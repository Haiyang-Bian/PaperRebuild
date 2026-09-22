include("r8_energy_study.jl")

function r8e_residuals(x)
    rows=NamedTuple[]
    for item in x.items
        r=x.records[item["id"]].result
        function visit(v, path)
            if v isa AbstractDict
                if all(haskey(v, k) for k in ("residual", "tolerance", "pass"))
                    push!(
                        rows,
                        (
                            id = item["id"],
                            run_id = r["run_id"],
                            path,
                            equation = string(get(v, "id", "unlabelled")),
                            residual = Float64(v["residual"]),
                            tolerance = Float64(v["tolerance"]),
                            pass = Bool(v["pass"]),
                        ),
                    )
                end
                for k in sort!(collect(keys(v)))
                    visit(v[k], path*"/"*k)
                end
            elseif v isa AbstractVector
                for (i, z) in enumerate(v)
                    visit(z, path*"/"*string(i))
                end
            end
        end
        visit(r["validation"], "validation")
    end
    rows
end

function r8e_pairs(x)
    rows=NamedTuple[]
    for a in x.items
        a["solver"]=="HiGHS" || continue
        b=only(
            filter(
                y->y["solver"]=="Gurobi"&&y["case_sha256"]==a["case_sha256"] &&
                   y["spec_sha256"]==a["spec_sha256"]&&y["model"]==a["model"],
                x.items,
            ),
        )
        ra, rb=x.records[a["id"]].result, x.records[b["id"]].result
        pa, pb=ra["validation"]["primary"], rb["validation"]["primary"]
        delta=missing
        judgement="unresolved"
        if pa["objective_complete"]&&pb["objective_complete"]
            av, bv=pa["objective_value"], pb["objective_value"]
            delta=(av-bv)/max(1, abs(av), abs(bv))
            judgement=abs(delta)<=1e-4 ? "same_model_A2_pass" : "contradiction"
        elseif ra["primary"]["status"]==rb["primary"]["status"]=="infeasible_certified"
            judgement="both_infeasible"
        end
        ea, eb=get(ra["validation"], "evaluation", Dict()),
        get(rb["validation"], "evaluation", Dict())
        risk_delta=haskey(ea, "event_upper_MWh")&&haskey(eb, "event_upper_MWh") ?
                   maximum(abs.(ea["event_upper_MWh"]-eb["event_upper_MWh"])) : missing
        # 最优正常计划可能不唯一；原正常控制不同时，不把风险不同误判为同一恢复模型矛盾。
        push!(
            rows,
            (
                left = a["id"],
                right = b["id"],
                judgement,
                relative_objective_difference = delta,
                risk_difference_MWh = risk_delta,
                risk_scope = "each_own_frozen_normal_plan",
            ),
        )
    end
    rows
end

function r8e_model_comparisons(x, parent)
    rows=NamedTuple[]
    for a in x.items
        a["model"]=="energy" || continue
        bs=if a["family"]=="shift_four"
            filter(
                y->y["model"]=="detailed"&&y["case_sha256"]==a["case_sha256"] &&
                   y["solver"]==a["solver"]&&y["mode"]==a["mode"],
                x.items,
            )
        else
            filter(
                y->y["control"]=="fixed"&&y["resource"]=="all" &&
                   y["case_sha256"]==a["case_sha256"]&&y["solver"]==a["solver"] &&
                   y["mode"]==a["mode"]&&(
                       a["mode"]!="threshold"||y["limit_MWh"]==only(
                           a["spec"]["limits_MWh"] |> unique,
                       )
                   ),
                parent.items,
            )
        end
        if isempty(bs)
            # 父批次三节点固定组只运行Gurobi；不悄悄引入第二个变化因素或补跑历史结果。
            push!(
                rows,
                (
                    family = a["family"],
                    UA_W_K = a["UA_W_K"],
                    mode = a["mode"],
                    solver = a["solver"],
                    energy_id = a["id"],
                    detailed_id = "not_available",
                    energy_status = x.records[a["id"]].result["primary"]["status"],
                    detailed_status = "not_run_same_solver",
                    cost_energy_minus_detailed_USD = missing,
                    risk_energy_minus_detailed_MWh = missing,
                    scope = "no_same_solver_parent",
                    is_optimality_gap = false,
                ),
            )
            continue
        end
        b=only(bs)
        a["normal"]==b["normal"]&&a["planning"]==b["planning"] || error("模型对照输入不一致")
        a["spec"]["penalty_USD_MWh"]==b["spec"]["penalty_USD_MWh"] || error("模型对照罚项不同")
        left=x.records[a["id"]].result
        right=(a["family"]=="shift_four" ? x : parent).records[b["id"]].result
        p, q=left["validation"]["primary"], right["validation"]["primary"]
        lp, rp=p["model_pass"], q["model_pass"]
        ev1, ev2=get(left["validation"], "evaluation", Dict()),
        get(right["validation"], "evaluation", Dict())
        cost_delta=lp&&rp ? p["normal_cost_USD"]-q["normal_cost_USD"] : missing
        risk_delta=get(ev1, "model_pass", false)&&get(ev2, "model_pass", false) ?
                   maximum(ev1["event_upper_MWh"])-maximum(ev2["event_upper_MWh"]) : missing
        push!(
            rows,
            (
                family = a["family"],
                UA_W_K = a["UA_W_K"],
                mode = a["mode"],
                solver = a["solver"],
                energy_id = a["id"],
                detailed_id = b["id"],
                energy_status = left["primary"]["status"],
                detailed_status = right["primary"]["status"],
                cost_energy_minus_detailed_USD = cost_delta,
                risk_energy_minus_detailed_MWh = risk_delta,
                scope = a["UA_W_K"]==0 ? "temporal_state_and_temperature_domain" :
                        "temporal_state_temperature_and_loss_representation",
                is_optimality_gap = false,
            ),
        )
    end
    rows
