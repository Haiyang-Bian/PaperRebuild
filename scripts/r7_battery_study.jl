using PaperRebuild, JuMP, TOML, SHA
include("r7_transport_study.jl")
const BATTERY_ROOT=normpath(joinpath(@__DIR__, ".."))

function battery_freeze(dest)
    ispath(dest)&&error("不覆盖电池冻结目录")
    rule=TOML.parsefile(joinpath(BATTERY_ROOT, "configs/r7/battery-study.toml"))
    parentdir=joinpath(BATTERY_ROOT, rule["parent"])
    old, _=transport_inputs(parentdir)
    parentmanifest=TOML.parsefile(joinpath(parentdir, "files.toml"))["files"]
    records=Dict{String,Any}[]
    parents=Dict{String,Any}()
    for item in old["records"]
        item["kind"] in ("main", "open_reference") || continue
        id=item["id"]
        path=joinpath(parentdir, "records", id)
        for name in ("case.toml", "spec.toml", "result.toml", "files.toml")
            key="records/$id/$name"
            bytes2hex(sha256(read(joinpath(path, name))))==parentmanifest[key] ||
                error("父记录改变")
        end
        parents[id]=Dict(
            "case"=>item["case"],
            "spec"=>item["spec"],
            "result"=>TOML.parsefile(joinpath(path, "result.toml")),
        )
        c=with_r7_battery_rule(R7RecoveryCase(item["case"]), rule["battery_rule"])
        s=deepcopy(item["spec"])
        s["case_sha256"]=c.sha256
        PaperRebuild.r7_transport_inputs(c, s)
        function add(kind, suffix; modes = nothing)
            r=Dict{String,Any}(
                "id"=>id*suffix,
                "parent_record"=>id,
                "kind"=>kind,
                "group"=>item["group"],
                "flow_label"=>item["flow_label"],
                "fault"=>item["fault"],
                "solver"=>item["solver"],
                "case"=>c.data,
                "spec"=>s,
                "case_sha256"=>c.sha256,
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            )
            modes===nothing ||
                (r["fixed_battery_modes"]=Dict(k=>PaperRebuild.r7_pack(v) for (k, v) in modes))
            push!(records, r)
        end
        if item["kind"]=="main"
            add("main", "")
        else
            bats=filter(g->g["kind"]=="BES", c.data["devices"])
            W=length(c.data["probabilities"])
            length(bats)==1 && c.data["periods"]==1 && W in (1, 2) ||
                error("本冻结协议只声明一或两位电池模式")
            for mask in 0:(2^W-1)
                modes=Dict(only(bats)["id"]=>reshape([(mask>>i)&1 for i in 0:(W-1)], 1, W))
                add("mode_enumeration", "_mode$mask"; modes)
            end
            add("ideal_reconstruction", "_reconstructed")
        end
    end
    count(r->r["kind"]!="ideal_reconstruction", records)==rule["optimized_record_count"] ||
        error("优化数量错误")
    count(r->r["kind"]=="ideal_reconstruction", records)==rule["reconstruction_count"] ||
        error("重构数量错误")
    mkpath(dest)
    for (name, data) in
        (("inputs.toml", Dict("records"=>records, "parents"=>parents)), ("rule.toml", rule))
        write(joinpath(dest, name), PaperRebuild.r7_text(data))
    end
    cp(@__FILE__, joinpath(dest, "study-source.jl"))
    cp(joinpath(@__DIR__, "r7_transport_study.jl"), joinpath(dest, "transport-study-source.jl"))
    for (p, f) in PaperRebuild.r7_transport_science_paths()
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>transport_manifest(dest),
                "science"=>PaperRebuild.r7_transport_science_hashes(),
                "parent_manifest_sha256"=>bytes2hex(
                    sha256(read(joinpath(parentdir, "files.toml"))),
                ),
            ),
        ),
    )
    println("34 optimization inputs and 3 original-value reconstructions frozen before running.")
end

