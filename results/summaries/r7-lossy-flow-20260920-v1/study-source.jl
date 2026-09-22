include("r7_flow_planning_study.jl")

function lossy_study_input(rule, group, control, UA)
    old, s0=joint_study_input(rule, group, control)
    d=deepcopy(old.normal.data)
    d["battery_rule"]=rule["battery_rule"]
    d["name"]*="_exclusive_UA$(Int(UA))"
    for p in d["heat"]["pipes"]
        p["UA_S_W_K"], p["UA_R_W_K"]=UA, UA
    end
    c=R7PlanningCase(R7NormalCase(d), old.specification)
    kwargs=Dict(
        Symbol(k)=>PaperRebuild.r7_unpack(s0["normal_flow"], k) for
        k in ("pipe_min", "pipe_max", "source_min", "source_max", "load_min", "load_max")
    )
    ns=r7_normal_flow_spec(
        c.normal;
        kwargs...,
        thermal = :lossy_gauss,
        quadrature_order = rule["quadrature_order"],
        max_truncation_error = rule["max_truncation_error"],
    )
    bounds=Dict(
        PaperRebuild.r7_planning_pair_key(p)=>PaperRebuild.r7_joint_bounds(s0, p) for
        p in PaperRebuild.r7_planning_pairs(c)
    )
    c,
    r7_flow_planning_spec(
        c;
        normal_flow = ns,
        recovery_bounds = bounds,
        substeps = rule["substeps"],
    )
end

function lossy_freeze(dest)
    ispath(dest)&&error("不覆盖有损规划冻结目录")
    rule=TOML.parsefile(joinpath(JOINT_ROOT, "configs/r7/lossy-flow-study.toml"))
    records=Dict{String,Any}[]
    for UA in rule["UA_values_W_K"],
        group in rule["groups"],
        control in rule["controls"],
        solver in (control=="prescribed" ? ["HiGHS", "Gurobi"] : ["Gurobi"])

        c, s=lossy_study_input(rule, group, control, UA)
        push!(
            records,
            Dict(
                "id"=>"ua$(Int(UA))_"*group*"_"*control*"_"*lowercase(solver),
                "group"=>group*"_ua$(Int(UA))",
                "safety_group"=>group,
                "control"=>control,
                "solver"=>solver,
                "UA_W_K"=>UA,
                "battery_rule"=>rule["battery_rule"],
                "normal"=>c.normal.data,
                "planning"=>c.specification,
                "spec"=>s,
                "case_sha256"=>c.sha256,
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            ),
        )
    end
    length(records)==rule["record_count"] || error("冻结数量错误")
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
                "seed"=>"deterministic_no_sampling",
                "git_head"=>strip(joint_capture(`git -C $JOINT_ROOT rev-parse HEAD`)),
                "git_status"=>joint_capture(`git -C $JOINT_ROOT status --porcelain`),
            ),
        ),
    )
    cp(@__FILE__, joinpath(dest, "study-source.jl"))
    for (p, f) in PaperRebuild.r7_flow_planning_science_paths()
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    common=joinpath(dest, "code", "scripts", "r7_flow_planning_study.jl")
    mkpath(dirname(common))
    cp(joinpath(@__DIR__, "r7_flow_planning_study.jl"), common)
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>joint_manifest(dest),
                "science"=>PaperRebuild.r7_flow_planning_science_hashes(),
            ),
        ),
    )
    println("24 lossy/exclusive planning runs frozen before formal optimization.")
end

function lossy_current_check(dir)
    items, rule=joint_inputs(dir)
    f=TOML.parsefile(joinpath(dir, "freeze.toml"))
    f["science"]==PaperRebuild.r7_flow_planning_science_hashes() || error("有损科学源码改变")
    read(@__FILE__)==read(joinpath(dir, "study-source.jl")) || error("有损编排改变")
    read(joinpath(@__DIR__, "r7_flow_planning_study.jl"))==read(
        joinpath(dir, "code", "scripts", "r7_flow_planning_study.jl"),
    ) || error("共用报告源码改变")
    items, rule
end

function lossy_run(dir, solver)
    items, rule=lossy_current_check(dir)
    pending=filter(x->x["solver"]==solver, items)
    isempty(pending)&&error("未声明求解器组")
    any(ispath(joinpath(dir, "records", x["id"])) for x in pending)&&error("不覆盖已开始的组")
    for x in pending
        lossy_current_check(dir)
        c=R7PlanningCase(R7NormalCase(x["normal"]), x["planning"])
        r=solve_r7_flow_planning(
            c,
            x["spec"];
            optimizer = joint_optimizer(solver),
            budget_sec = rule["budget_sec"],
        )
        save_r7_flow_planning(c, x["spec"], r, joinpath(dir, "records", x["id"]))
        println(
            x["id"],
            " status=",
            r["status"],
            " accepted=",
            r["candidate_accepted"],
            " cost=",
            get(r["validation"], "cost_USD", "missing"),
            " error=",
            get(r, "error", "none"),
        )
        flush(stdout)
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    isempty(ARGS)&&error(
        "usage: r7_lossy_flow_study.jl freeze DIR | run DIR HiGHS/Gurobi | report SRC NEW | check REPORT",
    )
    if ARGS[1]=="freeze"&&length(ARGS)==2
        lossy_freeze(abspath(ARGS[2]))
    elseif ARGS[1]=="run"&&length(ARGS)==3
        ARGS[3] in ("HiGHS", "Gurobi") || error("未声明求解器")
        Core.eval(@__MODULE__, ARGS[3]=="Gurobi" ? :(using Gurobi) : :(using HiGHS))
        Base.invokelatest(lossy_run, abspath(ARGS[2]), ARGS[3])
    elseif ARGS[1] in ("report", "check")
        Core.eval(@__MODULE__, :(using CSV))
        if ARGS[1]=="report"&&length(ARGS)==3
            Base.invokelatest(joint_report, abspath(ARGS[2]), abspath(ARGS[3]))
        elseif ARGS[1]=="check"&&length(ARGS)==2
            Base.invokelatest(joint_check, abspath(ARGS[2]))
        else
            error("有损报告参数错误")
        end
    else
        error("有损命令参数错误")
    end
end
