using PaperRebuild, JuMP, TOML, SHA, Dates
include("r7_transport_study.jl")
const LINKED_ROOT=normpath(joinpath(@__DIR__, ".."))
const LINKED_MODULES=Dict{String,Module}()

# 文件重定向避免受限Windows宿主的匿名管道EBADF；Git只读查询原样保存。
function linked_capture(cmd)
    mktempdir(joinpath(LINKED_ROOT, "tmp")) do dir
        out, err=joinpath(dir, "out.txt"), joinpath(dir, "err.txt")
        run(pipeline(cmd; stdin = devnull, stdout = out, stderr = err))
        read(out, String)
    end
end

"""读取保存原值及冻结的验证器；不调用优化器。"""
function linked_read(path)
    key=PaperRebuild.r7_digest(
        TOML.parsefile(joinpath(path, "result.toml"))["source_hashes_at_solve"],
    )
    if !haskey(LINKED_MODULES, key)
        wrapper=Module(gensym(:LinkedEvidence))
        Base.include(wrapper, abspath(joinpath(path, "code/replay.jl")))
        LINKED_MODULES[key]=Base.invokelatest(getfield, wrapper, :FrozenR7Linked)
        return Base.invokelatest(getfield, wrapper, :x)
    end
    mod=LINKED_MODULES[key]
    Base.invokelatest(Base.invokelatest(getfield, mod, :read_r7_linked_planning), path)
end

function linked_case(rule, group, n)
    hand=group=="original_hand"
    d=TOML.parsefile(joinpath(LINKED_ROOT, rule[hand ? "cases_hand" : "cases_reserve"]))
    events=TOML.parsefile(joinpath(LINKED_ROOT, rule[hand ? "events_hand" : "events_reserve"]))
    group in rule["groups"] || error("未声明的规划输入")
    group=="healthy_diagnostic" && (d["electric"]["fault_budget"]=0)
    if group=="reserve_heat_limit"
        for e in events["events"]
            e["loss_limit_MWh"]=d["dt_h"]*sum(
                d["heat"]["load_MW"][j][t] for j in 1:d["heat"]["nodes"] for
                t in e["event_start"]:(e["event_start"]+e["periods"]-1)
            )
        end
    end
    c=R7PlanningCase(R7NormalCase(d), events)
    # 本批只有一条内部电线和一对热管；不将此给定策略冒充通用故障控制。
    length(d["electric"]["lines"])==length(d["heat"]["pipes"])==1 || error("协议仅支持原双节点案例")
    flows=Dict{String,Any}()
    for pair in PaperRebuild.r7_planning_pairs(c)
        e=events["events"][pair.event]
        times=e["event_start"]:(e["event_start"]+e["periods"]-1)
        live=all(iszero, pair.fault)
        T=e["periods"]
        h=d["heat"]
        flows[PaperRebuild.r7_planning_pair_key(pair)]=Dict(
            "m_pipe"=>reshape(
                [live ? only(h["pipes"])["normal_flow_kg_s"][t] : 0.0 for t in times],
                1,
                T,
            ),
            "m_source"=>[
                live ? h["source_flow_kg_s"][j][t] : 0.0 for j in 1:h["nodes"], t in times
            ],
            "m_load"=>[live ? h["load_flow_kg_s"][j][t] : 0.0 for j in 1:h["nodes"], t in times],
        )
    end
    c, r7_linked_planning_spec(c; flows, substeps = n)
end