function battery_inputs(dir; current = false)
    freeze=TOML.parsefile(joinpath(dir, "freeze.toml"))
    for (p, h) in freeze["files"]
        !isabspath(p)&&!occursin(':', p)&&all(x->!(x in ("", ".", "..")), split(p, '/')) ||
            error("冻结路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("电池冻结内容改变")
    end
    if current
        freeze["science"]==PaperRebuild.r7_transport_science_hashes() ||
            error("科学源码与预冻结不符")
        read(@__FILE__)==read(joinpath(dir, "study-source.jl")) || error("编排源码失步")
        read(joinpath(@__DIR__, "r7_transport_study.jl"))==read(
            joinpath(dir, "transport-study-source.jl"),
        ) || error("编排依赖失步")
    end
    TOML.parsefile(joinpath(dir, "inputs.toml")), TOML.parsefile(joinpath(dir, "rule.toml"))
end

function battery_run(dir, group)
    group in ("open", "gurobi") || error("运行组错误")
    input, rule=battery_inputs(dir; current = true)
    todo=filter(r->(r["solver"]=="Gurobi") == (group=="gurobi"), input["records"])
    any(ispath(joinpath(dir, "records", r["id"])) for r in todo)&&error("已有记录，不覆盖或重跑")
    stops=Dict{String,Float64}()
    for item in todo
        c=R7RecoveryCase(item["case"])
        s=item["spec"]
        if item["kind"]=="ideal_reconstruction"
            p=input["parents"][item["parent_record"]]
            out=r7_reconstruct_battery_cycles(R7RecoveryCase(p["case"]), p["spec"], p["result"])
            out.case.sha256==c.sha256 && out.spec==s || error("重构域不同于预冻结")
            result=out.result
        else
            fixed=item["kind"]=="mode_enumeration"
            budget=rule["budget_sec"]
            if fixed
                stop=get!(stops, item["parent_record"]) do
                    time()+budget
                end
                budget=max(0.0, stop-time())
            end
            modes=fixed ?
                  Dict(
                k=>PaperRebuild.r7_unpack(item["fixed_battery_modes"], k) for
                k in keys(item["fixed_battery_modes"])
            ) : nothing
            result=solve_r7_transport_recovery(
                c,
                item["fault"],
                s;
                optimizer = transport_optimizer(item["solver"]),
                fixed_z = fixed ? 1 .- item["fault"] : nothing,
                fixed_battery_modes = modes,
                budget_sec = budget,
            )
        end
        save_r7_transport_recovery(c, s, result, joinpath(dir, "records", item["id"]))
        println(item["id"], " ", result["status"], " model=", result["validation"]["model_pass"])
    end
end

function battery_tables(dir)
    input, rule=battery_inputs(dir)
    freeze=TOML.parsefile(joinpath(dir, "freeze.toml"))
    summary=IOBuffer()
    paired=IOBuffer()
    cycles=IOBuffer()
    println(
        summary,
        "record,group,flow,fault,kind,solver,run_id,status,model_pass,mutual_exclusivity_pass,loss_MWh,lower_bound_MWh,conditional_optimality,elapsed_sec",
    )
    println(
        paired,
        "record,parent_run_id,new_run_id,parent_model_pass,new_model_pass,parent_loss_MWh,new_loss_MWh,new_minus_parent_MWh,battery_rule_only_changed",
    )
    println(
        cycles,
        "record,parent_run_id,new_run_id,device,t,scenario,charge_before_MW,discharge_before_MW,cycle_removed_MW,energy_increment_MWh,other_values_preserved",
    )
    for item in input["records"]
        x=transport_read(joinpath(dir, "records", item["id"]))
        x.case.data==item["case"] && x.case.sha256==item["case_sha256"] && x.spec==item["spec"] ||
            error("输入与预冻结不同")
        r=x.result
        q=x.validation
        p=input["parents"][item["parent_record"]]
        r["source_hashes_at_solve"]==freeze["science"] && r["fault"]==item["fault"] ||
            error("求解源码或故障不符")
        before=deepcopy(p["case"])
        before["battery_rule"]=rule["battery_rule"]
        before==x.case.data || error("除电池域之外还有输入变更")
        oldspec=deepcopy(p["spec"])
        oldspec["case_sha256"]=x.case.sha256
        oldspec==x.spec || error("温度历史或流量改变")
        get(r, "fixed_battery_modes", nothing)==get(item, "fixed_battery_modes", nothing) ||
            error("固定模式记录不符")
        exclusive=get(get(q, "shared", Dict()), "mutual_exclusivity_pass", false)
        println(
            summary,
            join(
                [
                    item["id"],
                    item["group"],
                    item["flow_label"],
                    only(item["fault"]),
                    item["kind"],
                    item["solver"],
                    r["run_id"],
                    r["status"],
                    q["model_pass"],
                    exclusive,
                    get(q, "loss_MWh", ""),
                    get(r, "lower_bound_MWh", ""),
                    q["conditional_optimality_pass"],
                    r["elapsed_sec"],
                ],
                ',',
            ),
        )
        if item["kind"]=="main"
            oldq=p["result"]["validation"]
            both=q["model_pass"]&&oldq["model_pass"]
            println(
                paired,
                join(
                    [
                        item["id"],
                        p["result"]["run_id"],
                        r["run_id"],
                        oldq["model_pass"],
                        q["model_pass"],
                        get(oldq, "loss_MWh", ""),
                        get(q, "loss_MWh", ""),
                        both ? q["loss_MWh"]-oldq["loss_MWh"] : "",
                        true,
                    ],
                    ',',
                ),
            )
        elseif item["kind"]=="ideal_reconstruction"
            parent=p["result"]
            r["optimized_again"]===false &&
            r["parent_result_sha256"]==PaperRebuild.r7_digest(parent) &&
            !haskey(r, "lower_bound_MWh") || error("重构身份或求解范围错误")
            for key in keys(parent["values"])
                key in ("P_ch", "P_dis") && continue
                r["values"][key]==parent["values"][key] || error("重构修改了其他控制量或状态")
            end
            r["thermal_values"]==parent["thermal_values"] &&
            r["solver_objective_MWh"]==parent["solver_objective_MWh"] ||
                error("重构热状态或失供改变")
            ch, dis=(PaperRebuild.r7_unpack(parent["values"], k) for k in ("P_ch", "P_dis"))
            nch, ndis=(PaperRebuild.r7_unpack(r["values"], k) for k in ("P_ch", "P_dis"))
            for row in r["reconstruction_rows"]
                g=only(findall(z->z["id"]==row["device"], x.case.data["devices"]))
                t=row["t"]
                w=row["scenario"]
                dev=x.case.data["devices"][g]
                dev["eta_ch"]==dev["eta_dis"]==1 || error("原电池非理想，不能零能量变化重构")
                delta=min(ch[g, t, w], dis[g, t, w])
                row["removed_cycle_MW"]==delta &&
                row["energy_increment_MWh"]==0 &&
                nch[g, t, w]==ch[g, t, w]-delta &&
                ndis[g, t, w]==dis[g, t, w]-delta || error("重构恒等式不符")
                println(
                    cycles,
                    join(
                        [
                            item["id"],
                            parent["run_id"],
                            r["run_id"],
                            row["device"],
                            t,
                            w,
                            ch[g, t, w],
                            dis[g, t, w],
                            delta,
                            0.0,
                            true,
                        ],
                        ',',
                    ),
                )
            end
        end
    end
    Dict(
        "summary.csv"=>String(take!(summary)),
        "domain-pairs.csv"=>String(take!(paired)),
        "ideal-cycles.csv"=>String(take!(cycles)),
    )
end

function battery_report(source, dest)
    ispath(dest)&&error("不覆盖电池报告")
    tables=battery_tables(source)
    cp(source, dest)
    for (name, value) in tables
        write(joinpath(dest, name), value)
    end
    write(
        joinpath(dest, "files.toml"),
        PaperRebuild.r7_text(Dict("files"=>transport_manifest(dest))),
    )
    println("34 optimization runs and 3 separate original-value reconstructions archived.")
end

function battery_check(dir)
    transport_manifest(dir)==TOML.parsefile(joinpath(dir, "files.toml"))["files"] ||
        error("电池报告改变")
    for (name, value) in battery_tables(dir)
        read(joinpath(dir, name), String)==value || error("原值与电池摘要不同")
    end
    println("Battery evidence rechecked from saved values and frozen source; no optimization.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 && ARGS[1]=="freeze" ? battery_freeze(abspath(ARGS[2])) :
    length(ARGS)==3 && ARGS[1]=="run" ? battery_run(abspath(ARGS[2]), ARGS[3]) :
    length(ARGS)==3 && ARGS[1]=="report" ? battery_report(abspath(ARGS[2]), abspath(ARGS[3])) :
    length(ARGS)==2 && ARGS[1]=="check" ? battery_check(abspath(ARGS[2])) :
    error(
        "usage: r7_battery_study.jl freeze NEW | run FROZEN open|gurobi | report RAW NEW | check REPORT",
    )
end
