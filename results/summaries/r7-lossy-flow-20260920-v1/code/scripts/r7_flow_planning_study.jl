using PaperRebuild, JuMP, TOML, SHA, Dates
const JOINT_ROOT=normpath(joinpath(@__DIR__, ".."))
const JOINT_MODULES=Dict{String,Module}()
joint_hash(p) = bytes2hex(sha256(read(p)))
joint_manifest(dir) = Dict(
    replace(relpath(joinpath(p, f), dir), '\\'=>'/')=>joint_hash(joinpath(p, f)) for
    (p, _, fs) in walkdir(dir) for f in fs
)
function joint_capture(cmd)
    mktempdir(joinpath(JOINT_ROOT, "tmp")) do dir
        out, err=joinpath(dir, "out"), joinpath(dir, "err")
        run(pipeline(cmd; stdin = devnull, stdout = out, stderr = err))
        read(out, String)
    end
end
function joint_study_input(rule, group, control)
    d=TOML.parsefile(joinpath(JOINT_ROOT, rule["normal_input"]))
    group=="healthy_zero_loss"&&(d["electric"]["fault_budget"]=0)
    rules=TOML.parsefile(joinpath(JOINT_ROOT, rule["planning_input"]))
    limit=group=="all_faults_heat_limit" ? rule["heat_loss_limit_MWh"] : 0.0
    foreach(e->e["loss_limit_MWh"]=limit, rules["events"])
    c=R7PlanningCase(R7NormalCase(d), rules)
    h=d["heat"]
    arrays=Dict(
        "pipe"=>reduce(vcat, permutedims(p["normal_flow_kg_s"]) for p in h["pipes"]),
        "source"=>reduce(vcat, permutedims.(h["source_flow_kg_s"])),
        "load"=>reduce(vcat, permutedims.(h["load_flow_kg_s"])),
    )
    kwargs=Dict{Symbol,Any}()
    for (kind, x) in arrays
        cap=kind=="pipe" ? [p["flow_max_kg_s"] for p in h["pipes"]] : h[kind*"_flow_max"]
        lo, hi=copy(x), copy(x)
        if control=="joint_continuous"
            for I in CartesianIndices(x)
                lo[I]=x[I]>0 ? rule["positive_floor_kg_s"] : 0.0
                hi[I]=x[I]>0 ? cap[I[1]] : 0.0
            end
        end
        kwargs[Symbol(kind*"_min")], kwargs[Symbol(kind*"_max")]=lo, hi
    end
    ns=r7_normal_flow_spec(c.normal; kwargs...)
    bounds=Dict{String,Any}()
    length(h["pipes"])==1 && h["nodes"]==2 || error("本冻结规则只适用于预先声明的单管双节点例")
    for pair in PaperRebuild.r7_planning_pairs(c)
        T=rules["events"][pair.event]["periods"]
        flow=any(==(1), pair.fault) ? 0.0 : 5.0
        b=Dict{String,Any}()
        for (kind, x) in (
            "pipe"=>fill(flow, 1, T),
            "source"=>vcat(fill(flow, 1, T), zeros(1, T)),
            "load"=>vcat(zeros(1, T), fill(flow, 1, T)),
        )
            cap=kind=="pipe" ? [p["flow_max_kg_s"] for p in h["pipes"]] : h[kind*"_flow_max"]
            b[kind*"_min"]=control=="prescribed" ? x : zeros(size(x))
            b[kind*"_max"]=control=="prescribed" ? x : repeat(reshape(cap, :, 1), 1, T)
        end
        bounds[PaperRebuild.r7_planning_pair_key(pair)]=b
    end
    c,
    r7_flow_planning_spec(
        c;
        normal_flow = ns,
        recovery_bounds = bounds,
        substeps = rule["substeps"],
    )
end
function joint_freeze(dest)
    ispath(dest)&&error("不覆盖联合流量冻结目录")
    rule=TOML.parsefile(joinpath(JOINT_ROOT, "configs/r7/flow-planning-study.toml"))
    records=Dict{String,Any}[]
    for group in rule["groups"],
        control in rule["controls"],
        solver in (control=="prescribed" ? ["HiGHS", "Gurobi"] : ["Gurobi"])

        c, s=joint_study_input(rule, group, control)
        push!(
            records,
            Dict(
                "id"=>group*"_"*control*"_"*lowercase(solver),
                "group"=>group,
                "control"=>control,
                "solver"=>solver,
                "normal"=>c.normal.data,
                "planning"=>c.specification,
                "spec"=>s,
                "case_sha256"=>c.sha256,
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            ),
        )
    end
    length(records)==rule["record_count"] || error("联合冻结数量错误")
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
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>joint_manifest(dest),
                "science"=>PaperRebuild.r7_flow_planning_science_hashes(),
            ),
        ),
    )
    println("Twelve joint-flow comparisons frozen before formal optimization.")
