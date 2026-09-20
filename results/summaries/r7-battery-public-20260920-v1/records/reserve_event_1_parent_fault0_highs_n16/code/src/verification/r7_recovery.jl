const R7_RECOVERY_VERIFY_FILE = @__FILE__

# 独立从原值核查模式、互斥和固定模式身份，不读取JuMP表达式或只看二元标志。
function r7_verify_battery_domain!(rec, d, r, v, power_tolerance)
    if !r7_exclusive_battery(d)
        haskey(r, "fixed_battery_modes") && error("和式域记录混入互斥模式")
        return
    end
    fixed=haskey(r, "fixed_battery_modes") ?
          r7_fixed_battery_modes(
        d,
        Dict(k=>r7_unpack(r["fixed_battery_modes"], k) for k in keys(r["fixed_battery_modes"])),
    ) : nothing
    for (g, dev) in enumerate(d["devices"]), t in 1:d["periods"], w in eachindex(d["probabilities"])
        b=v["b_BES"][g, t, w]
        rec("R7-B1-bounds", dev["id"], t, w, max(0.0, -b, b-1), "1", 1e-6)
        rec("R7-B1-integer", dev["id"], t, w, b-round(b), "1", 1e-6)
        if dev["kind"]=="BES"
            ch, dis=v["P_ch"][g, t, w], v["P_dis"][g, t, w]
            rec(
                "R7-B1-charge",
                dev["id"],
                t,
                w,
                max(0.0, ch-dev["P_max_MW"]*b),
                "MW",
                power_tolerance,
            )
            rec(
                "R7-B1-discharge",
                dev["id"],
                t,
                w,
                max(0.0, dis-dev["P_max_MW"]*(1-b)),
                "MW",
                power_tolerance,
            )
            rec("R7-B1-nonsimultaneous", dev["id"], t, w, min(ch, dis), "MW", power_tolerance)
            fixed===nothing ||
                rec("R7-B1-fixed", dev["id"], t, w, b-fixed[dev["id"]][t, w], "1", 1e-6)
        else
            rec("R7-B1-inactive", dev["id"], t, w, b, "1", 1e-6)
        end
    end
end