end

function r8e_trajectories(x)
    rows=NamedTuple[]
    for item in x.items
        item["family"]=="shift_four" || continue
        r=x.records[item["id"]].result
        get(get(r["validation"], "evaluation", Dict()), "model_pass", false) || continue
        d=item["normal"]
        h=d["heat"]
        for witness in r["evaluation"]["witnesses"]
            event=item["planning"]["events"][witness["event"]]
            event["event_start"]==1 && item["flow"]["substeps"]==1 ||
                error("本轨迹导出限本批事件1/整时步")
            v=Dict(k=>PaperRebuild.r7_unpack(witness["values"], k) for k in keys(witness["values"]))
            detailed=item["model"]=="detailed"
            th=detailed ?
               Dict(
                k=>PaperRebuild.r7_unpack(witness["thermal_values"], k) for
                k in keys(witness["thermal_values"])
            ) : Dict()
            for w in eachindex(d["probabilities"])
                # 逐水团重放保存的入口温度/流量，不读取优化输运权重。
                states=Dict(
                    (a, side)=>PaperRebuild.r7_normal_initial(d, p, side, w) for
                    (a, p) in enumerate(h["pipes"]) for side in ("S", "R")
                )
                inventories() = sum(
                    PaperRebuild.r7_pipe_inventory(
                        state;
                        cp_J_kgK = h["c_J_kgK"],
                        reference_K = h["$(side)_min_K"],
                    ).relative_heat_MWh for ((_, side), state) in states
                )
                initial=inventories()
                cumulative=0.0
                for t in 1:event["periods"]
                    Hgen=sum(v["H"][:, t, w])
                    Pdraw=sum(
                        v["P"][g, t, w] for (g, z) in enumerate(d["devices"]) if z["kind"]=="EB";
                        init = 0.0,
                    )
                    Hload=sum(z[t] for z in h["load_MW"])
                    Hshed=sum(v["H_shed"][:, t, w])
                    Pshed=sum(v["P_shed"][:, t, w])
                    loss=0.0
                    replay_error=missing
                    delta=missing
                    energy_residual=missing
                    if detailed
                        out_error=0.0
                        for (a, p) in enumerate(h["pipes"]), side in ("S", "R")
                            node=p[side=="S" ? "from" : "to"]
                            step=PaperRebuild.r7_pipe_step(
                                states[(a, side)];
                                mass_flow_kg_s = v["m_pipe"][a, t],
                                inlet_K = th[side][node, t, w],
                                ambient_K = h["ambient_K"][t],
                                dt_h = d["dt_h"],
                                cp_J_kgK = h["c_J_kgK"],
                                UA_W_K = p["UA_$(side)_W_K"],
                                reference_K = h["$(side)_min_K"],
                            )
                            states[(a, side)]=step.state
                            loss+=step.loss_MWh
                            out_error=max(
                                out_error,
                                abs(step.outlet_mean_K-th["out_$side"][a, t, w]),
                            )
                        end
                        cumulative+=d["dt_h"]*(Hgen-Hload+Hshed)-loss
                        delta=inventories()-initial
                        energy_residual=delta-cumulative
                        replay_error=out_error
                    else
                        loss=d["dt_h"]*sum(
                            p["UA_$(side)_W_K"]*(h["$(side)_reference_K"]-h["ambient_K"][t]) for
                            p in h["pipes"] for side in ("S", "R")
                        )/1e6
                    end
                    push!(
                        rows,
                        (
                            id = item["id"],
                            run_id = r["run_id"],
                            model = item["model"],
                            UA_W_K = item["UA_W_K"],
                            mode = item["mode"],
                            solver = item["solver"],
                            event = witness["event"],
                            fault = join(witness["fault"], ""),
                            scenario = w,
                            probability = d["probabilities"][w],
                            t,
                            dt_h = d["dt_h"],
                            source_MW = Hgen,
                            load_MW = Hload,
                            heat_shed_MW = Hshed,
                            electric_shed_MW = Pshed,
                            EB_MW = Pdraw,
                            loss_MWh = loss,
                            stored_above_initial_MWh = delta,
                            replay_temperature_error_K = replay_error,
                            cumulative_energy_residual_MWh = energy_residual,
                            terminal_rule = "recovery_free_thermal_end",
                        ),
                    )
                end
            end
        end
    end
    rows
