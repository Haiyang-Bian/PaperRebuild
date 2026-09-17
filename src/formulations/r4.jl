"""
    build_r4_model(case; spec=R4Spec(), optimizer=nothing, stage=:central,
                   actor=0, frozen=nothing, modes=nothing)

构建第4章采用模型，不求解/写文件。MW/MWh；电支路内部使用标幺平方量。
stage=:local为聚合商自调度；:network冻结聚合商全部物理控制；:central联合优化。
modes可指定逐时电池充电状态，用于16种状态穷举的连续凸对照。
式(4-1)–(4-59)的采用范围见第4章台账；R4-P1–P7是显式项目补全。
返回模型、变量、公式映射、实际MOI类型与成本表达式。热网仅为稳态能量流包络。
"""
function build_r4_model(
    c::R4Case;
    spec = R4Spec(),
    optimizer = nothing,
    stage = :central,
    actor = 0,
    frozen = nothing,
    modes = nothing,
)
    TOML.parse(c.source_text)==c.data || error("输入被原位改写，请构造新的R4Case")
    stage in (:central, :local, :network) || error("建模阶段错误")
    stage==:local && !(actor in (2, 3)) && error("AG0只对聚合商A/B独立调度")
    stage==:network && frozen===nothing && error("网络校核必须提供冻结计划")
    d=c.data
    T=d["T"]
    dt=d["dt_h"]
    actors=d["actors"]
    model=optimizer===nothing ? Model() : Model(optimizer)
    variables=Dict{String,Any}()
    for key in
        ("P_CHP", "P_PV", "P_HP", "P_EB", "P_ch", "P_dis", "P_D", "H_D", "H_src", "w_P", "w_H")
        variables[key]=@variable(model, [1:3, 1:T], lower_bound=0, base_name=key)
    end
    v=variables
    v["E"]=@variable(model, [1:3, 1:(T+1)], lower_bound=0, base_name="E")
    active(i) = stage!=:local || i==actor
    b=findfirst(i->active(i) && actors[i]["BS_power_max"]>0, 1:3)
    if modes!==nothing
        length(modes)==T && all(x->x in (0, 1), modes) || error("电池模式错误")
    end
    z=@variable(model, [1:T], lower_bound=0, upper_bound=1, base_name="z")
    v["z"]=z
    for t in 1:T
        b===nothing ? fix(z[t], 0; force = true) :
        modes===nothing ? set_binary(z[t]) : fix(z[t], modes[t]; force = true)
    end
    capmap=Dict(
        "P_CHP"=>"CHP_max",
        "P_HP"=>"HP_max",
        "P_EB"=>"EB_max",
        "P_ch"=>"BS_power_max",
        "P_dis"=>"BS_power_max",
    )
    resource=AffExpr(0.0)
    dissatisfaction=AffExpr(0.0)
    for i in 1:3
        a=actors[i]
        on=active(i)
        for t in 1:T
            for (k, cap) in capmap
                set_upper_bound(v[k][i, t], on ? a[cap] : 0.0)
            end
            set_upper_bound(v["P_PV"][i, t], on ? a["PV_max"]*a["PV_profile"][t] : 0.0)
            for carrier in ("P", "H")
                ref=on ? a[carrier*"_load"][t] : 0.0
                lo=(1-a["flex"])*ref
                hi=(1+a["flex"])*ref
                set_lower_bound(v[carrier*"_D"][i, t], lo)
                set_upper_bound(v[carrier*"_D"][i, t], hi)
                w=v["w_"*carrier][i, t]
                # (4-4)、(4-21)：选择凸递减不满意度 a(Dmax-D)^2；锥上图保持精确最优值。
                if on && a["sat_"*carrier]>0
                    @constraint(
                        model,
                        [w, 0.5, hi-v[carrier*"_D"][i, t]] in RotatedSecondOrderCone()
                    )
                    add_to_expression!(dissatisfaction, dt*a["sat_"*carrier], w)
                else
                    fix(w, 0; force = true)
                end
            end
            @constraint(
                model,
                v["H_src"][i, t]==a["heat_ratio"]*v["P_CHP"][i, t]+a["COP_HP"]*v["P_HP"][i, t]+a["COP_EB"]*v["P_EB"][
                    i,
                    t,
                ]
            )
            # R4-P2：t对应时段，E列1对应初态；Δt从MW转为MWh。
            @constraint(
                model,
                v["E"][i, t+1]==v["E"][i, t]+dt*(
                    a["eta_ch"]*v["P_ch"][i, t]-v["P_dis"][i, t]/a["eta_dis"]
                )
            )
            if i==b
                @constraint(model, v["P_ch"][i, t]<=a["BS_power_max"]*z[t])
                @constraint(model, v["P_dis"][i, t]<=a["BS_power_max"]*(1-z[t]))
            end
            add_to_expression!(resource, dt*a["CHP_cost"], v["P_CHP"][i, t])
            add_to_expression!(resource, dt*a["PV_cost"], v["P_PV"][i, t])
            add_to_expression!(resource, dt*a["BS_cost"], v["P_ch"][i, t])
            add_to_expression!(resource, dt*a["BS_cost"], v["P_dis"][i, t])
        end
        for t in 1:(T+1)
            set_upper_bound(v["E"][i, t], on ? a["BS_energy_max"] : 0.0)
        end
        fix(v["E"][i, 1], on ? a["BS_initial"] : 0.0; force = true)
        fix(v["E"][i, T+1], on ? a["BS_initial"] : 0.0; force = true)
    end
    P_net=@expression(
        model,
        [i=1:3, t=1:T],
        v["P_CHP"][i, t]+v["P_PV"][i, t]+v["P_dis"][i, t]-v["P_ch"][i, t]-v["P_HP"][i, t]-v["P_EB"][
            i,
            t,
        ]-v["P_D"][i, t]
    )
    H_net=@expression(model, [i=1:3, t=1:T], v["H_src"][i, t]-v["H_D"][i, t])
    external=AffExpr(0.0)
    settlement=AffExpr(0.0)
    if stage==:local
        a=actors[actor]
        price=d["settlement"]
        for carrier in ("P", "H")
            buy=@variable(
                model,
                [1:T],
                lower_bound=0,
                upper_bound=a["retail_limit"],
                base_name=carrier*"_buy"
            )
            sell=@variable(
                model,
                [1:T],
                lower_bound=0,
                upper_bound=a["retail_limit"],
                base_name=carrier*"_sell"
            )
            v[carrier*"_buy"]=buy
            v[carrier*"_sell"]=sell
            net=carrier=="P" ? P_net : H_net
            for t in 1:T
                @constraint(model, net[actor, t]==sell[t]-buy[t])
                add_to_expression!(settlement, dt*price[carrier*"_buy"], buy[t])
                add_to_expression!(settlement, -dt*price[carrier*"_sell"], sell[t])
            end
        end
    else
        if stage==:network
            for local_run in frozen
                i=local_run["actor"]
                for k in ("P_CHP", "P_PV", "P_HP", "P_EB", "P_ch", "P_dis", "P_D", "H_D", "E")
                    x=r4_matrix(local_run["values"][k])
                    for t in axes(x, 2)
                        @constraint(model, v[k][i, t]==x[i, t])
                    end
                end
            end
        end
        e=d["electric"]
        edges=e["edges"]
        base=e["S_base_MVA"]
        v["P_grid"]=@variable(
            model,
            [1:T],
            lower_bound=0,
            upper_bound=e["grid_max"],
            base_name="P_grid"
        )
        v["Q_grid"]=@variable(
            model,
            [1:T],
            lower_bound=-e["Q_grid_max"],
            upper_bound=e["Q_grid_max"],
            base_name="Q_grid"
        )
        v["v"]=@variable(
            model,
            [1:3, 1:T],
            lower_bound=e["v_min"]^2,
            upper_bound=e["v_max"]^2,
            base_name="v"
        )
        for k in ("P_branch", "Q_branch")
            v[k]=@variable(model, [1:2, 1:T], base_name=k)
        end
        v["ell"]=@variable(model, [1:2, 1:T], lower_bound=0, base_name="ell")
        for t in 1:T
            fix(v["v"][1, t], 1; force = true)
            add_to_expression!(external, dt*d["grid_price"][t], v["P_grid"][t])
            for (p, edge) in enumerate(edges)
                i=edge["from"]
                j=edge["to"]
                r=edge["r"]
                x=edge["x"]
                P=v["P_branch"][p, t]
                Q=v["Q_branch"][p, t]
                ell=v["ell"][p, t]
                vi=v["v"][i, t]
                for (var, cap) in ((P, edge["P_max"]/base), (Q, edge["Q_max"]/base))
                    set_lower_bound(var, -cap)
                    set_upper_bound(var, cap)
                end
                set_upper_bound(ell, edge["ell_max"])
                @constraint(model, v["v"][j, t]==vi-2*(r*P+x*Q)+(r^2+x^2)*ell)
                if spec.electric==:socp
                    @constraint(model, [vi+ell, 2P, 2Q, vi-ell] in SecondOrderCone())
                else
                    # 原支路等式显式选择，不能以锥松弛合格替代。
                    @constraint(model, vi*ell==P^2+Q^2)
                end
            end
            for i in 1:3
                incoming=findall(p->p["to"]==i, edges)
                outgoing=findall(p->p["from"]==i, edges)
                @constraint(
                    model,
                    P_net[i, t]/base+(i==1 ? v["P_grid"][t]/base : 0)+sum(
                        v["P_branch"][p, t]-edges[p]["r"]*v["ell"][p, t] for p in incoming;
                        init = 0,
                    )==sum(v["P_branch"][p, t] for p in outgoing; init = 0)
                )
                @constraint(
                    model,
                    -actors[i]["Q_ratio"]*v["P_D"][i, t]/base+(i==1 ? v["Q_grid"][t]/base : 0)+sum(
                        v["Q_branch"][p, t]-edges[p]["x"]*v["ell"][p, t] for p in incoming;
                        init = 0,
                    )==sum(v["Q_branch"][p, t] for p in outgoing; init = 0)
                )
            end
        end
        h=d["heat"]
        pipes=h["pipes"]
        for k in ("H_in", "H_out", "m_pipe")
            v[k]=@variable(model, [1:2, 1:T], lower_bound=0, base_name=k)
        end
        for k in ("m_source", "m_load")
            v[k]=@variable(model, [1:3, 1:T], lower_bound=0, base_name=k)
        end
        for t in 1:T
            for (p, pipe) in enumerate(pipes)
                set_upper_bound(v["m_pipe"][p, t], pipe["flow_max"])
                set_upper_bound(v["H_in"][p, t], pipe["H_max"])
                set_upper_bound(v["H_out"][p, t], pipe["H_max"])
                @constraint(model, v["H_out"][p, t]==v["H_in"][p, t]-r4_loss(pipe))
            end
            for i in 1:3
                ms=v["m_source"][i, t]
                ml=v["m_load"][i, t]
                set_upper_bound(ms, actors[i]["port_flow_max"])
                set_upper_bound(ml, actors[i]["port_flow_max"])
                for (m, H, port) in ((ms, v["H_src"][i, t], "source"), (ml, v["H_D"][i, t], "load"))
                    @constraint(model, H>=h["cp"]*h[port*"_delta_min"]*m/1e6)
                    @constraint(model, H<=h["cp"]*h[port*"_delta_max"]*m/1e6)
                end
                incoming=findall(p->p["to"]==i, pipes)
                outgoing=findall(p->p["from"]==i, pipes)
                @constraint(
                    model,
                    ms+sum(v["m_pipe"][p, t] for p in incoming; init = 0)==ml+sum(
                        v["m_pipe"][p, t] for p in outgoing;
                        init = 0,
                    )
                )
                @constraint(
                    model,
                    v["H_src"][i, t]+sum(v["H_out"][p, t] for p in incoming; init = 0)==v["H_D"][
                        i,
                        t,
                    ]+sum(v["H_in"][p, t] for p in outgoing; init = 0)
                )
            end
        end
    end
    @objective(model, Min, resource+dissatisfaction+external+settlement)
    types=string.(list_of_constraint_types(model))
    return (;
        model,
        variables,
        resource,
        dissatisfaction,
        external,
        settlement,
        stage,
        actor,
        formula_map = Dict(
            "devices"=>"ch04-004:013",
            "electric"=>"ch04-026:033",
            "heat"=>"ch04-041:047",
            "balance"=>"R4-P1:7",
        ),
        model_types = types,
        model_class = spec.electric==:exact && stage!=:local ? "nonconvex_quadratic" :
                      b!==nothing && modes===nothing ? "MISOCP" : "SOCP",
    )
end