function linked_freeze(dest)
    ispath(dest)&&error("不覆盖详细规划冻结目录")
    rule=TOML.parsefile(joinpath(LINKED_ROOT, "configs/r7/linked-study.toml"))
    records=Dict{String,Any}[]
    function add(group, method, solver, n, kind)
        c, s=linked_case(rule, group, n)
        push!(
            records,
            Dict(
                "id"=>"$(group)_$(method)_$(lowercase(solver))_n$n",
                "group"=>group,
                "method"=>method,
                "solver"=>solver,
                "kind"=>kind,
                "normal"=>c.normal.data,
                "planning"=>c.specification,
                "spec"=>s,
                "case_sha256"=>c.sha256,
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            ),
        )
    end
    for group in rule["groups"], method in rule["methods"], solver in rule["main_solvers"]
        add(group, method, solver, rule["substeps"], "main")
    end
    for group in rule["refinement_groups"],
        n in rule["refinement_substeps"],
        method in rule["methods"]

        add(group, method, "HiGHS", n, "refinement")
    end
    length(records)==rule["record_count"] &&
    length(unique(r["id"] for r in records))==length(records) || error("冻结数量/身份错误")
    sources=Dict(
        p=>bytes2hex(sha256(read(joinpath(LINKED_ROOT, p)))) for
        p in [rule[k] for k in ("cases_hand", "events_hand", "cases_reserve", "events_reserve")]
    )
    mkpath(dest)
    write(
        joinpath(dest, "inputs.toml"),
        PaperRebuild.r7_text(Dict("records"=>records, "sources"=>sources)),
    )
    write(joinpath(dest, "rule.toml"), PaperRebuild.r7_text(rule))
    write(
        joinpath(dest, "environment.toml"),
        PaperRebuild.r7_text(
            Dict(
                "utc"=>string(now(UTC)),
                "julia_version"=>string(VERSION),
                "origin"=>"synthetic",
                "git_head"=>strip(linked_capture(`git -C $LINKED_ROOT rev-parse HEAD`)),
                "git_status"=>linked_capture(`git -C $LINKED_ROOT status --porcelain`),
                "entry"=>"scripts/r7_linked_study.jl",
                "seed"=>"deterministic_no_sampling",
            ),
        ),
    )
    cp(@__FILE__, joinpath(dest, "study-source.jl"))
    cp(joinpath(@__DIR__, "r7_transport_study.jl"), joinpath(dest, "transport-study-source.jl"))
    for (p, f) in PaperRebuild.r7_linked_science_paths()
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>transport_manifest(dest),
                "science"=>PaperRebuild.r7_linked_science_hashes(),
            ),
        ),
    )
    println(
        "24 shared-state planning inputs, protocol and source frozen before formal optimization.",
    )
end

function linked_inputs(dir; current = false)
    frozen=TOML.parsefile(joinpath(dir, "freeze.toml"))
    for (p, h) in frozen["files"]
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("冻结路径非法")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("详细规划冻结内容改变")
    end
    if current
        frozen["science"]==PaperRebuild.r7_linked_science_hashes() || error("科学源码与预冻结不符")
        read(@__FILE__)==read(joinpath(dir, "study-source.jl")) || error("编排源码与预冻结不符")
        read(joinpath(@__DIR__, "r7_transport_study.jl"))==read(
            joinpath(dir, "transport-study-source.jl"),
        ) || error("编排依赖与预冻结不符")
    end
    TOML.parsefile(joinpath(dir, "inputs.toml")), TOML.parsefile(joinpath(dir, "rule.toml"))
end

function linked_run(dir, group)
    group in ("open", "gurobi") || error("求解组错误")
    input, rule=linked_inputs(dir; current = true)
    todo=filter(r->(r["solver"]=="Gurobi") == (group=="gurobi"), input["records"])
    any(ispath(joinpath(dir, "records", r["id"])) for r in todo)&&error("已有记录，不覆盖或重开")
    for item in todo
        c=R7PlanningCase(R7NormalCase(item["normal"]), item["planning"])
        r=solve_r7_linked_planning(
            c,
            item["spec"];
            optimizer = transport_optimizer(item["solver"]),
            method = Symbol(item["method"]),
            budget_sec = rule["budget_sec"],
        )
        save_r7_linked_planning(c, item["spec"], r, joinpath(dir, "records", item["id"]))
        println(
            item["id"],
            " ",
            r["status"],
            " accepted=",
            r["candidate_accepted"],
            " cost=",
            get(r["validation"], "cost_USD", "unavailable"),
        )
        flush(stdout)
    end
end

function linked_csv(io, values)
    println(io, join(["\""*replace(string(v), '"'=>"\"\"")*"\"" for v in values], ','))
end

