using PaperRebuild, JuMP, TOML, SHA, Dates, CSV
include("r8_cases.jl")
include("r8_archive.jl")
const R8_ROOT=normpath(joinpath(@__DIR__, ".."))
function r8_capture(cmd)
    mktempdir(joinpath(R8_ROOT, "tmp")) do d
        out=joinpath(d, "stdout")
        run(pipeline(cmd; stdin = devnull, stdout = out, stderr = joinpath(d, "stderr")))
        read(out, String)
    end
end
function r8_study_records(rule)
    records=Dict{String,Any}[]
    function add(family, resource, control, mode, limit, solver)
        x=r8_mechanism_input(R8_ROOT, family; UA = rule["UA_W_K"], resource, control)
        s=r8_spec(
            x.case,
            x.flow;
            mode,
            limits_MWh = fill(limit, 2),
            penalty_USD_MWh = rule["penalty_USD_MWh"],
            topology = x.topology,
            heat_preparation = x.heat_preparation,
        )
        id=join(
            (
                family,
                resource,
                control,
                String(mode),
                "L"*replace(string(limit), '.'=>'p'),
                lowercase(solver),
            ),
            "_",
        )
        push!(
            records,
            Dict(
                "id"=>id,
                "family"=>family,
                "resource"=>resource,
                "control"=>control,
                "mode"=>String(mode),
                "limit_MWh"=>limit,
                "solver"=>solver,
                "normal"=>x.case.normal.data,
                "planning"=>x.case.specification,
                "flow"=>x.flow,
                "spec"=>s,
                "case_sha256"=>x.case.sha256,
                "flow_sha256"=>PaperRebuild.r7_digest(x.flow),
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            ),
        )
    end
    for solver in ("HiGHS", "Gurobi")
        add("legacy", "all", "fixed", :economic, 0.4, solver)
        add("legacy", "all", "fixed", :penalty, 0.4, solver)
        for limit in rule["legacy_thresholds_MWh"]
            add("legacy", "all", "fixed", :threshold, limit, solver)
        end
    end
    for mode in (:economic, :penalty)
        add("tie_three", "all", "fixed", mode, 0.4, "Gurobi")
    end
    for limit in rule["tie_thresholds_MWh"]
        add("tie_three", "all", "fixed", :threshold, limit, "Gurobi")
    end
    for resource in rule["resource_variants"], solver in ("HiGHS", "Gurobi")
        add("tie_three", resource, "fixed", :threshold, rule["resource_threshold_MWh"], solver)
    end
    for mode in (:economic, :penalty, :threshold)
        add("tie_three", "all", "joint_continuous", mode, 0.4, "Gurobi")
    end
    add("legacy", "all", "joint_continuous", :threshold, 0.4, "Gurobi")
    length(records)==rule["record_count"] || error("R8运行清单数量错误")
    records
end
function r8_study_freeze(dest)
    ispath(dest)&&error("不覆盖R8冻结目录")
    rule=TOML.parsefile(joinpath(R8_ROOT, "configs/r8/tradeoff-study.toml"))
    records=r8_study_records(rule)
    mkpath(dest)
    write(joinpath(dest, "inputs.toml"), PaperRebuild.r7_text(Dict("records"=>records)))
    write(joinpath(dest, "rule.toml"), PaperRebuild.r7_text(rule))
    write(
        joinpath(dest, "environment.toml"),
        PaperRebuild.r7_text(
            Dict(
                "origin"=>"synthetic",
                "utc"=>string(now(UTC)),
                "julia_version"=>string(VERSION),
                "git_head"=>strip(r8_capture(`git -C $R8_ROOT rev-parse HEAD`)),
                "git_status"=>r8_capture(`git -C $R8_ROOT status --porcelain`),
                "seed"=>"deterministic_no_sampling",
            ),
        ),
    )
    for (p, f) in PaperRebuild.r8_science_paths()
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    for p in ("r8_cases.jl", "r8_archive.jl", "r8_tradeoff_study.jl")
        cp(joinpath(@__DIR__, p), joinpath(dest, p))
    end
    module_text="module FrozenR8\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
                join("include(\"$p\")\n" for p in PaperRebuild.r8_includes()) *
                "end\n"
    write(joinpath(dest, "code/frozen-module.jl"), module_text)
    write(
        joinpath(dest, "code/replay.jl"),
        "include(\"../r8_archive.jl\")\nx=r8_archive_check(joinpath(@__DIR__,\"..\"))\nprintln(length(x.records),\" frozen R8 records checked\")\n",
    )
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict("files"=>r8_archive_files(dest), "science"=>PaperRebuild.r8_science_hashes()),
        ),
    )
    println(length(records), " R8 inputs and source frozen before optimization.")
end
function r8_current_freeze(dir)
    xs, rule, registry=r8_archive_inputs(dir)
    registry["science"]==PaperRebuild.r8_science_hashes() || error("R8正式科学源码已变化")
    for p in ("r8_cases.jl", "r8_archive.jl", "r8_tradeoff_study.jl")
        read(joinpath(dir, p))==read(joinpath(@__DIR__, p)) || error("R8编排已变化")
    end
    xs, rule
end
function r8_study_optimizer(solver)
    solver=="HiGHS" && return optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "mip_rel_gap"=>1e-9,
        "mip_feasibility_tolerance"=>1e-8,
        "primal_feasibility_tolerance"=>1e-8,
    )
    solver=="Gurobi" || error("未知R8求解器")
    optimizer_with_attributes(
        Gurobi.Optimizer,
        "Threads"=>1,
        "NonConvex"=>2,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-8,
        "DualReductions"=>0,
    )
