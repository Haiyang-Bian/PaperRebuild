"""
    build_r7_normal(case; optimizer=nothing, fixed_commitments=nothing,
                    fixed_battery_modes=nothing)

构建给定管流、固定电拓扑的正常经济调度，不求解、不写文件。采用(6-1)至(6-46)的
显式解释：共享CHP启停、逐场景设备、电池周期能量、线性电网、正端口混合和双管输运。
给定流量使水力与热耦合线性；实际MOI类型决定LP/MILP，不据此宣称原变流量模型为MILP。
互斥电池模式按设备ID提供时段×场景矩阵；不传时保留整数决策，不固定灾时电池的末端能量。
"""
function build_r7_normal(
    c::R7NormalCase;
    optimizer = nothing,
    fixed_commitments = nothing,
    fixed_battery_modes = nothing,
)
    r7_normal_assert(c)
    d=c.data
    e, h=d["electric"], d["heat"]
    ds, ls, ps=d["devices"], e["lines"], h["pipes"]
    T, W, N, J, G=d["periods"], length(d["probabilities"]), e["nodes"], h["nodes"], length(ds)
    dt=d["dt_h"]
    cp=h["c_J_kgK"]/1e6
    m=optimizer===nothing ? Model() : Model(optimizer)
    variables=Dict{String,Any}()
    for (k, s) in sort(collect(r7_normal_shape(c)); by = first)
        variables[k]=reshape(
            [@variable(m, base_name=k*"["*join(Tuple(I), ",")*"]") for I in CartesianIndices(s)],
            s,
        )
    end
    rows=Dict{String,Vector{Any}}()
    r7_add_battery_domain!(m, d, variables, rows; fixed_modes = fixed_battery_modes)
    add(id, x) = (push!(get!(rows, id, Any[]), x); x)
    function bounds(id, x, lo, hi)
        add(id, @constraint(m, x>=lo))
        add(id, @constraint(m, x<=hi))
    end
    P, Q, H, Pch, Pdis, E=(variables[k] for k in ("P", "Q", "H", "P_ch", "P_dis", "E_BES"))
    PP, QP, Pl, Ql, v=(variables[k] for k in ("P_PCC", "Q_PCC", "P_line", "Q_line", "v"))
    S, R, Ts, Td=(variables[k] for k in ("τ_S", "τ_R", "τ_source", "τ_load"))
    chp=Dict{String,Any}()
    chpids=Set(g["id"] for g in ds if g["kind"]=="CHP")
    fixed_commitments===nothing ||
        Set(keys(fixed_commitments))==chpids ||
        error("固定启停必须覆盖全部且仅CHP设备")
    for (g, z) in enumerate(ds)
        if z["kind"]=="CHP"
            s=r7_normal_chp(d, z)
            b=add_r7_chp_commitment!(
                m,
                s;
                fixed_u = fixed_commitments===nothing ? nothing : fixed_commitments[z["id"]],
            )
            chp[z["id"]]=b
            for (id, cs) in b.constraints, x in cs
                add(id, x)
            end
            for t in 1:T, w in 1:W
                for (a, k) in ((P, "P_CHP"), (Q, "Q_CHP"), (H, "H_CHP"))
                    add("R7-D-device-link", @constraint(m, a[g, t, w]==b.variables[k][t, w]))
                end
            end
        end
        for t in 1:T, w in 1:W
            kind=z["kind"]
            if kind!="CHP"
                upper=kind=="PV" ? z["available_MW"][t][w] : kind=="BES" ? 0.0 : z["P_max_MW"]
                bounds("6-8:10", P[g, t, w], 0, upper)
                bounds("6-9", Q[g, t, w], 0, kind=="GT" ? z["Q_max_Mvar"] : 0)
                if kind=="EB"
                    add("6-11", @constraint(m, H[g, t, w]==z["heat_ratio"]*P[g, t, w]))
                else
                    add("6-11-zero", @constraint(m, H[g, t, w]==0))
                end
            end
            if kind=="BES"
                bounds("6-12", Pch[g, t, w], 0, z["P_max_MW"])
                bounds("6-12", Pdis[g, t, w], 0, z["P_max_MW"])
                add("6-12", @constraint(m, Pch[g, t, w]+Pdis[g, t, w]<=z["P_max_MW"]))
                add(
                    "6-14",
                    @constraint(
                        m,
                        E[g, t+1, w]-E[g, t, w]==dt*(
                            z["eta_ch"]*Pch[g, t, w]-Pdis[g, t, w]/z["eta_dis"]
                        )
                    )
                )
            else
                add("6-12-zero", @constraint(m, Pch[g, t, w]==0))
                add("6-12-zero", @constraint(m, Pdis[g, t, w]==0))
            end
        end
        for w in 1:W, k in 1:(T+1)
            if z["kind"]=="BES"
                bounds("6-13", E[g, k, w], z["E_min_MWh"], z["E_max_MWh"])
                k==1 && add("R7-D-battery-initial", @constraint(m, E[g, k, w]==z["initial_MWh"][w]))
                k==T+1 && add("6-15", @constraint(m, E[g, k, w]==E[g, 1, w]))
            else
                add("6-13-zero", @constraint(m, E[g, k, w]==0))
            end
        end
    end
    for t in 1:T, w in 1:W
        bounds("R7-D-PCC-bounds", PP[t, w], e["pcc_min_MW"], e["pcc_max_MW"])
        bounds("R7-D-PCC-bounds", QP[t, w], e["qcc_min_Mvar"], e["qcc_max_Mvar"])
        for n in 1:N
            bounds("6-22", v[n, t, w], e["v_min_pu"], e["v_max_pu"])
            n==e["pcc_node"] && add("R7-D-root-voltage", @constraint(m, v[n, t, w]==e["v_ref_pu"]))
            pg=sum(
                (z["kind"]=="EB" ? -P[g, t, w] : P[g, t, w])+Pdis[g, t, w]-Pch[g, t, w] for
                (g, z) in enumerate(ds) if z["electric_node"]==n;
                init = 0.0,
            )
            qg=sum(Q[g, t, w] for (g, z) in enumerate(ds) if z["electric_node"]==n; init = 0.0)
            pin=sum(Pl[l, t, w] for (l, z) in enumerate(ls) if z["to"]==n; init = 0.0)
            pout=sum(Pl[l, t, w] for (l, z) in enumerate(ls) if z["from"]==n; init = 0.0)
            qin=sum(Ql[l, t, w] for (l, z) in enumerate(ls) if z["to"]==n; init = 0.0)
            qout=sum(Ql[l, t, w] for (l, z) in enumerate(ls) if z["from"]==n; init = 0.0)
            # 根节点也纳入完整节点守恒；根上设备/负荷不能在PCC=支路流的简记中消失。
            add(
                "6-18:19",
                @constraint(m, pg+pin+(n==e["pcc_node"] ? PP[t, w] : 0)==pout+e["load_MW"][n][t])
            )
            add(
                "6-20",
                @constraint(
                    m,
                    qg+qin+(n==e["pcc_node"] ? QP[t, w] : 0)==qout+e["tan_phi"][n]*e["load_MW"][n][t]
                )
            )
        end
        for (l, z) in enumerate(ls)
            closed=z["base_closed"]
            sgn=e["flow_domain"]=="signed" ? -1 : 0
            bounds("6-24:25", Pl[l, t, w], sgn*z["P_max_MW"]*closed, z["P_max_MW"]*closed)
            bounds("6-24:25", Ql[l, t, w], sgn*z["Q_max_Mvar"]*closed, z["Q_max_Mvar"]*closed)
            closed==1 && add(
                "R7-D-voltage",
                @constraint(
                    m,
                    v[z["from"], t, w]-v[z["to"], t, w]==(
                        z["r_pu"]*Pl[l, t, w]+z["x_pu"]*Ql[l, t, w]
                    )/(e["S_base_MVA"]*e["v_ref_pu"])
                )
            )
        end
        for j in 1:J
            for (x, side) in ((S, "S"), (R, "R"), (Ts, "S"), (Td, "R"))
                bounds("6-27:29", x[j, t, w], h["$(side)_min_K"], h["$(side)_max_K"])
            end
            ms, md=h["source_flow_kg_s"][j][t], h["load_flow_kg_s"][j][t]
            generated=sum(
                H[g, t, w] for
                (g, z) in enumerate(ds) if z["kind"] in ("CHP", "EB")&&z["heat_node"]==j;
                init = 0.0,
            )
            add("6-26", @constraint(m, generated==cp*ms*(Ts[j, t, w]-R[j, t, w])))
            add("6-28", @constraint(m, h["load_MW"][j][t]==cp*md*(S[j, t, w]-Td[j, t, w])))
            ms>0 ?
            bounds(
                "R7-D-port-delta",
                Ts[j, t, w]-R[j, t, w],
                h["source_delta_min"][j],
                h["source_delta_max"][j],
            ) : add("R7-D-idle-port", @constraint(m, Ts[j, t, w]==S[j, t, w]))
            md>0 ?
            bounds(
                "R7-D-port-delta",
                S[j, t, w]-Td[j, t, w],
                h["load_delta_min"][j],
                h["load_delta_max"][j],
            ) : add("R7-D-idle-port", @constraint(m, Td[j, t, w]==R[j, t, w]))
            sins=sum(
                p["normal_flow_kg_s"][t]*variables["τ_pipe_S"][a, t, w] for
                (a, p) in enumerate(ps) if p["to"]==j;
                init = 0.0,
            )
            rins=sum(
                p["normal_flow_kg_s"][t]*variables["τ_pipe_R"][a, t, w] for
                (a, p) in enumerate(ps) if p["from"]==j;
                init = 0.0,
            )
            fs=ms+sum(p["normal_flow_kg_s"][t] for p in ps if p["to"]==j; init = 0.0)
            fr=md+sum(p["normal_flow_kg_s"][t] for p in ps if p["from"]==j; init = 0.0)
            add("R7-D-mix-S", @constraint(m, S[j, t, w]==(sins+ms*Ts[j, t, w])/fs))
            add("R7-D-mix-R", @constraint(m, R[j, t, w]==(rins+md*Td[j, t, w])/fr))
        end
    end
    for (a, p) in enumerate(ps), side in ("S", "R")
        k=r7_normal_pipe_map(d, p, side)
        node=p[side=="S" ? "from" : "to"]
        input=side=="S" ? S : R
        out, energy=variables["τ_pipe_$side"], variables["E_pipe_$side"]
        cap=h["c_J_kgK"]*h["rho_kg_m3"]*p["volume_$(side)_m3"]/3.6e9*(
            h["$(side)_max_K"]-h["$(side)_min_K"]
        )
        for w in 1:W
            for t in 1:T
                add(
                    "R7-D-transport",
                    @constraint(
                        m,
                        out[a, t, w]==k.b[t, w]+sum(k.A[t, s]*input[node, s, w] for s in 1:T)
                    )
                )
                bounds(
                    "R7-D-pipe-temperature",
                    out[a, t, w],
                    h["$(side)_min_K"],
                    h["$(side)_max_K"],
                )
            end
            for t in 1:(T+1)
                add(
                    "R7-D-inventory",
                    @constraint(
                        m,
                        energy[a, t, w]==k.eb[t, w]+sum(k.E[t, s]*input[node, s, w] for s in 1:T)
                    )
                )
                bounds("R7-D-inventory-domain", energy[a, t, w], 0, cap)
            end
            d["heat_terminal_rule"]=="pipe_inventory_initial" &&
                add("R7-D-thermal-terminal", @constraint(m, energy[a, T+1, w]==energy[a, 1, w]))
        end
    end
    # 给定管流下压降是常数。回水沿to→from，不能照抄同一供水方向的平方压降。
    for t in 1:T
        for j in 1:J
            for side in ("S", "R")
                bounds("6-35", variables["Φ_$side"][j, t], 0, h["pressure_max_Pa"])
            end
            bounds(
                "6-36",
                variables["Φ_S"][j, t]-variables["Φ_R"][j, t],
                h["delta_pressure_min_Pa"],
                h["delta_pressure_max_Pa"],
            )
        end
        for (a, p) in enumerate(ps), side in ("S", "R")
            i, j=side=="S" ? (p["from"], p["to"]) : (p["to"], p["from"])
            valve=variables["Φ_val_$side"][a, t]
            bounds("6-35", valve, 0, p["valve_max_Pa"])
            # 以输入压力基准缩放等式，保存/验算仍使用Pa及无量纲残差。
            add(
                "R7-D-pressure-$side",
                @constraint(
                    m,
                    (variables["Φ_$side"][i, t]-variables["Φ_$side"][j, t]-valve)/h["pressure_max_Pa"]==p["mu_$(side)_Pa_s2_kg2"]*p["normal_flow_kg_s"][t]^2/h["pressure_max_Pa"]
                )
            )
        end
    end
    startup=sum(b.startup_cost for b in values(chp); init = 0.0)
    running=dt*sum(
        d["probabilities"][w]*(
            e[r7_money_key(d, "price_USD_MWh")][t]*PP[t, w]+sum(
                z[r7_money_key(d, "cost_P_USD_MWh")]*(
                    z["kind"]=="BES" ? Pch[g, t, w]+Pdis[g, t, w] : P[g, t, w]
                ) for (g, z) in enumerate(ds);
                init = 0.0,
            )
        ) for t in 1:T, w in 1:W
    )
    @objective(m, Min, startup+running)
    types=list_of_constraint_types(m)
    all(
        F in (VariableRef, AffExpr) && S_ in
        (MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.EqualTo{Float64}, MOI.ZeroOne) for
        (F, S_) in types
    ) || error("正常条件模型含未声明约束类型")
    (;
        model = m,
        variables,
        chp,
        constraints = rows,
        model_class = any(is_binary, all_variables(m)) ? "MILP" : "LP",
        model_types = [string(F)*" in "*string(S_) for (F, S_) in types],
    )
end
