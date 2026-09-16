# 固定的一轮R2对照；每个运行独立落盘，整个批次不覆盖旧结果。
let depot = normpath(joinpath(@__DIR__, "..", ".julia"))
    isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
end
const R2_EXPERIMENT_ROOT = normpath(joinpath(@__DIR__, ".."))
push!(LOAD_PATH, R2_EXPERIMENT_ROOT)
using PaperRebuild, JuMP, Clarabel, TOML, Dates, UUIDs
budget_arg = findfirst(a -> startswith(a, "--budget="), ARGS)
budget = isnothing(budget_arg) ? 60.0 : parse(Float64, split(ARGS[budget_arg], '=')[2])
0 < budget <= 600 || error("每实例预算限于(0,600]秒")
batch = "r2-study-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
batchdir = joinpath(R2_EXPERIMENT_ROOT, "results", "runs", batch);
mkdir(batchdir)
entries = Dict{String,Any}[]
commercial = nothing;
license_state = "available"
try
    @eval import Gurobi
    global environment = Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    global commercial =
        () -> begin
            op = Gurobi.Optimizer(environment)
            for (key, val) in (
                "Threads"=>1,
                "Seed"=>0,
                "NonConvex"=>2,
                "FeasibilityTol"=>1e-9,
                "OptimalityTol"=>1e-9,
                "BarConvTol"=>1e-10,
                "MIPGap"=>1e-6,
            )
                MOI.set(op, MOI.RawOptimizerAttribute(key), val)
            end
            op
        end
catch err
    message = lowercase(sprint(showerror, err))
    if occursin("license", message)
        global license_state = "not_run_license"
    elseif err isa ArgumentError && occursin("package", message)
        global license_state = "dependency_missing"
    else
        rethrow()
    end
end
jobs = [
    ("single-fixed-open", "single-source", R2Spec(), true, true),
    ("single-fixed-gurobi", "single-source", R2Spec(), true, false),
    ("single-wmm", "single-source", R2Spec(), false, false),
    ("single-schpd", "single-source", R2Spec(; formulation = :schpd_mc_v1), false, false),
    ("two-wmm", "two-source", R2Spec(), false, false),
    ("two-schpd", "two-source", R2Spec(; formulation = :schpd_mc_v1), false, false),
    ("two-fixed-enumeration", "two-source", R2Spec(; formulation = :schpd_mc_v1), true, true),
    ("two-fixed-mip", "two-source", R2Spec(; formulation = :schpd_mc_v1), true, false),
    ("ablation-heat-envelope", "single-source", R2Spec(; heat_balance = :mc), false, false),
    ("ablation-reference-loss", "single-source", R2Spec(; loss = :reference), false, false),
    (
        "ablation-temperature",
        "single-source",
        R2Spec(; dynamics = :fv, loss = :dynamic),
        false,
        false,
    ),
    ("ablation-mixing", "two-source", R2Spec(; mixing = :dominant), false, false),
    ("literal-wmm", "single-source", R2Spec(; formulation = :wmm_literal), false, true),
    ("literal-schpd", "single-source", R2Spec(; formulation = :schpd_literal), false, true),
]
manifest_path = joinpath(batchdir, "study.toml")
function save_manifest()
    open(
        io -> TOML.print(
            io,
            Dict(
                "batch"=>batch,
                "budget_per_instance_sec"=>budget,
                "license_status"=>license_state,
                "origin"=>"synthetic",
                "runs"=>entries,
            );
            sorted = true,
        ),
        manifest_path,
        "w",
    )
end
save_manifest()
for (name, file, spec, fixed, open_solver) in jobs
    if !open_solver && isnothing(commercial)
        push!(entries, Dict("name"=>name, "status"=>license_state))
        save_manifest()
        continue
    end
    c = load_r2_case(joinpath(R2_EXPERIMENT_ROOT, "configs", "r2", file*".toml"))
    logpath = open_solver ? nothing : joinpath(batchdir, name*"-solver.log")
    println("START ", name)
    flush(stdout)
    r = solve_r2_case(
        c;
        spec,
        optimizer = open_solver ? Clarabel.Optimizer : commercial,
        fixed_flows = fixed,
        enumerate_mixing = open_solver,
        budget_sec = budget,
        solver_log = logpath,
    )
    r["study_job"] = name
    dir = save_r2_run(c, r; root = joinpath(R2_EXPERIMENT_ROOT, "results", "runs"))
    !isnothing(logpath) && isfile(logpath) && cp(logpath, joinpath(dir, "solver.log"))
    v = validate_r2_solution(c, r)
    entry = Dict{String,Any}(
        "name"=>name,
        "directory"=>replace(relpath(dir, R2_EXPERIMENT_ROOT), '\\'=>'/'),
        "status"=>r["status"],
        "model_pass"=>v.model_pass,
        "original_physics_pass"=>v.original_physics_pass,
    )
    for key in ("objective", "bound", "relative_gap", "elapsed_sec", "class")
        haskey(r, key) && (entry[key] = r[key])
    end
    push!(entries, entry)
    save_manifest()
    println(
        "DONE ",
        name,
        " ",
        r["status"],
        " model=",
        v.model_pass,
        " objective=",
        get(r, "objective", "missing"),
    )
    flush(stdout)
end
println("R2_STUDY=", replace(relpath(manifest_path, R2_EXPERIMENT_ROOT), '\\'=>'/'))