end
function joint_inputs(dir; current = false)
    f=TOML.parsefile(joinpath(dir, "freeze.toml"))
    for (p, h) in f["files"]
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("冻结路径非法")
        joint_hash(joinpath(dir, split(p, '/')...))==h || error("冻结内容已改变")
    end
    current&&f["science"]!=PaperRebuild.r7_flow_planning_science_hashes()&&error("科学源码已改变")
    current&&read(@__FILE__)!=read(joinpath(dir, "study-source.jl"))&&error("冻结编排已改变")
    TOML.parsefile(joinpath(dir, "inputs.toml"))["records"],
    TOML.parsefile(joinpath(dir, "rule.toml"))
end
function joint_optimizer(solver)
    if solver=="Gurobi"
        return optimizer_with_attributes(
            Gurobi.Optimizer,
            "Threads"=>1,
            "NonConvex"=>2,
            "FeasibilityTol"=>1e-9,
            "OptimalityTol"=>1e-9,
            "IntFeasTol"=>1e-9,
            "MIPGap"=>1e-8,
            "DualReductions"=>0,
        )
    elseif solver=="HiGHS"
        return optimizer_with_attributes(
            HiGHS.Optimizer,
            "threads"=>1,
            "primal_feasibility_tolerance"=>1e-9,
            "dual_feasibility_tolerance"=>1e-9,
            "mip_feasibility_tolerance"=>1e-9,
            "mip_rel_gap"=>1e-8,
        )
    end
    error("未声明求解器")
end
function joint_run(dir, solver)
    items, rule=joint_inputs(dir; current = true)
    todo=filter(x->x["solver"]==solver, items)
    isempty(todo)&&error("未声明求解器组")
    any(ispath(joinpath(dir, "records", x["id"])) for x in todo)&&error("不覆盖已开始的联合流量组")
    for x in todo
        joint_inputs(dir; current = true)
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
            " ",
            r["status"],
            " accepted=",
            r["candidate_accepted"],
            " complete=",
            r["domain_cost_complete"],
        )
        flush(stdout)
    end
end
function joint_frozen_read(record)
    files=TOML.parsefile(joinpath(record, "files.toml"))["files"]
    id=PaperRebuild.r7_digest(Dict(p=>h for (p, h) in files if startswith(p, "code/")))
    mod=get!(JOINT_MODULES, id) do
        m=Module(gensym(:R7JointFrozen))
        Core.eval(m, :(using JuMP, TOML, SHA, Dates, UUIDs))
        Core.eval(m, :(const MOI=JuMP.MOI))
        for p in PaperRebuild.r7_flow_planning_includes()
            joint_hash(joinpath(record, "code", split(p, '/')...))==files["code/"*p] ||
                error("冻结源码篡改")
            Base.include(m, joinpath(record, "code", split(p, '/')...))
        end
        m
    end
    Base.invokelatest(() -> getfield(mod, :read_r7_flow_planning)(record))
