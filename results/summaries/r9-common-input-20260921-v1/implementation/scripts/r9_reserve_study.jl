# 预算覆盖导入、冻结输入读取、构建、求解、独立验算和保存。
const R9_RESERVE_PROCESS_START=time_ns()/1e9
module R9ReserveStudy
using TOML, SHA, Dates, JuMP, HiGHS
const ROOT=normpath(joinpath(@__DIR__, ".."))
clock() = time_ns()/1e9
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function safe(root, rel)
    isabspath(rel)||occursin(':', rel)||occursin('\\', rel) ? error("Invalid relative path") :
    nothing
    all(x->!isempty(x)&&x ∉ (".", ".."), split(rel, '/')) || error("Invalid relative path")
    p=abspath(root)
    for part in split(rel, '/')
        p=joinpath(p, part)
        islink(p) && error("Frozen source cannot be a symlink")
    end
    p
end
function inventory(root)
    files=String[]
    for (dir, dirs, names) in walkdir(root)
        any(islink(joinpath(dir, n)) for n in vcat(dirs, names)) && error("Symlink in evidence")
        for name in names
            push!(files, replace(relpath(joinpath(dir, name), root), '\\'=>'/'))
        end
    end
    sort(files)
end
function science_files()
    files=["src/networks/fixed_flow_heat.jl"]
    for name in ("market", "dispatch"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    append!(
        files,
        ["src/verification/r5_dispatch_duality.jl", "src/formulations/r5_dispatch_dual.jl"],
    )
    for name in ("commitment", "risk"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    append!(
        files,
        [
            "src/core/r6_protocol.jl",
            "src/algorithms/r6_data.jl",
            "src/reporting/r6_data.jl",
            "src/core/r9_inputs.jl",
            "src/core/r9_pv.jl",
            "src/core/r9_reserve.jl",
            "src/verification/r9_reserve.jl",
            "src/core/r9_risk.jl",
        ],
    )
    files
end
function library(code)
    wrapper=Module(gensym(:R9ReserveWrapper))
    Base.include(wrapper, joinpath(code, "study-library.jl"))
    Base.invokelatest(getfield, wrapper, :FrozenReserve)
end
call(lib, name, args...; kwargs...) =
    Base.invokelatest(Base.invokelatest(getfield, lib, name), args...; kwargs...)

"""先冻结独立抽样与原始数值、再允许三方案优化；不覆盖旧批次。"""
function freeze(out; root = ROOT)
    VERSION==v"1.12.6" || error("Freeze with Julia 1.12.6")
    ispath(out) && error("Preserve previous study")
    science=science_files()
    source=vcat(
        science,
        [
            "scripts/r9_reserve_study.jl",
            "scripts/run_r9_reserve_batch.jl",
            "configs/r9/reserve-protocol.toml",
            "configs/r9/reserve-study.toml",
            "configs/r9/reserve-trajectories.toml",
            "docs/reading/ch07/inputs.toml",
            "docs/reading/ch07/topology.toml",
            "docs/reading/ch07/reported-results.toml",
            "Project.toml",
            "Manifest.toml",
            "tools/solvers/Project.toml",
            "tools/solvers/Manifest.toml",
        ],
    )
    hashes=Dict(rel=>hashfile(safe(root, rel)) for rel in source)
    mkpath(out)
    for rel in source
        target=safe(out, "code/"*rel)
        mkpath(dirname(target))
        cp(safe(root, rel), target)
        hashfile(target)==hashes[rel] || error("Concurrent source change")
    end
    write(
        joinpath(out, "code/study-library.jl"),
        "module FrozenReserve\nusing JuMP,TOML,SHA,Dates,UUIDs,CSV,Random\n" *
        join("include(\"$rel\")\n" for rel in science) *
        "end\n",
    )
    lib=library(joinpath(out, "code"))
    println("Frozen library loaded; generating independent trajectories.")
    flush(stdout)
    spec=call(lib, :load_r9_reserve_study, joinpath(out, "code/configs/r9/reserve-study.toml"))
    p=call(lib, :load_r6_protocol, joinpath(out, "code/configs/r9/reserve-trajectories.toml"))
    p.data["clustering"]["count"]==spec.data["support_count"] || error("Support count mismatch")
    template=call(
        lib,
        :r9_reserve_template,
        joinpath(out, "code/docs/reading/ch07"),
        joinpath(out, "code/configs/r9/reserve-protocol.toml"),
    )
    sets=Dict(
        s=>call(lib, :r6_generate_trajectories, p, s) for s in ("train", "validation", "test")
    )
    reps=call(lib, :r6_fit_representatives, sets["train"], p)
    println("Training representatives fitted; converged=", reps["converged"])
    flush(stdout)
    reps["converged"] || error("Training clustering did not converge")
    call(
        lib,
        :save_r6_dataset,
        joinpath(out, "data"),
        p,
        sets,
        reps;
        provenance = Dict(
            "usage"=>"R9 three-scheme input only; R6 schema labels do not execute methods",
            "market_solver_or_strategy_used"=>false,
            "source_hashes"=>hashes,
        ),
    )
    toml(joinpath(out, "template.toml"), template.data)
    toml(joinpath(out, "input-audit.toml"), call(lib, :audit_r9_reserve_input, template))
    methods=Dict{String,Any}[]
    for pilot in (true, false), scheme in spec.data["schemes"]
        println("Freezing input identity: ", scheme, " pilot=", pilot)
        flush(stdout)
        c=call(lib, :r9_reserve_risk_case, template, sets["train"], reps, spec, scheme; pilot)
        push!(
            methods,
            Dict(
                "id"=>(pilot ? "pilot4-" : "full100-")*lowercase(scheme),
                "scheme"=>scheme,
                "pilot"=>pilot,
                "case_sha256"=>c.sha256,
                "scenarios"=>length(c.data["commitment"]["scenarios"]),
            ),
        )
    end
    all(hashfile(safe(root, rel))==h for (rel, h) in hashes) ||
        error("Source changed while freezing")
    manifest=Dict(
        "schema"=>"r9-reserve-frozen-study-v1",
        "origin"=>"synthetic",
        "protocol_sha256"=>spec.sha256,
        "template_sha256"=>template.sha256,
        "source_hashes"=>hashes,
        "methods"=>methods,
        "optimization_performed_at_freeze"=>false,
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "git_commit"=>readchomp(`git -C $root rev-parse HEAD`),
        "git_status"=>read(`git -C $root status --porcelain=v1`, String),
        "files"=>Dict(rel=>hashfile(safe(out, rel)) for rel in inventory(out)),
    )
    toml(joinpath(out, "manifest.toml"), manifest)
    write(joinpath(out, "manifest.sha256"), hashfile(joinpath(out, "manifest.toml"))*"\n")
    println(
        "Frozen 2000/500/1000 complete days, 100 representatives, 3 schemes and 3 pilot cases; no optimization.",
    )
    manifest
end

"""只读核验全部数值、源码及训练聚类；不重新抽样、不读取样本外优化结果。"""
function check(out)
    hashfile(joinpath(out, "manifest.toml"))==strip(
        read(joinpath(out, "manifest.sha256"), String),
    ) || error("Manifest changed")
    m=TOML.parsefile(joinpath(out, "manifest.toml"))
    m["schema"]=="r9-reserve-frozen-study-v1" && !m["optimization_performed_at_freeze"] ||
        error("Study identity")
    Set(inventory(out))==union(Set(keys(m["files"])), Set(["manifest.toml", "manifest.sha256"])) ||
        error("Study file inventory changed")
    for (rel, h) in m["files"]
        hashfile(safe(out, rel))==h || error("Frozen bytes changed: $rel")
    end
    for (rel, h) in m["source_hashes"]
        m["files"]["code/"*rel]==h || error("Source identity mismatch")
    end
    lib=library(joinpath(out, "code"))
    dataset=call(lib, :read_r6_dataset, joinpath(out, "data"))
    spec=call(lib, :load_r9_reserve_study, joinpath(out, "code/configs/r9/reserve-study.toml"))
    template=call(lib, :R5DispatchCase, TOML.parsefile(joinpath(out, "template.toml")))
    spec.sha256==m["protocol_sha256"] && template.sha256==m["template_sha256"] ||
        error("Input identity")
    length(m["methods"])==6 && allunique(e["id"] for e in m["methods"]) || error("Method inventory")
    expected=Set((scheme, pilot) for scheme in spec.data["schemes"] for pilot in (true, false))
    Set((e["scheme"], e["pilot"]) for e in m["methods"])==expected ||
        error("Incomplete factorial methods")
    (; lib, dataset, spec, template, manifest = m)
end

function gurobi_factory()
    # 本地可选环境；仅求解时申请许可，冻结/重读无需商业求解器。
    env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    optimizer_with_attributes(
        ()->Gurobi.Optimizer(env),
        "Threads"=>1,
        "Seed"=>23,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-9,
        "DualReductions"=>0,
    )
end

"""从冻结源码运行单个方法；预算和负结果独立保存，不重试或换输入。"""
function solve(out, id, target; process_start = clock())
    ispath(target) && error("Preserve previous result")
    mkpath(target)
    status=Dict{String,Any}(
        "schema"=>"r9-reserve-method-status-v1",
        "method_id"=>id,
        "status"=>"started",
        "started_utc"=>string(now(UTC)),
        "complete_process_budget_sec"=>600.0,
    )
    toml(joinpath(target, "status.toml"), status)
    try
        bundle=check(out)
        status["frozen_input_read_sec"]=clock()-process_start
        lib, spec=bundle.lib, bundle.spec
        entry=only(e for e in bundle.manifest["methods"] if e["id"]==id)
        hashfile(@__FILE__)==bundle.manifest["files"]["code/scripts/r9_reserve_study.jl"] ||
            error("Use frozen runner")
        status["study_manifest_sha256"]=hashfile(joinpath(out, "manifest.toml"))
        status["scheme"], status["pilot"], status["scenario_count"]=entry["scheme"],
        entry["pilot"],
        entry["scenarios"]
        c=call(
            lib,
            :r9_reserve_risk_case,
            bundle.template,
            bundle.dataset.sets["train"],
            bundle.dataset.representatives,
            spec,
            entry["scheme"];
            pilot = entry["pilot"],
        )
        c.sha256==entry["case_sha256"] || error("Input differs from pre-optimization freeze")
        status["case_build_sec"]=clock()-process_start-status["frozen_input_read_sec"]
        status["case_sha256"]=c.sha256
        depot=joinpath(pwd(), ".julia")
        isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
        path=joinpath(out, "code/tools/solvers")
        path in LOAD_PATH || push!(LOAD_PATH, path)
        @eval using Gurobi
        opt=Base.invokelatest(gurobi_factory)
        oracle=optimizer_with_attributes(
            HiGHS.Optimizer,
            "threads"=>1,
            "primal_feasibility_tolerance"=>1e-9,
            "dual_feasibility_tolerance"=>1e-9,
        )
        remaining=spec.data["budget_sec"]-(clock()-process_start)-spec.data["archive_reserve_sec"]
        remaining>0 || error("Budget exhausted before optimization")
        status["preparation_sec"]=clock()-process_start
        toml(joinpath(target, "status.toml"), status)
        pattern=entry["scheme"]=="3A" ? zeros(Int, entry["scenarios"]) : nothing
        r=call(
            lib,
            :solve_r5_risk,
            c;
            optimizer = opt,
            oracle_optimizer = oracle,
            pattern,
            budget_sec = remaining,
        )
        status["solve_and_validation_sec"]=clock()-process_start-status["preparation_sec"]
        archive_start=clock()
        call(lib, :save_r5_risk_run, c, r, joinpath(target, "run"))
        verified=call(lib, :read_r5_risk_run, joinpath(target, "run"))
        status["save_and_reread_sec"]=clock()-archive_start
        status["status"]=r["status"]
        for k in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
            status[k]=verified.validation[k]
        end
        for k in (
            "nominal_net_cost",
            "worst_net_cost",
            "worst_violation_probability",
            "selected_violation_bound",
            "relative_gap",
        )
            haskey(verified.validation, k) && (status[k]=verified.validation[k])
        end
        status["cost_optimization_complete"]=r["cost_optimization_complete"]
    catch err
        status["status"]=occursin(
            r"(?i)license|licence|expired|not licensed",
            sprint(showerror, err),
        ) ? "license_unavailable" :
                         occursin("Budget exhausted", sprint(showerror, err)) ?
                         "budget_exhausted_before_optimization" : "execution_error"
        open(io->showerror(io, err, catch_backtrace()), joinpath(target, "failure.txt"), "w")
    end
    status["elapsed_sec"]=clock()-process_start
    status["budget_pass"]=status["elapsed_sec"]<=status["complete_process_budget_sec"]
    toml(joinpath(target, "status.toml"), status)
    println(
        "Method ",
        id,
        ": ",
        status["status"],
        " model=",
        get(status, "model_pass", false),
        " risk=",
        get(status, "risk_pass", false),
        " seconds=",
        status["elapsed_sec"],
    )
    status
end

function main(args; process_start = clock())
    length(args)>=2 || error("usage: freeze|check STUDY; run STUDY ID NEW_OUTPUT")
    action=args[1]
    if action=="freeze" && length(args)==2
        freeze(abspath(args[2]))
    elseif action=="check" && length(args)==2
        check(abspath(args[2]))
        println("Frozen data and source check passed; no optimization")
    elseif action=="run" && length(args)==4
        solve(abspath(args[2]), args[3], abspath(args[4]); process_start)
    else
        error("Unknown action/arguments")
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    R9ReserveStudy.main(ARGS; process_start = R9_RESERVE_PROCESS_START)
end