end
function r8_study_run(dir, solver)
    items, rule=r8_current_freeze(dir)
    pending=filter(x->x["solver"]==solver, items)
    isempty(pending)&&error("未知求解器组")
    any(ispath(joinpath(dir, "records", x["id"])) for x in pending)&&error("不覆盖已开始组")
    for x in pending
        r8_current_freeze(dir)
        c=R7PlanningCase(R7NormalCase(x["normal"]), x["planning"])
        r=solve_r8_case(
            c,
            x["flow"],
            x["spec"];
            optimizer = r8_study_optimizer(solver),
            budget_sec = rule["budget_sec"],
        )
        path=joinpath(dir, "records", x["id"])
        stage=path*".writing"
        ispath(stage)&&error("已有未完成记录，不自动覆盖")
        mkpath(stage)
        write(joinpath(stage, "result.toml"), PaperRebuild.r7_text(r))
        write(
            joinpath(stage, "files.toml"),
            PaperRebuild.r7_text(Dict("files"=>r8_archive_files(stage))),
        )
        mv(stage, path)
        println(
            x["id"],
            " primary=",
            r["primary"]["status"],
            " accepted=",
            r["validation"]["primary_model_pass"],
            " cost=",
            get(r["validation"]["primary"], "normal_cost_USD", "missing"),
            " eval=",
            get(get(r, "evaluation", Dict()), "status", "missing"),
            " error=",
            get(r["primary"], "error", "none"),
        )
        flush(stdout)
    end
end
function r8_study_tables(x)
    rows=NamedTuple[]
    events=NamedTuple[]
    for item in x.items
        r=x.records[item["id"]].result
        p=r["validation"]["primary"]
        e=get(r["validation"], "evaluation", Dict())
        loss=get(e, "event_upper_MWh", nothing)
        push!(
            rows,
            (
                id = item["id"],
                run_id = r["run_id"],
                family = item["family"],
                resource = item["resource"],
                control = item["control"],
                mode = item["mode"],
                limit_MWh = item["limit_MWh"],
                solver = item["solver"],
                primary_status = r["primary"]["status"],
                primary_model_pass = p["model_pass"],
                objective_complete = p["objective_complete"],
                normal_cost_USD = get(p, "normal_cost_USD", missing),
                objective_value = get(p, "objective_value", missing),
                objective_kind = r["primary"]["objective_kind"],
                objective_bound = get(r["primary"], "objective_lower_bound", missing),
                relative_gap = get(p, "relative_gap", missing),
                evaluation_status = get(get(r, "evaluation", Dict()), "status", "not_run"),
                evaluation_pass = get(e, "model_pass", false),
                risk_complete = get(e, "objective_complete", false),
                threshold_pass = r["validation"]["threshold_pass"],
                worst_upper_MWh = loss===nothing ? missing : maximum(loss),
                elapsed_sec = r["elapsed_sec"],
                wall_budget_pass = r["wall_budget_pass"],
            ),
        )
        if loss!==nothing
            for j in eachindex(loss)
                push!(
                    events,
                    (
                        id = item["id"],
                        run_id = r["run_id"],
                        event = j,
                        upper_MWh = loss[j],
                        lower_MWh = get(e, "event_lower_MWh", fill(missing, length(loss)))[j],
                        certified = get(e, "event_optimality_pass", falses(length(loss)))[j],
                        electric_at_worst_MWh = e["event_electric_at_worst_MWh"][j],
                        heat_at_worst_MWh = e["event_heat_at_worst_MWh"][j],
                    ),
                )
            end
        end
    end
    (; rows, events)
end
function r8_study_report(src, dest)
    ispath(dest)&&error("不覆盖R8报告")
    x=r8_archive_check(src)
    tables=r8_study_tables(x)
    cp(src, dest)
    CSV.write(joinpath(dest, "summary.csv"), tables.rows)
    CSV.write(joinpath(dest, "events.csv"), tables.events)
    write(
        joinpath(dest, "report-hashes.toml"),
        PaperRebuild.r7_text(Dict("files"=>r8_archive_files(dest))),
    )
    println("R8 report saved from ", length(x.records), " independently replayed records.")
end
if abspath(PROGRAM_FILE)==@__FILE__
    isempty(ARGS)&&error(
        "usage: r8_tradeoff_study.jl freeze NEW | run FROZEN HiGHS/Gurobi | report SRC NEW | check REPORT",
    )
    if ARGS[1]=="freeze" && length(ARGS)==2
        r8_study_freeze(abspath(ARGS[2]))
    elseif ARGS[1]=="run" && length(ARGS)==3
        ARGS[3] in ("HiGHS", "Gurobi") || error("未声明求解器")
        Core.eval(@__MODULE__, ARGS[3]=="HiGHS" ? :(using HiGHS) : :(using Gurobi))
        Base.invokelatest(r8_study_run, abspath(ARGS[2]), ARGS[3])
    elseif ARGS[1]=="report" && length(ARGS)==3
        r8_study_report(abspath(ARGS[2]), abspath(ARGS[3]))
    elseif ARGS[1]=="check" && length(ARGS)==2
        x=r8_archive_check(abspath(ARGS[2]))
        println(length(x.records), " R8 records independently checked.")
    else
        error("R8命令参数错误")
    end
end