function linked_tables(dir)
    input, rule=linked_inputs(dir)
    freeze=TOML.parsefile(joinpath(dir, "freeze.toml"))
    tables=Dict(
        name=>IOBuffer() for name in (
            "summary.csv",
            "iterations.csv",
            "events.csv",
            "normal-state.csv",
            "event-state.csv",
            "residuals.csv",
            "paired.csv",
        )
    )
    println(
        tables["summary.csv"],
        "record,group,method,solver,substeps,run_id,status,model_pass,cost_USD,lower_bound_USD,cost_complete,iterations,elapsed_sec",
    )
    println(
        tables["iterations.csv"],
        "record,run_id,iteration,status,normal_pass,robust_pass,cost_USD,lower_bound_USD,included,added,elapsed_sec",
    )
    println(
        tables["events.csv"],
        "record,run_id,iteration,key,kind,model_pass,loss_MWh,electric_loss_MWh,heat_loss_MWh,limit_MWh,prefix_residual_K,max_thermal_normalized_residual",
    )
    println(tables["normal-state.csv"], "record,run_id,scenario,quantity,index,time_h,value,unit")
    println(
        tables["event-state.csv"],
        "record,run_id,iteration,key,pipe,side,scenario,segment,mass_kg,base_K,amplitude_K,rate_per_kg,from_left",
    )
    println(
        tables["residuals.csv"],
        "record,run_id,iteration,key,scope,equation,index,t,scenario,residual,unit,tolerance,pass",
    )
    println(
        tables["paired.csv"],
        "factor,left_record,right_record,left_run_id,right_run_id,same_input,both_pass,cost_difference_USD,relative_difference,A2_pass",
    )
    checks=Dict{String,Any}()
    function rows(item, r, iteration, key, scope, values)
        for v in values
            linked_csv(
                tables["residuals.csv"],
                [
                    item["id"],
                    r["run_id"],
                    iteration,
                    key,
                    scope*"/"*get(v, "scope", "adopted"),
                    v["id"],
                    get(v, "entity", get(v, "object", "")),
                    get(v, "t", get(v, "step", 0)),
                    v["scenario"],
                    v["residual"],
                    v["unit"],
                    v["tolerance"],
                    v["pass"],
                ],
            )
        end
    end
    for item in input["records"]
        x=linked_read(joinpath(dir, "records", item["id"]))
        r, q=x.result, x.validation
        x.case.normal.data==item["normal"] &&
        x.case.specification==item["planning"] &&
        x.case.sha256==item["case_sha256"] &&
        x.spec==item["spec"] &&
        r["method"]==item["method"] &&
        r["source_hashes_at_solve"]==freeze["science"] || error("正式运行身份与预冻结不同")
        checks[item["id"]]=(item = item, result = r, check = q)
        linked_csv(
            tables["summary.csv"],
            [
                item["id"],
                item["group"],
                item["method"],
                item["solver"],
                x.spec["substeps"],
                r["run_id"],
                r["status"],
                q["robust_model_pass"],
                get(q, "cost_USD", ""),
                get(q, "lower_bound_USD", ""),
                q["conditional_optimality_pass"],
                length(r["iterations"]),
                r["elapsed_sec"],
            ],
        )
        for (i, it) in enumerate(r["iterations"])
            m=it["master"]
            iq=q["iterations"][i]
            mq=iq["master"]
            linked_csv(
                tables["iterations.csv"],
                [
                    item["id"],
                    r["run_id"],
                    i,
                    m["status"],
                    mq["normal_pass"],
                    iq["robust_model_pass"],
                    get(mq, "cost_USD", ""),
                    get(m, "lower_bound_USD", ""),
                    length(m["included"]),
                    length(it["added_pairs"]),
                    m["elapsed_sec"],
                ],
            )
            if haskey(mq, "normal_check")
                rows(item, r, i, "normal", "normal", mq["normal_check"]["rows"])
            end
            for audit in it["audits"]
                key=PaperRebuild.r7_planning_pair_key((
                    event = audit["event"],
                    fault = audit["fault"],
                ))
                for p in audit["event_evidence"]["initial_pipe_profiles"],
                    (k, z) in enumerate(p["segments"])

                    linked_csv(
                        tables["event-state.csv"],
                        [
                            item["id"],
                            r["run_id"],
                            i,
                            key,
                            p["pipe"],
                            p["side"],
                            p["scenario"],
                            k,
                            z["mass_kg"],
                            z["base_K"],
                            z["amplitude_K"],
                            z["rate_per_kg"],
                            z["from_left"],
                        ],
                    )
                end
            end
            for (kind, events) in
                (("master_witness", mq["witness_checks"]), ("fault_optimization", iq["audits"]))
                for e in events
                    eq=e["check"]
                    event=parse(Int, first(split(e["key"], ':')))
                    linked_csv(
                        tables["events.csv"],
                        [
                            item["id"],
                            r["run_id"],
                            i,
                            e["key"],
                            kind,
                            eq["model_pass"],
                            get(eq, "loss_MWh", ""),
                            get(eq, "loss_electric_MWh", ""),
                            get(eq, "loss_heat_MWh", ""),
                            x.case.specification["events"][event]["loss_limit_MWh"],
                            get(e, "prefix_residual_K", ""),
                            get(get(eq, "thermal", Dict()), "max_normalized_residual", ""),
                        ],
                    )
                    if haskey(eq, "thermal")
                        rows(item, r, i, e["key"], "thermal", eq["thermal"]["rows"])
                        rows(item, r, i, e["key"], "shared", eq["shared"]["rows"])
                    end
                end
            end
        end
        if q["robust_model_pass"]
            normal=r["iterations"][q["candidate_iteration"]]["master"]["normal"]
            for (quantity, unit, shift) in (("E_BES", "MWh", 1), ("τ_S", "K", 0), ("τ_R", "K", 0))
                v=PaperRebuild.r7_unpack(normal["values"], quantity)
                for j in axes(v, 1), t in axes(v, 2), w in axes(v, 3)
                    quantity=="E_BES"&&x.case.normal.data["devices"][j]["kind"]!="BES"&&continue
                    linked_csv(
                        tables["normal-state.csv"],
                        [
                            item["id"],
                            r["run_id"],
                            w,
                            quantity,
                            j,
                            (t-shift)*x.case.normal.data["dt_h"],
                            v[j, t, w],
                            unit,
                        ],
                    )
                end
            end
        end
    end
    for a in input["records"], b in input["records"]
        a["id"]<b["id"] || continue
        a["case_sha256"]==b["case_sha256"]&&a["spec_sha256"]==b["spec_sha256"] || continue
        factor=a["solver"]==b["solver"]&&a["method"]!=b["method"] ? "method" :
               a["method"]==b["method"]&&a["solver"]!=b["solver"] ? "solver" : ""
        isempty(factor)&&continue
        x, y=checks[a["id"]], checks[b["id"]]
        both=x.check["robust_model_pass"]&&y.check["robust_model_pass"]
        delta=both ? y.check["cost_USD"]-x.check["cost_USD"] : NaN
        relative=both ? abs(delta)/max(1, abs(x.check["cost_USD"])) : NaN
        passed=both&&relative<=1e-4&&x.check["conditional_optimality_pass"]&&y.check["conditional_optimality_pass"]
        linked_csv(
            tables["paired.csv"],
            [
                factor,
                a["id"],
                b["id"],
                x.result["run_id"],
                y.result["run_id"],
                true,
                both,
                both ? delta : "",
                both ? relative : "",
                passed,
            ],
        )
    end
    Dict(name=>String(take!(io)) for (name, io) in tables)
