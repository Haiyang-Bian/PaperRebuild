const R5_DISPATCH_MODEL_FILE = @__FILE__

"""
    build_r5_dispatch(case; optimizer=nothing)

构建给定成交/调用轨迹的连续IES补救LP，不求解、不写文件。
采用(5-1)至(5-31)的核查解释：正购电、EB耗电、总受热进入建筑、固定流量节点法。
返回变量、逐约束公式映射及实际MOI类型；线性配电网不等于交流原支路等式。
"""
function build_r5_dispatch(c::R5DispatchCase; optimizer = nothing)
    r5_dispatch_assert_case(c)
    d=c.data
    T, B, L, N, A, S, J, G=r5_dispatch_sizes(c)
    e, h, a, rt=d["electric"], d["heat"], d["award"], d["realtime"]
    ds, bs, ss, ps, ls=d["devices"], d["buildings"], h["sources"], h["pipes"], e["lines"]
    dt=d["dt_h"]
    cp=h["c_J_kgK"]/1e6
    m=optimizer===nothing ? Model() : Model(optimizer)
    @variable(m, P_DER[1:G, 1:T])
    @variable(m, Q_DER[1:G, 1:T])
    @variable(m, P_PCC[1:1, 1:T])
    @variable(m, Q_PCC[1:1, 1:T])
    @variable(m, P_line[1:L, 1:T])
    @variable(m, Q_line[1:L, 1:T])
    @variable(m, v[1:B, 1:T])
    @variable(m, τ_S[1:N, 1:T])
    @variable(m, τ_R[1:N, 1:T])
    @variable(m, τ_src[1:S, 1:T])
    @variable(m, τ_load_R[1:J, 1:T])
    @variable(m, τ_pipe_S[1:A, 1:T])
    @variable(m, τ_pipe_R[1:A, 1:T])
    @variable(m, H_D[1:J, 1:T]>=0)
    @variable(m, P_DH[1:J, 1:T]>=0)
    @variable(m, τ_IN[1:J, 1:T])
    @variable(m, delivery[1:1, 1:T])
    @variable(m, mismatch[1:1, 1:T]>=0)
    variables=(;
        P_DER,
        Q_DER,
        P_PCC,
        Q_PCC,
        P_line,
        Q_line,
        v,
        τ_S,
        τ_R,
        τ_src,
        τ_load_R,
        τ_pipe_S,
        τ_pipe_R,
        H_D,
        P_DH,
        τ_IN,
        delivery,
        mismatch,
    )
    rows=Dict{String,ConstraintRef}()
    add(id, entity, t, ref) = (rows["$id/$entity/$t"]=ref)
    bounds(x, lo, hi) = (set_lower_bound(x, lo); set_upper_bound(x, hi))
    for t in 1:T
        bounds(P_PCC[1, t], e["pcc_min_MW"], e["pcc_max_MW"])
        bounds(Q_PCC[1, t], e["qcc_min_Mvar"], e["qcc_max_Mvar"])
        for n in 1:B
            bounds(v[n, t], e["v_min_pu"], e["v_max_pu"])
        end
        add("5-17", "root", t, @constraint(m, v[e["root"], t]==e["v_ref_pu"]))
        for g in 1:G
            z=ds[g]
            upper=z["kind"]=="PV" ? z["available_MW"][t] : z["p_max_MW"]
            bounds(P_DER[g, t], z["p_min_MW"], upper)
            bounds(Q_DER[g, t], z["q_min_Mvar"], z["q_max_Mvar"])
            if z["kind"] in ("CHP", "GT")
                prev=t==1 ? z["P_initial_MW"] : P_DER[g, t-1]
                add("5-10-up", z["id"], t, @constraint(m, P_DER[g, t]-prev<=dt*z["ramp_up_MW_h"]))
                add(
                    "5-10-down",
                    z["id"],
                    t,
                    @constraint(m, prev-P_DER[g, t]<=dt*z["ramp_down_MW_h"])
                )
            end
        end
        for b in 1:B
            # EB的P为非负耗电；GT恢复到发电集合，不能沿印刷5-14把EB加到供电端。
            pgen=sum(
                (z["kind"]=="EB" ? -1 : 1)*P_DER[g, t] for (g, z) in enumerate(ds) if z["node"]==b;
                init = 0.0,
            )
            qgen=sum(Q_DER[g, t] for (g, z) in enumerate(ds) if z["node"]==b; init = 0.0)
            plocal=sum(P_DH[j, t] for (j, z) in enumerate(bs) if z["electric_node"]==b; init = 0.0)
            pin=sum(P_line[l, t] for (l, z) in enumerate(ls) if z["to"]==b; init = 0.0)
            pout=sum(P_line[l, t] for (l, z) in enumerate(ls) if z["from"]==b; init = 0.0)
            qin=sum(Q_line[l, t] for (l, z) in enumerate(ls) if z["to"]==b; init = 0.0)
            qout=sum(Q_line[l, t] for (l, z) in enumerate(ls) if z["from"]==b; init = 0.0)
            add(
                "5-14",
                b,
                t,
                @constraint(
                    m,
                    pgen+pin+(b==e["root"] ? P_PCC[1, t] : 0)==pout+e["P_load_MW"][b][t]+plocal
                )
            )
            add(
                "5-15",
                b,
                t,
                @constraint(
                    m,
                    qgen+qin+(b==e["root"] ? Q_PCC[1, t] : 0)==qout+e["Q_load_Mvar"][b][t]
                )
            )
        end
        for (l, z) in enumerate(ls)
            bounds(P_line[l, t], -z["P_limit_MW"], z["P_limit_MW"])
            bounds(Q_line[l, t], -z["Q_limit_Mvar"], z["Q_limit_Mvar"])
            # 幅值v而非v²，功率除以三相基准容量；保留作者线性化的适用边界。
            add(
                "5-16",
                z["id"],
                t,
                @constraint(
                    m,
                    v[z["to"], t]==v[z["from"], t]-(z["r_pu"]*P_line[l, t]+z["x_pu"]*Q_line[l, t])/(
                        e["S_base_MVA"]*e["v_ref_pu"]
                    )
                )
            )
        end
        for n in 1:N
            bounds(τ_S[n, t], h["S_min_K"], h["S_max_K"])
            bounds(τ_R[n, t], h["R_min_K"], h["R_max_K"])
            # 供水按物理入流混合；回水沿相反管向流动，分别加入热源/负荷端口。
            ms=sum(z["m_kg_s"] for z in ps if z["from"]==n; init = 0.0)+sum(
                z["m_kg_s"] for z in bs if z["heat_node"]==n;
                init = 0.0,
            )
            mr=sum(z["m_kg_s"] for z in ps if z["to"]==n; init = 0.0)+sum(
                z["m_kg_s"] for z in ss if z["node"]==n;
                init = 0.0,
            )
            sins=sum(
                z["m_kg_s"]*τ_pipe_S[p, t] for (p, z) in enumerate(ps) if z["to"]==n;
                init = 0.0,
            )+sum(z["m_kg_s"]*τ_src[s, t] for (s, z) in enumerate(ss) if z["node"]==n; init = 0.0)
            rins=sum(
                z["m_kg_s"]*τ_pipe_R[p, t] for (p, z) in enumerate(ps) if z["from"]==n;
                init = 0.0,
            )+sum(
                z["m_kg_s"]*τ_load_R[j, t] for (j, z) in enumerate(bs) if z["heat_node"]==n;
                init = 0.0,
            )
            add("5-20", n, t, @constraint(m, τ_S[n, t]==sins/ms))
            add("5-21", n, t, @constraint(m, τ_R[n, t]==rins/mr))
        end
        for (s, z) in enumerate(ss)
            bounds(τ_src[s, t], z["T_min_K"], z["T_max_K"])
            generated=sum(
                dev["heat_ratio"]*P_DER[g, t] for (g, dev) in enumerate(ds) if
                dev["kind"] in ("CHP", "EB") && dev["source_id"]==z["id"];
                init = 0.0,
            )
            add(
                "5-18",
                z["id"],
                t,
                @constraint(m, generated==cp*z["m_kg_s"]*(τ_src[s, t]-τ_R[z["node"], t]))
            )
        end
        for (j, z) in enumerate(bs)
            bounds(τ_load_R[j, t], z["R_min_K"], z["R_max_K"])
            bounds(τ_IN[j, t], z["T_min_K"], z["T_max_K"])
            set_upper_bound(P_DH[j, t], z["P_DH_max_MW"])
            add(
                "5-19",
                z["id"],
                t,
                @constraint(m, H_D[j, t]==cp*z["m_kg_s"]*(τ_S[z["heat_node"], t]-τ_load_R[j, t]))
            )
            previous=t==1 ? z["T_initial_K"] : τ_IN[j, t-1]
            # 总受热为热网交付+本地产热；用K形式建模以避免热容尺度掩盖温度误差。
            coeff=r5_building_coefficients(z["C_MWh_K"], z["G_MW_K"], dt)
            add(
                "R5-D-building",
                z["id"],
                t,
                @constraint(
                    m,
                    (1+coeff.U)*τ_IN[j, t]==previous+coeff.η_H*(H_D[j, t]+z["COP_DH"]*P_DH[j, t])+coeff.U*d["ambient_K"][t]
                )
            )
            if t==T && z["terminal_rule"]=="initial"
                add("R5-D-terminal", z["id"], t, @constraint(m, τ_IN[j, t]==z["T_initial_K"]))
            end
        end
        add("R5-D-delivery", "PCC", t, @constraint(m, delivery[1, t]==a["P_DA_MW"][t]-P_PCC[1, t]))
        request=rt["alpha_up"][t]*a["R_up_MW"][t]-rt["alpha_down"][t]*a["R_down_MW"][t]
        add("5-3-plus", "PCC", t, @constraint(m, mismatch[1, t]>=request-delivery[1, t]))
        add("5-3-minus", "PCC", t, @constraint(m, mismatch[1, t]>=delivery[1, t]-request))
    end
    for (p, z) in enumerate(ps)
        k=fixed_flow_kernel(
            z["m_kg_s"],
            z["rho_kg_m3"],
            z["area_m2"],
            z["length_m"],
            dt,
            z["loss_W_mK"];
            c_w = h["c_J_kgK"]/1000,
        )
        for (side, from, output, hist) in (
            ("S", z["from"], τ_pipe_S, z["history_S_K"]),
            ("R", z["to"], τ_pipe_R, z["history_R_K"]),
        )
            input=side=="S" ? τ_S : τ_R
            for t in 1:T
                adv=sum(
                    w*(t-lag>0 ? input[from, t-lag] : hist[end+t-lag]) for
                    (lag, w) in zip(k.lags, k.weights)
                )
                # 5-25/26：显式历史+作者节点法J；不是新PDE精确衰减版本。
                add(
                    "5-25-26-$side",
                    z["id"],
                    t,
                    @constraint(m, output[p, t]==d["ambient_K"][t]+k.J*(adv-d["ambient_K"][t]))
                )
            end
        end
    end
    add(
        "5-4",
        "window",
        0,
        @constraint(m, dt*sum(mismatch)<=rt["delta"]*dt*sum(a["R_up_MW"]+a["R_down_MW"]))
    )
    fixed=dt*sum(
        a["energy_price"] .* a["P_DA_MW"]-a["up_price"] .* a["R_up_MW"]-a["down_price"] .*
                                                                        a["R_down_MW"],
    )
    @objective(
        m,
        Min,
        fixed+dt*sum(z["cost_USD_MWh"]*P_DER[g, t] for (g, z) in enumerate(ds), t in 1:T)+dt*sum(
            -rt["price"][t]*delivery[1, t]+rt["penalty_USD_MWh"]*mismatch[1, t] for t in 1:T
        )
    )
    (;
        model = m,
        variables,
        rows,
        model_type = "continuous_LP",
        model_types = r5_market_lp_types(m),
        formulation = "r5_dispatch_checked_v1",
        fixed_day_ahead_cost = fixed,
    )
end
