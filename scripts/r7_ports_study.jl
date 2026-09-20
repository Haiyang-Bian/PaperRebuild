using PaperRebuild, JuMP, TOML, SHA
const PORT_ROOT=normpath(joinpath(@__DIR__, ".."))
if length(ARGS)>=3 && ARGS[1]=="run"
    if ARGS[3]=="open"
        using HiGHS, Clarabel
    elseif ARGS[3]=="gurobi"
        using Gurobi
    end
end

function port_read(dir)
    wrapper=Module(gensym(:PortEvidence))
    Base.include(wrapper, abspath(joinpath(dir, "code/replay.jl")))
    x=Base.invokelatest(getfield, wrapper, :x)
    mod=Base.invokelatest(
        () -> getfield(
            wrapper,
            isdefined(wrapper, :FrozenR7Thermal) ? :FrozenR7Thermal :
            isdefined(wrapper, :FrozenR7Planning) ? :FrozenR7Planning : :FrozenR7,
        ),
    )
    (; x, mod)
end

function port_manifest(dir; exclude = Set(["files.toml"]))
    Dict(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(dir) for
        f in fs if !(replace(relpath(joinpath(p, f), dir), '\\'=>'/') in exclude)
    )
end

function port_freeze(dir)
    ispath(dir)&&error("不覆盖端口研究输入")
    rule=TOML.parsefile(joinpath(PORT_ROOT, "configs/r7/ports-study.toml"))
    old=joinpath(PORT_ROOT, "results/summaries/r7-thermal-20260920-v1/evidence")
    records=Dict{String,Any}[]
    sources=Dict{String,Any}[]
    for (group, original) in zip(
        rule["recovery_groups"],
        [
            "recovery-hand_n1_same_dispatch",
            "nested_witness_1_n1_same_dispatch",
            "nested_witness_2_n1_same_dispatch",
        ],
    )
        path=joinpath(old, original)
        archive=port_read(path).x
        case=with_r7_port_temperature_bounds(R7RecoveryCase(archive.case.data))
        evidence=Dict(
            "group"=>group,
            "path"=>replace(relpath(path, PORT_ROOT), '\\'=>'/'),
            "files_sha256"=>bytes2hex(sha256(read(joinpath(path, "files.toml")))),
            "parent"=>archive.parent,
            "spec"=>archive.spec,
            "old_case"=>archive.case.data,
            "case"=>case.data,
            "profiles"=>archive.spec["profiles"],
        )
        push!(sources, evidence)
        for fault in rule["faults"], solver in rule["recovery_solvers"]
            push!(
                records,
                Dict(
                    "id"=>"$(group)_fault$(only(fault))_$(lowercase(solver))",
                    "kind"=>"recovery",
                    "group"=>group,
                    "solver"=>solver,
                    "fault"=>fault,
                    "case"=>case.data,
                    "case_sha256"=>case.sha256,
                ),
            )
        end
    end
    normal=load_r7_normal_case(joinpath(PORT_ROOT, "configs/r7/normal-reserve-hand.toml"))
    for limit in rule["planning_thresholds_MWh"]
        spec=TOML.parsefile(joinpath(PORT_ROOT, "configs/r7/planning-reserve-hand.toml"))
        spec["recovery_model"]=rule["version"]
        foreach(e->e["loss_limit_MWh"]=limit, spec["events"])
        c=R7PlanningCase(normal, spec)
        for solver in ("HiGHS", "Gurobi"), method in rule[lowercase(solver)*"_planning_methods"]
            label=limit==0 ? "zero_loss" : "allow_full_heat"
            push!(
                records,
                Dict(
                    "id"=>"$(label)_$(lowercase(solver))_$method",
                    "kind"=>"planning",
                    "group"=>label,
                    "solver"=>solver,
                    "method"=>method,
                    "normal"=>normal.data,
                    "specification"=>spec,
                    "case_sha256"=>c.sha256,
                ),
            )
        end
    end
    length(records)==28 || error("端口冻结清单数量错误")
    mkpath(dir)
    write(
        joinpath(dir, "inputs.toml"),
        PaperRebuild.r7_text(Dict("records"=>records, "sources"=>sources)),
    )
    write(joinpath(dir, "rule.toml"), PaperRebuild.r7_text(rule))
    cp(@__FILE__, joinpath(dir, "study-source.jl"))
    science=merge(PaperRebuild.r7_planning_science_paths(), PaperRebuild.r7_thermal_science_paths())
    for (p, f) in science
        target=joinpath(dir, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    write(
        joinpath(dir, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "schema"=>"r7-ports-freeze-v1",
                "files"=>port_manifest(dir),
                "science"=>Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in science),
            ),
        ),
    )
    println(
        "28 records frozen before optimization; three inherited inputs and two separate planning thresholds.",
    )
end

