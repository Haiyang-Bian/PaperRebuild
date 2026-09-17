# 正式运行使用冻结配置；每个案例/批次独立，不覆盖旧证据。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Clarabel
include("r3_setup.jl")
root = normpath(joinpath(@__DIR__, ".."))
studyfile = joinpath(root, "configs", "r3", "study.toml")
study = TOML.parsefile(studyfile)
budget_arg = findfirst(a->startswith(a, "--budget="), ARGS)
budget =
    isnothing(budget_arg) ? study["budget_per_instance_sec"] :
    parse(Float64, split(ARGS[budget_arg], '=')[2])
0<budget<=600 || error("每实例预算限于(0,600]秒")
selected = filter(a->!startswith(a, "--"), ARGS)
all(id -> any(e["id"]==id for e in study["runs"]), selected) || error("未知案例ID")
factory = nothing
license_status = "available"
if !("--open" in ARGS)
    try
        @eval import Gurobi
        global factory = r3_gurobi_factory(Gurobi)
    catch err
        text = lowercase(sprint(showerror, err))
        if occursin("license", text)
            global license_status = "not_run_license"
        elseif occursin("package", text)
            global license_status = "dependency_missing"
        else
            rethrow()
        end
    end
else
    license_status = "not_requested"
end
batch = "r3-study-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
batchdir = joinpath(root, "results", "runs", batch)
mkdir(batchdir)
entries = Dict{String,Any}[]
function save_study()
    open(
        io->TOML.print(
            io,
            Dict(
                "batch"=>batch,
                "origin"=>"synthetic",
                "budget_per_instance_sec"=>budget,
                "configuration_sha256"=>bytes2hex(sha256(read(studyfile))),
                "license_status"=>license_status,
                "runs"=>entries,
            );
            sorted = true,
        ),
        joinpath(batchdir, "study.toml"),
        "w",
    )
end
save_study()
for entry in study["runs"]
    isempty(selected) || entry["id"] in selected || continue
    c, m = r3_study_case(entry)
    result = solve_r3_feasibility(
        c;
        optimizer = factory,
        convex_optimizer = Clarabel.Optimizer,
        initial_flow = m,
        budget_sec = budget,
    )
    result["solver_setup_status"] = license_status
    path = save_r3_run(c, result; root = batchdir, run_id = batch*"_"*entry["id"])
    verified = read_r3_run(path)
    push!(
        entries,
        Dict(
            "id"=>entry["id"],
            "directory"=>basename(path),
            "case"=>entry["case"],
            "initialization"=>entry["initialization"],
            "status"=>result["status"],
            "physical_pass"=>verified.validation.physical_pass,
        ),
    )
    save_study()
    println(
        entry["id"],
        " ",
        result["status"],
        " physical=",
        verified.validation.physical_pass,
        " elapsed=",
        round(result["elapsed_sec"]; digits = 2),
    )
end
println("R3_STUDY=", joinpath(batchdir, "study.toml"))