end
function joint_tables(dir)
    items, rule=joint_inputs(dir)
    summary=NamedTuple[]
    events=NamedTuple[]
    trajectories=NamedTuple[]
    residuals=NamedTuple[]
    for x in items
        rr=joint_frozen_read(joinpath(dir, "records", x["id"]))
        r, q=rr.result, rr.validation
        rr.case.sha256==x["case_sha256"]&&PaperRebuild.r7_digest(rr.spec)==x["spec_sha256"] ||
            error("运行与冻结输入不符")
        push!(
            summary,
            (
                id = x["id"],
                group = x["group"],
                control = x["control"],
                solver = x["solver"],
                run_id = r["run_id"],
                status = r["status"],
                model_pass = q["robust_model_pass"],
                cost_complete = q["domain_optimality_pass"],
                cost_USD = get(q, "cost_USD", missing),
                lower_bound_USD = get(r, "lower_bound_USD", missing),
                relative_gap = get(q, "relative_gap", missing),
                elapsed_sec = r["elapsed_sec"],
                model_class = get(r, "model_class", "unknown"),
                nonsimultaneous_pass = q["robust_model_pass"]&&q["normal_check"]["normal_validation"]["mutual_exclusivity_pass"] &&
                                       all(
                                           cq["shared"]["mutual_exclusivity_pass"] for
                                           cq in q["witness_checks"]
                                       ),
            ),
        )
        haskey(q, "normal_check") || continue
        function addrows(stage, rows)
            for z in rows
                push!(
                    residuals,
                    (
                        id = x["id"],
                        run_id = r["run_id"],
                        stage = stage,
                        formula = z["id"],
                        object = string(
                            get(
                                z,
                                "entity",
                                get(z, "element", get(z, "object", get(z, "key", ""))),
                            ),
                        ),
                        time = get(z, "t", get(z, "time", get(z, "step", 0))),
                        scenario = get(z, "scenario", 0),
                        residual = z["residual"],
                        tolerance = z["tolerance"],
                        unit = z["unit"],
                        pass = z["pass"],
                    ),
                )
            end
        end
        addrows("normal_flow", q["normal_check"]["rows"])
        if haskey(q["normal_check"], "normal_validation")
            addrows("normal", q["normal_check"]["normal_validation"]["rows"])
        end
        n=r["normal"]
        f=PaperRebuild.r7_unpack(n["flow_values"], "pipe")
        for a in axes(f, 1), t in axes(f, 2)
            push!(
                trajectories,
                (
                    id = x["id"],
                    run_id = r["run_id"],
                    stage = "normal",
                    event = 0,
                    fault = "none",
                    pipe = a,
                    time = t,
                    flow_kg_s = f[a, t],
                ),
            )
        end
        for (w, cq) in zip(r["witnesses"], q["witness_checks"])
            e=rr.case.specification["events"][w["event"]]
            push!(
                events,
                (
                    id = x["id"],
                    run_id = r["run_id"],
                    event = w["event"],
                    fault = join(w["fault"], ":"),
                    loss_limit_MWh = e["loss_limit_MWh"],
                    loss_MWh = get(cq, "loss_MWh", missing),
                    model_pass = cq["model_pass"],
                    threshold_pass = cq["threshold_pass"],
                    initial_profiles_sha256 = cq["initial_profiles_sha256"],
                ),
            )
            addrows("recovery_shared_"*cq["key"], cq["shared"]["rows"])
            addrows("recovery_boundary_"*cq["key"], cq["rows"])
            haskey(cq, "thermal")&&addrows("recovery_thermal_"*cq["key"], cq["thermal"]["rows"])
            m=PaperRebuild.r7_unpack(w["values"], "m_pipe")
            for a in axes(m, 1), t in axes(m, 2)
                push!(
                    trajectories,
                    (
                        id = x["id"],
                        run_id = r["run_id"],
                        stage = "recovery",
                        event = w["event"],
                        fault = join(w["fault"], ":"),
                        pipe = a,
                        time = e["event_start"]+t-1,
                        flow_kg_s = m[a, t],
                    ),
                )
            end
        end
    end
    (; summary, events, trajectories, residuals)
end
function joint_report(src, dest)
    ispath(dest)&&error("不覆盖联合流量报告")
    tables=joint_tables(src)
    mkpath(dest)
    for p in (
        "inputs.toml",
        "rule.toml",
        "environment.toml",
        "study-source.jl",
        "freeze.toml",
        "code",
        "records",
    )
        cp(joinpath(src, p), joinpath(dest, p))
    end
    for key in propertynames(tables)
        CSV.write(joinpath(dest, string(key)*".csv"), getproperty(tables, key))
    end
    write(
        joinpath(dest, "report-hashes.toml"),
        PaperRebuild.r7_text(Dict("files"=>joint_manifest(dest))),
    )
    println("Joint flow report and source-frozen original values saved.")
end
function joint_check(dir)
    h=TOML.parsefile(joinpath(dir, "report-hashes.toml"))["files"]
    actual=joint_manifest(dir)
    delete!(actual, "report-hashes.toml")
    actual==h || error("联合报告文件/字节改变")
    tables=joint_tables(dir)
    for k in propertynames(tables)
        io=IOBuffer()
        CSV.write(io, getproperty(tables, k))
        take!(io)==read(joinpath(dir, string(k)*".csv")) || error("原值重算表不同：$k")
    end
    println(
        "Joint report: ",
        length(tables.summary),
        " records and ",
        length(tables.residuals),
        " residuals independently replayed.",
    )
end
if abspath(PROGRAM_FILE)==@__FILE__
    isempty(ARGS)&&error(
        "usage: r7_flow_planning_study.jl freeze DIR | run DIR HiGHS/Gurobi | report SOURCE NEW | check REPORT",
    )
    action=ARGS[1]
    if action=="freeze"&&length(ARGS)==2
        joint_freeze(abspath(ARGS[2]))
    elseif action=="run"&&length(ARGS)==3
        ARGS[3] in ("HiGHS", "Gurobi") || error("未声明求解器")
        Core.eval(@__MODULE__, ARGS[3]=="Gurobi" ? :(using Gurobi) : :(using HiGHS))
        Base.invokelatest(joint_run, abspath(ARGS[2]), ARGS[3])
    elseif action=="report"&&length(ARGS)==3
        Core.eval(@__MODULE__, :(using CSV))
        Base.invokelatest(joint_report, abspath(ARGS[2]), abspath(ARGS[3]))
    elseif action=="check"&&length(ARGS)==2
        Core.eval(@__MODULE__, :(using CSV))
        Base.invokelatest(joint_check, abspath(ARGS[2]))
    else
        error("联合流量命令/参数错误")
    end
end