function port_frozen(dir; current = false)
    d=TOML.parsefile(joinpath(dir, "freeze.toml"))
    d["schema"]=="r7-ports-freeze-v1" || error("冻结身份错误")
    for (p, h) in d["files"]
        !isabspath(p)&&!occursin(':', p)&&all(s->!(s in ("", ".", "..")), split(p, '/')) ||
            error("冻结路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("冻结文件改变")
    end
    if current
        paths=merge(
            PaperRebuild.r7_planning_science_paths(),
            PaperRebuild.r7_thermal_science_paths(),
        )
        Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in paths)==d["science"] ||
            error("运行科学源码与预冻结不符")
        read(@__FILE__)==read(joinpath(dir, "study-source.jl")) || error("协议入口改变")
    end
    TOML.parsefile(joinpath(dir, "inputs.toml")), TOML.parsefile(joinpath(dir, "rule.toml"))
end

function port_optimizer(name)
    name=="HiGHS" && return optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    name=="Clarabel" && return Clarabel.Optimizer
    name=="Gurobi" && return optimizer_with_attributes(
        Gurobi.Optimizer,
        "OutputFlag"=>0,
        "Threads"=>1,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-9,
        "DualReductions"=>0,
    )
    error("未声明求解器")
end

function port_run(dir, group)
    group in ("open", "gurobi") || error("运行组错误")
    input, rule=port_frozen(dir; current = true)
    todo=filter(r->(r["solver"]=="Gurobi") == (group=="gurobi"), input["records"])
    all(!ispath(joinpath(dir, "records", r["id"])) for r in todo) ||
        error("该组已有记录，不覆盖或静默重跑")
    for item in todo
        started=time()
        dest=joinpath(dir, "records", item["id"])
        opt=port_optimizer(item["solver"])
        if item["kind"]=="recovery"
            c=R7RecoveryCase(item["case"])
            fixed=item["solver"]=="Clarabel" ? 1 .- item["fault"] : nothing
            r=solve_r7_recovery(
                c,
                item["fault"];
                optimizer = opt,
                fixed_z = fixed,
                budget_sec = max(0, rule["budget_sec"]-(time()-started)),
            )
            save_r7_recovery(c, r, dest)
            if item["solver"]==rule["thermal_followup_solver"] && r["candidate_accepted"]
                source=only(filter(s->s["group"]==item["group"], input["sources"]))
                spec=r7_thermal_spec(
                    c,
                    r;
                    profiles = source["profiles"],
                    profile_origin = "frozen original thermal study spatial state",
                    substeps = rule["thermal_substeps"],
                    mode = Symbol(rule["thermal_mode"]),
                )
                q=solve_r7_thermal_reconstruction(
                    c,
                    r,
                    spec;
                    optimizer = opt,
                    budget_sec = max(0, rule["budget_sec"]-(time()-started)),
                )
                save_r7_thermal_reconstruction(c, r, spec, q, joinpath(dir, "thermal", item["id"]))
            end
        else
            c=R7PlanningCase(R7NormalCase(item["normal"]), item["specification"])
            r=solve_r7_planning(
                c;
                optimizer = opt,
                method = Symbol(item["method"]),
                budget_sec = max(0, rule["budget_sec"]-(time()-started)),
            )
            save_r7_planning(c, r, dest)
        end
        println(item["id"], " ", r["status"])
        flush(stdout)
    end
    write(
        joinpath(dir, group*"-complete.toml"),
        PaperRebuild.r7_text(Dict("records"=>[x["id"] for x in todo])),
    )
    println("$group completed without overwriting any old result.")
end