"""
    validate_r7_recovery(case, result; aggregate_heat=true)

从保存值独立重算设备、失供积分、线性电网、森林及双水箱约束，沿用A1。
不复用JuMP约束表达式；一阶循环交换的真实乘积误差、电池同时充放单列，
不将代理模型通过升级为详细热网、交流潮流或全故障安全认证。
aggregate_heat=false仅供逐管调度验证共用设备/电网/流量块；此时model_pass始终false，
共用块检查另记shared_block_pass，不能将缺失热模型的检查当作完整恢复通过。
"""
function validate_r7_recovery(c::R7RecoveryCase, r; aggregate_heat = true)
    r7_recovery_assert(c)
    r["schema"] == "r7-recovery-result-v1" && r["version"] == r7_recovery_version(c) ||
        error("恢复结果版本错误")
    r["objective_kind"] == "expected_unserved_energy_MWh" &&
    r["preplan_id"] == c.data["preplan_id"] &&
    r["preplan_optimality_verified"] === false || error("恢复目标或灾前证据范围错误")
    r["case_sha256"]==c.sha256 || error("恢复结果输入身份错误")
    d=c.data
    e, h=d["electric"], d["heat"]
    ds, ls, ps=d["devices"], e["lines"], h["pipes"]
    N, J, T, W, G, L, A=e["nodes"],
    h["nodes"],
    d["periods"],
    length(d["probabilities"]),
    length(ds),
    length(ls),
    length(ps)
    gamma=Int.(r["fault"])
    r7_check_fault(c, gamma)
    rows=Dict{String,Any}[]
    out=Dict{String,Any}(
        "model_pass"=>false,
        "loss_pass"=>false,
        "optimality_pass"=>false,
        "detailed_heat_validated"=>false,
        "ac_grid_validated"=>false,
        "rows"=>rows,
    )
    aggregate_heat || (out["shared_block_pass"]=false)
    haskey(r, "values") || return out
    r["status"] in
    ("infeasible_certified", "budget_exhausted", "time_limit_no_solution", "license_unavailable") &&
        error("恢复状态与候选值矛盾")
    isfinite(r["solver_objective_MWh"]) || error("恢复目标不是有限值")
    shape=Dict(
        "z"=>(L,),
        "beta"=>(N,),
        "a_on"=>(L,),
        "a_off"=>(L,),
        "virtual"=>(L,),
        "root_supply"=>(N,),
        "P_line"=>(L, T, W),
        "Q_line"=>(L, T, W),
        "v"=>(N, T, W),
        "P_PCC"=>(T, W),
        "Q_PCC"=>(T, W),
        "P"=>(G, T, W),
        "Q"=>(G, T, W),
        "H"=>(G, T, W),
        "P_ch"=>(G, T, W),
        "P_dis"=>(G, T, W),
        "E_BES"=>(G, T+1, W),
        "P_shed"=>(N, T, W),
        "H_shed"=>(J, T, W),
        "m_pipe"=>(A, T),
        "m_source"=>(J, T),
        "m_load"=>(J, T),
        "E_S"=>(T+1, W),
        "E_R"=>(T+1, W),
        "H_CF"=>(T, W),
        "H_loss_S"=>(T, W),
        "H_loss_R"=>(T, W),
    )
    r7_exclusive_battery(d) && (shape["b_BES"]=(G, T, W))
    if !aggregate_heat
        foreach(k->delete!(shape, k), ("E_S", "E_R", "H_CF", "H_loss_S", "H_loss_R"))
    end
    Set(keys(r["values"]))==Set(keys(shape)) || error("恢复数值字段不完整")
    v=Dict(k=>r7_unpack(r["values"], k) for k in keys(shape))
    all(size(v[k])==s && all(isfinite, v[k]) for (k, s) in shape) || error("恢复值形状或有限性错误")
    power_scale=max(
        1.0,
        maximum(reduce(vcat, e["load_MW"])),
        sum(g["P_max_MW"] for g in ds; init = 0.0),
        maximum(reduce(vcat, h["load_MW"])),
    )
    flow_scale=max(
        1.0,
        maximum(p["flow_max_kg_s"] for p in ps),
        maximum(h["source_flow_max"]),
        maximum(h["load_flow_max"]),
    )
    # 独立按SI体积/比热计算容量，不能直接读取建模侧派生常量。
    cap=Dict(
        side=>h["c_J_kgK"]*h["rho_kg_m3"]*sum(p["volume_$(side)_m3"] for p in ps)/3.6e9 for
        side in ("S", "R")
    )
    energy_scale=max(
        1.0,
        cap["S"]*(h["S_max_K"]-h["S_min_K"]),
        cap["R"]*(h["R_max_K"]-h["R_min_K"]),
        maximum((g["E_max_MWh"] for g in ds if g["kind"]=="BES"); init = 0.0),
    )
    pt, ft, et=1e-6*(1+power_scale), 1e-6*(1+flow_scale), 1e-6*(1+energy_scale)
    function rec(id, entity, t, w, x, unit, tol; scope = "adopted")
        push!(
            rows,
            Dict(
                "id"=>id,
                "entity"=>string(entity),
                "t"=>t,
                "scenario"=>w,
                "scope"=>scope,
                "unit"=>unit,
                "residual"=>abs(Float64(x)),
                "tolerance"=>tol,
                "normalized"=>abs(Float64(x))/tol,
                "pass"=>isfinite(x)&&abs(x)<=tol,
            ),
        )
    end
    bound(id, entity, t, w, x, lo, hi, unit, tol) =
        rec(id, entity, t, w, max(0.0, lo-x, x-hi), unit, tol)
    r7_verify_battery_domain!(rec, d, r, v, pt)
    z, beta=v["z"], v["beta"]
    if haskey(r, "fixed_z")
        length(r["fixed_z"]) == L && all(x -> x in (0, 1), r["fixed_z"]) ||
            error("固定拓扑记录错误")
        for l in 1:L
            rec("fixed-topology", l, 0, 0, z[l]-r["fixed_z"][l], "1", 1e-6)
        end
    end
    for (key, vec) in (("z", z), ("beta", beta), ("a_on", v["a_on"]), ("a_off", v["a_off"]))
        for (i, x) in enumerate(vec)
            bound("binary-$key", i, 0, 0, x, 0, 1, "1", 1e-6)
            rec("integer-$key", i, 0, 0, x-round(x), "1", 1e-6)
        end
    end
    for l in 1:L
        base=ls[l]["base_closed"]
        rec("R7-R1", l, 0, 0, z[l]-base*(1-gamma[l])-v["a_on"][l]+v["a_off"][l], "1", 1e-6)
        bound("on-action", l, 0, 0, v["a_on"][l], 0, (1-base)*(1-gamma[l]), "1", 1e-6)
        bound("off-action", l, 0, 0, v["a_off"][l], 0, base*(1-gamma[l]), "1", 1e-6)
        bound("virtual-arc", l, 0, 0, v["virtual"][l], -(N-1)*z[l], (N-1)*z[l], "1", 1e-6)
    end
    bound("6-63", "network", 0, 0, sum(v["a_on"])+sum(v["a_off"]), 0, e["switch_budget"], "1", 1e-6)
    rec("forest-edges", "network", 0, 0, sum(z)-N+sum(beta), "1", 1e-6)
    # 独立图遍历只在原整数残差检查之后解释邻接结构；不以四舍五入掩盖非整数候选。
    groups=r7_connected_components(N, [(l["from"], l["to"]) for l in ls], Int.(round.(z)))
    rec("forest-independent", "network", 0, 0, sum(round.(z))-N+length(groups), "1", 1e-6)
    for (i, group) in enumerate(groups)
        rec("one-root-per-component", i, 0, 0, sum(beta[group])-1, "1", 1e-6)
    end
    for n in 1:N
        bound("root-eligible", n, 0, 0, beta[n], 0, e["root_eligible"][n], "1", 1e-6)
        bound("root-supply", n, 0, 0, v["root_supply"][n], 0, N*beta[n], "1", 1e-6)
        outgoing=sum(v["virtual"][l] for l in 1:L if ls[l]["from"]==n; init = 0.0)
        incoming=sum(v["virtual"][l] for l in 1:L if ls[l]["to"]==n; init = 0.0)
        rec("virtual-node", n, 0, 0, outgoing-incoming-v["root_supply"][n]+1, "1", 1e-6)
    end
    dt=d["dt_h"]
    simultaneous=0.0
    for g in 1:G, t in 1:T, w in 1:W
        dev=ds[g]
        kind=dev["kind"]
        P, Q, H, ch, dis=(v[key][g, t, w] for key in ("P", "Q", "H", "P_ch", "P_dis"))
        u=kind=="CHP" ? dev["commitment"][t] : 1
        upper=kind=="PV" ? d["renewable_factor"]*dev["available_MW"][t][w] :
              kind=="BES" ? 0.0 : dev["P_max_MW"]*u
        lower=kind=="CHP" ? dev["P_min_MW"]*u : 0.0
        bound("6-8/56/60", g, t, w, P, lower, upper, "MW", pt)
        qlo=kind=="CHP" ? dev["Q_min_Mvar"]*u : 0.0
        qhi=kind in ("CHP", "GT") ? dev["Q_max_Mvar"]*u : 0.0
        bound("6-3/9", g, t, w, Q, qlo, qhi, "Mvar", pt)
        rec("6-11", g, t, w, H-(kind in ("CHP", "EB") ? dev["heat_ratio"]*P : 0.0), "MW", pt)
        if kind=="CHP"
            previous=t==1 ? dev["previous_P_MW"][w] : v["P"][g, t-1, w]
            previous_u=t==1 ? dev["previous_commitment"] : dev["commitment"][t-1]
            bound(
                "6-4/57",
                g,
                t,
                w,
                P-previous,
                -Inf,
                previous_u*dev["ramp_MW_h"]*dt+(1-previous_u)*dev["startup_MW"],
                "MW",
                pt,
            )
            bound(
                "6-5/58",
                g,
                t,
                w,
                previous-P,
                -Inf,
                u*dev["ramp_MW_h"]*dt+(1-u)*dev["shutdown_MW"],
                "MW",
                pt,
            )
        end
        if kind=="BES"
            bound("battery-charge", g, t, w, ch, 0, dev["P_max_MW"], "MW", pt)
            bound("battery-discharge", g, t, w, dis, 0, dev["P_max_MW"], "MW", pt)
            bound("6-12", g, t, w, ch+dis, 0, dev["P_max_MW"], "MW", pt)
            rec(
                "6-14",
                g,
                t,
                w,
                v["E_BES"][g, t+1, w]-v["E_BES"][g, t, w]-dt*(dev["eta_ch"]*ch-dis/dev["eta_dis"]),
                "MWh",
                et,
            )
            simultaneous=max(simultaneous, min(ch, dis))
        else
            rec("inactive-charge", g, t, w, ch, "MW", pt)
            rec("inactive-discharge", g, t, w, dis, "MW", pt)
        end
    end
    for g in 1:G, k in 1:(T+1), w in 1:W
        dev=ds[g]
        if dev["kind"]=="BES"
            bound(
                "6-13",
                g,
                k,
                w,
                v["E_BES"][g, k, w],
                dev["E_min_MWh"],
                dev["E_max_MWh"],
                "MWh",
                et,
            )
            k==1 && rec("6-61", g, k, w, v["E_BES"][g, k, w]-dev["initial_MWh"][w], "MWh", et)
        else
            rec("inactive-energy", g, k, w, v["E_BES"][g, k, w], "MWh", et)
        end
    end
    for t in 1:T, w in 1:W
        rec("6-51-P", "PCC", t, w, v["P_PCC"][t, w], "MW", pt)
        rec("6-51-Q", "PCC", t, w, v["Q_PCC"][t, w], "Mvar", pt)
        for l in 1:L
            line=ls[l]
            sign=e["flow_domain"]=="signed" ? -1.0 : 0.0
            for (key, maxkey) in (("P_line", "P_max_MW"), ("Q_line", "Q_max_Mvar"))
                bound(
                    "6-24:25-$key",
                    l,
                    t,
                    w,
                    v[key][l, t, w],
                    sign*line[maxkey]*z[l],
                    line[maxkey]*z[l],
                    key=="P_line" ? "MW" : "Mvar",
                    pt,
                )
            end
            voltage=v["v"][line["from"], t, w]-v["v"][line["to"], t, w]-(
                line["r_pu"]*v["P_line"][l, t, w]+line["x_pu"]*v["Q_line"][l, t, w]
            )/(e["S_base_MVA"]*e["v_ref_pu"])
            bound(
                "R7-R3",
                l,
                t,
                w,
                voltage,
                -(e["v_max_pu"]-e["v_min_pu"])*(1-z[l]),
                (e["v_max_pu"]-e["v_min_pu"])*(1-z[l]),
                "pu",
                1e-6,
            )
        end
        for n in 1:N
            bound("6-22", n, t, w, v["v"][n, t, w], e["v_min_pu"], e["v_max_pu"], "pu", 1e-6)
            shed=v["P_shed"][n, t, w]
            bound("6-54", n, t, w, shed, 0, e["load_MW"][n][t]*e["shed_fraction_max"][n], "MW", pt)
            demand=e["load_MW"][n][t]-shed
            p, q=-demand, -e["tan_phi"][n]*demand
            for g in 1:G
                ds[g]["electric_node"]==n || continue
                p+=(ds[g]["kind"]=="EB" ? -1 : 1)*v["P"][g, t, w]+v["P_dis"][g, t, w]-v["P_ch"][
                    g,
                    t,
                    w,
                ]
                q+=v["Q"][g, t, w]
            end
            n==e["pcc_node"] && (p+=v["P_PCC"][t, w]; q+=v["Q_PCC"][t, w])
            for l in 1:L
                s=(ls[l]["to"]==n ? 1 : 0)-(ls[l]["from"]==n ? 1 : 0)
                p+=s*v["P_line"][l, t, w]
                q+=s*v["Q_line"][l, t, w]
            end
            rec("6-19", n, t, w, p, "MW", pt)
            rec("6-20", n, t, w, q, "Mvar", pt)
        end
    end
    for t in 1:T
        for a in 1:A
            p=ps[a]
            flow=v["m_pipe"][a, t]
            bound("6-74", a, t, 0, flow, -p["flow_max_kg_s"], p["flow_max_kg_s"], "kg/s", ft)
            bound(
                "6-72",
                a,
                t,
                0,
                flow-p["normal_flow_kg_s"][t],
                -p["flow_change_max_kg_s"],
                p["flow_change_max_kg_s"],
                "kg/s",
                ft,
            )
        end
        for j in 1:J
            source, load=v["m_source"][j, t], v["m_load"][j, t]
            bound("source-port", j, t, 0, source, 0, h["source_flow_max"][j], "kg/s", ft)
            bound("load-port", j, t, 0, load, 0, h["load_flow_max"][j], "kg/s", ft)
            mass=source-load
            for a in 1:A
                mass+=((ps[a]["to"]==j ? 1 : 0)-(ps[a]["from"]==j ? 1 : 0))*v["m_pipe"][a, t]
            end
            rec("R7-R4", j, t, 0, mass, "kg/s", ft)
            for w in 1:W
                shed=v["H_shed"][j, t, w]
                bound(
                    "6-55",
                    j,
                    t,
                    w,
                    shed,
                    0,
                    h["load_MW"][j][t]*h["shed_fraction_max"][j],
                    "MW",
                    pt,
                )
                delivered=h["load_MW"][j][t]-shed
                generated=sum(
                    v["H"][g, t, w] for
                    g in 1:G if ds[g]["kind"] in ("CHP", "EB") && ds[g]["heat_node"]==j;
                    init = 0.0,
                )
                cw=h["c_J_kgK"]/1e6
                bound(
                    "6-83",
                    j,
                    t,
                    w,
                    generated,
                    cw*source*h["source_delta_min"][j],
                    cw*source*h["source_delta_max"][j],
                    "MW",
                    pt,
                )
                bound(
                    "6-84",
                    j,
                    t,
                    w,
                    delivered,
                    cw*load*h["load_delta_min"][j],
                    cw*load*h["load_delta_max"][j],
                    "MW",
                    pt,
                )
                if r7_recovery_version(c)=="r7_recovery_port_checked_v1"
                    # 直接从原输入温区重算，不读取建模约束或其辅助系数。
                    bound(
                        "R7-C1-source",
                        j,
                        t,
                        w,
                        generated,
                        cw*source*(h["S_min_K"]-h["R_max_K"]),
                        cw*source*(h["S_max_K"]-h["R_min_K"]),
                        "MW",
                        pt,
                    )
                    bound(
                        "R7-C1-load",
                        j,
                        t,
                        w,
                        delivered,
                        cw*load*(h["S_min_K"]-h["R_max_K"]),
                        cw*load*(h["S_max_K"]-h["R_min_K"]),
                        "MW",
                        pt,
                    )
                end
            end
        end
    end
    if aggregate_heat
        for side in ("S", "R"), k in 1:(T+1), w in 1:W
            energy=v["E_$side"][k, w]
            bound(
                "6-81:82-temperature",
                side,
                k,
                w,
                h["$(side)_min_K"]+energy/cap[side],
                h["$(side)_min_K"],
                h["$(side)_max_K"],
                "K",
                1e-4,
            )
            bound(
                "6-80:82",
                side,
                k,
                w,
                energy,
                0,
                cap[side]*(h["$(side)_max_K"]-h["$(side)_min_K"]),
                "MWh",
                et,
            )
            if k==1
                initial=h["c_J_kgK"]*h["rho_kg_m3"]/3.6e9*sum(
                    p["volume_$(side)_m3"]*(p["initial_$(side)_K"][w]-h["$(side)_min_K"]) for
                    p in ps
                )
                rec("R7-A3/90", side, k, w, energy-initial, "MWh", et)
            end
        end
        for t in 1:T, w in 1:W
            Ts=h["S_min_K"]+v["E_S"][t, w]/cap["S"]
            Tr=h["R_min_K"]+v["E_R"][t, w]/cap["R"]
            mf=sum(v["m_source"][:, t])
            ref=h["S_reference_K"]-h["R_reference_K"]
            exact=h["c_J_kgK"]/1e6*mf*(Ts-Tr)
            linear=h["c_J_kgK"]/1e6*(mf*ref+h["reference_flow_kg_s"][t]*(Ts-Tr-ref))
            rec("6-89", "circulation", t, w, v["H_CF"][t, w]-linear, "MW", pt)
            rec(
                "6-88",
                "circulation",
                t,
                w,
                v["H_CF"][t, w]-exact,
                "MW",
                pt;
                scope = "exact_exchange",
            )
            for (side, temp) in (("S", Ts), ("R", Tr))
                loss=sum(p["UA_$(side)_W_K"] for p in ps)/1e6*(temp-h["ambient_K"][t])
                rec("6-85:86", side, t, w, v["H_loss_$side"][t, w]-loss, "MW", pt)
            end
            source=sum(v["H"][:, t, w])
            delivered=sum(h["load_MW"][j][t]-v["H_shed"][j, t, w] for j in 1:J)
            rec(
                "R7-A4-S",
                "tank",
                t,
                w,
                v["E_S"][t+1, w]-v["E_S"][t, w]-dt*(source-v["H_loss_S"][t, w]-v["H_CF"][t, w]),
                "MWh",
                et,
            )
            rec(
                "R7-A4-R",
                "tank",
                t,
                w,
                v["E_R"][t+1, w]-v["E_R"][t, w]-dt*(-delivered-v["H_loss_R"][t, w]+v["H_CF"][t, w]),
                "MWh",
                et,
            )
        end
    end
    lossP=dt*sum(d["probabilities"][w]*sum(v["P_shed"][:, :, w]) for w in 1:W)
    lossH=dt*sum(d["probabilities"][w]*sum(v["H_shed"][:, :, w]) for w in 1:W)
    rec(
        "6-53",
        "objective",
        0,
        0,
        r["solver_objective_MWh"]-lossP-lossH,
        "MWh",
        1e-6*max(1, abs(lossP+lossH)),
    )
    out["loss_electric_MWh"], out["loss_heat_MWh"], out["loss_MWh"]=lossP, lossH, lossP+lossH
    out["model_pass"]=all(x["pass"] for x in rows if x["scope"]=="adopted")
    out["loss_pass"]=last(rows)["pass"]
    out["exchange_exact_pass"]=all(x["pass"] for x in rows if x["scope"]=="exact_exchange")
    out["max_simultaneous_charge_discharge_MW"]=simultaneous
    out["mutual_exclusivity_pass"]=simultaneous<=pt
    if haskey(r, "lower_bound_MWh")
        gap=(lossP+lossH-r["lower_bound_MWh"])/max(1, abs(lossP+lossH))
        out["relative_gap"]=gap
        out["optimality_pass"]=out["model_pass"] && -1e-6<=gap<=1e-4
    end
    if !aggregate_heat
        out["shared_block_pass"]=out["model_pass"]
        out["model_pass"]=false
        out["optimality_pass"]=false
        out["exchange_exact_pass"]=false
    end
    out
end