end

function r8e_boundaries(x)
    rows=NamedTuple[]
    for item in x.items
        item["model"]=="energy" || continue
        d=item["normal"]
        h=d["heat"]
        losses=[
            sum(
                p["UA_$(side)_W_K"]*(h["$(side)_reference_K"]-h["ambient_K"][t]) for p in
                                                                                     h["pipes"] for
                side in ("S", "R")
            )/1e6 for t in 1:d["periods"]
        ]
        if item["family"]=="legacy"
            # 唯一内部电线断开，CHP所在节点无电负荷、储电/电锅炉或其他消纳出口。
            length(d["electric"]["lines"])==1 || error("孤岛证书范围改变")
            d["electric"]["load_MW"][1]==zeros(d["periods"]) || error("孤岛出现电负荷")
            only(filter(g->g["electric_node"]==1, d["devices"]))["kind"]=="CHP" ||
                error("孤岛设备改变")
            minimum(losses)>0 || error("无正散热冲突")
            push!(
                rows,
                (
                    id = item["id"],
                    certificate = "isolated_CHP_no_electric_sink",
                    value = minimum(losses),
                    unit = "MW",
                    meaning = "strictly_positive_required_heat_vs_zero_possible_heat",
                ),
            )
        elseif item["family"]=="shift_four"
            chp=only(filter(g->g["kind"]=="CHP", d["devices"]))
            gt=only(filter(g->g["kind"]=="GT", d["devices"]))
            eb=only(filter(g->g["kind"]=="EB", d["devices"]))
            all(g["kind"] in ("CHP", "GT", "EB") for g in d["devices"]) ||
                error("晚段证书出现其他资源")
            eb["heat_ratio"]<=1 || error("电热替代证书效率条件不满足")
            e=sum(d["electric"]["load_MW"])
            all(isapprox(e[t], chp["P_max_MW"]+gt["P_max_MW"]; atol = 1e-12) for t in 3:4) ||
                error("晚段容量条件改变")
            H=sum(h["load_MW"])
            lower=d["dt_h"]*sum(H[t]+losses[t]-chp["heat_ratio"]*chp["P_max_MW"] for t in 3:4)
            push!(
                rows,
                (
                    id = item["id"],
                    certificate = "late_period_heat_electric_capacity",
                    value = lower,
                    unit = "MWh",
                    meaning = "lower_bound_on_total_recovery_unserved",
                ),
            )
        end
    end
    rows
end

function r8e_create_audit(report, parentdir, out)
    ispath(out)&&error("不覆盖能流审计")
    x=r8_energy_archive(report)
    parent=r8_archive_check(parentdir)
    TOML.parsefile(joinpath(report, "environment.toml"))["parent_manifest_sha256"]==r8_file_hash(
        joinpath(parentdir, "report-hashes.toml"),
    ) || error("父运行变更")
    mkpath(out)
    rows=r8e_residuals(x)
    parts=String[]
    for (i, k) in enumerate(1:5000:length(rows))
        name="residuals-"*lpad(string(i), 3, '0')*".csv"
        CSV.write(joinpath(out, name), rows[k:min(k+4999, length(rows))])
        push!(parts, name)
    end
    for (p, z) in (
        ("solver-pairs.csv", r8e_pairs(x)),
        ("model-comparisons.csv", r8e_model_comparisons(x, parent)),
        ("trajectories.csv", r8e_trajectories(x)),
        ("boundary-certificates.csv", r8e_boundaries(x)),
    )
        CSV.write(joinpath(out, p), z)
    end
    cp(@__FILE__, joinpath(out, "audit-source.jl"))
    write(
        joinpath(out, "audit.toml"),
        PaperRebuild.r7_text(
            Dict(
                "schema"=>"r8-energy-audit-v1",
                "origin"=>"synthetic",
                "report_manifest_sha256"=>r8_file_hash(joinpath(report, "report-hashes.toml")),
                "parent_manifest_sha256"=>r8_file_hash(joinpath(parentdir, "report-hashes.toml")),
                "residual_parts"=>parts,
                "residual_count"=>length(rows),
                "files"=>r8_archive_files(out),
            ),
        ),
    )
    println("Frozen energy comparisons and independent parcel trajectories audited.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3 || error("usage: audit_r8_energy.jl REPORT PARENT NEW_AUDIT")
    r8e_create_audit(abspath.(ARGS)...)
end