end

function linked_report(source, dest)
    ispath(dest)&&error("不覆盖详细规划报告")
    tables=linked_tables(source)
    cp(source, dest)
    for (name, value) in tables
        write(joinpath(dest, name), value)
    end
    write(
        joinpath(dest, "files.toml"),
        PaperRebuild.r7_text(Dict("files"=>transport_manifest(dest))),
    )
    println("24 detailed shared-state planning records archived from original values.")
end

function linked_check(dir)
    transport_manifest(dir)==TOML.parsefile(joinpath(dir, "files.toml"))["files"] ||
        error("详细规划报告改变")
    for (name, value) in linked_tables(dir)
        read(joinpath(dir, name), String)==value || error("详细规划原值与摘要不同")
    end
    println("Linked planning evidence rechecked with frozen source; no optimization.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2&&ARGS[1]=="freeze" ? linked_freeze(abspath(ARGS[2])) :
    length(ARGS)==3&&ARGS[1]=="run" ? linked_run(abspath(ARGS[2]), ARGS[3]) :
    length(ARGS)==3&&ARGS[1]=="report" ? linked_report(abspath(ARGS[2]), abspath(ARGS[3])) :
    length(ARGS)==2&&ARGS[1]=="check" ? linked_check(abspath(ARGS[2])) :
    error(
        "usage: r7_linked_study.jl freeze NEW | run FROZEN open|gurobi | report RAW NEW | check REPORT",
    )
end