function port_tables(dir)
    input, rule=port_frozen(dir)
    summary=IOBuffer()
    proof=IOBuffer()
    heat=IOBuffer()
    println(
        summary,
        "record,kind,group,solver,run_id,status,adopted_pass,objective_kind,objective,lower_bound,conditional_optimality,elapsed_sec",
    )
    println(proof, "record,run_id,applicable,minimum_heat_loss_MWh,hard_shedding_conflict,reason")
    println(
        heat,
        "record,run_id,substeps,status,thermal_pass,same_dispatch_pass,heat_unserved_MWh,max_normalized_residual",
    )
    allvalues=Dict{String,Any}()
    for item in input["records"]
        evidence=port_read(joinpath(dir, "records", item["id"]))
        x=evidence.x
        r=x.result
        q=x.validation
        x.case.sha256==item["case_sha256"] || error("运行与冻结输入不同")
        if item["kind"]=="recovery"
            isequal(x.case.data, item["case"])&&r["fault"]==item["fault"] ||
                error("恢复配对因素改变")
            p=Base.invokelatest(
                Base.invokelatest(getfield, evidence.mod, :r7_island_heat_bound),
                x.case,
                r["fault"],
            )
            println(
                proof,
                join(
                    [
                        item["id"],
                        r["run_id"],
                        p["applicable"],
                        get(p, "minimum_heat_loss_MWh", ""),
                        get(p, "hard_shedding_conflict", ""),
                        p["reason"],
                    ],
                    ',',
                ),
            )
            pass=q["model_pass"]
            obj=get(q, "loss_MWh", "")
            lower=get(r, "lower_bound_MWh", "")
            optimal=q["optimality_pass"]
            if item["solver"]==rule["thermal_followup_solver"] && pass
                hx=port_read(joinpath(dir, "thermal", item["id"])).x
                isequal(hx.parent, r) || error("详细热回代父记录不同")
                source=only(filter(s->s["group"]==item["group"], input["sources"]))
                isequal(hx.spec["profiles"], source["profiles"]) &&
                hx.spec["mode"]==rule["thermal_mode"] &&
                hx.spec["substeps"]==rule["thermal_substeps"] || error("详细热回代边界改变")
                hq=hx.validation
                println(
                    heat,
                    join(
                        [
                            item["id"],
                            hx.result["run_id"],
                            hx.spec["substeps"],
                            hx.result["status"],
                            hq["thermal_model_pass"],
                            hq["same_dispatch_pass"],
                            get(hq, "heat_unserved_MWh", ""),
                            get(hq, "max_normalized_residual", ""),
                        ],
                        ',',
                    ),
                )
            end
        else
            isequal(x.case.normal.data, item["normal"]) &&
            isequal(x.case.specification, item["specification"]) &&
            r["method"]==item["method"] || error("规划配对因素改变")
            pass=q["robust_model_pass"]
            obj=get(q, "cost_USD", "")
            lower=get(q, "lower_bound_USD", "")
            optimal=q["conditional_optimality_pass"]
        end
        println(
            summary,
            join(
                [
                    item["id"],
                    item["kind"],
                    item["group"],
                    item["solver"],
                    r["run_id"],
                    r["status"],
                    pass,
                    item["kind"]=="recovery" ? "expected_unserved_MWh" : "normal_cost_USD",
                    obj,
                    lower,
                    optimal,
                    r["elapsed_sec"],
                ],
                ',',
            ),
        )
        allvalues[item["id"]]=(item = item, result = r, validation = q)
    end
    pairs=IOBuffer()
    println(
        pairs,
        "group,fault,first,second,relative_objective_difference,both_model_pass,A2_value_pass",
    )
    for group in rule["recovery_groups"], fault in rule["faults"], alt in ("clarabel", "gurobi")
        first=allvalues["$(group)_fault$(only(fault))_highs"]
        second=allvalues["$(group)_fault$(only(fault))_$alt"]
        pass=first.validation["model_pass"] && second.validation["model_pass"]
        diff=pass ?
             abs(first.validation["loss_MWh"]-second.validation["loss_MWh"])/max(
            1,
            abs(first.validation["loss_MWh"]),
        ) : ""
        println(
            pairs,
            join(
                [
                    group,
                    only(fault),
                    first.result["run_id"],
                    second.result["run_id"],
                    diff,
                    pass,
                    pass&&diff<=1e-4,
                ],
                ',',
            ),
        )
    end
    Dict(
        "summary.csv"=>String(take!(summary)),
        "island-bound.csv"=>String(take!(proof)),
        "thermal.csv"=>String(take!(heat)),
        "solver-pairs.csv"=>String(take!(pairs)),
    )
end

function port_report(source, dest)
    ispath(dest)&&error("不覆盖端口报告")
    tables=port_tables(source)
    cp(source, dest)
    for (p, t) in tables
        write(joinpath(dest, p), t)
    end
    write(joinpath(dest, "files.toml"), PaperRebuild.r7_text(Dict("files"=>port_manifest(dest))))
    println(
        "28 original method runs and declared heat follow-ups frozen; no repeated optimization.",
    )
end

function port_check(dir)
    files=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    port_manifest(dir)==files || error("端口报告集合或哈希改变")
    for (p, t) in port_tables(dir)
        read(joinpath(dir, p), String)==t || error("端口报告原值重验失败")
    end
    println(
        "28 frozen inputs, original models, analytic bounds, thermal follow-ups and paired tables checked.",
    )
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==2 && ARGS[1]=="freeze"
        port_freeze(abspath(ARGS[2]))
    elseif length(ARGS)==3 && ARGS[1]=="run"
        port_run(abspath(ARGS[2]), ARGS[3])
    elseif length(ARGS)==3 && ARGS[1]=="report"
        port_report(abspath(ARGS[2]), abspath(ARGS[3]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        port_check(abspath(ARGS[2]))
    else
        error(
            "usage: r7_ports_study.jl freeze NEW | run BATCH open|gurobi | report RAW NEW_REPORT | check REPORT",
        )
    end
end
