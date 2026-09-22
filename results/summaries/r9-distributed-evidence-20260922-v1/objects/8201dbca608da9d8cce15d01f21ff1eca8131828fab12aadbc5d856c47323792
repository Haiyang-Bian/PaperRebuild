"""
    build_r4_model(case; spec=R4Spec(), optimizer=nothing, stage=:central,
                   actor=0, frozen=nothing, modes=nothing)

构建第4章采用模型，不求解/写文件。MW/MWh；电支路内部使用标幺平方量。
stage=:local为聚合商自调度；:network冻结聚合商全部物理控制；:central联合优化。
stage=:trading仅联合聚合商、显式匹配合同，忽略网络；用于TSPA第一阶段，不是物理调度。
stage=:agent仅含单个聚合商资源；:operator仅含DSO资源/网络和明确的边界副本，用于分布接口。
balance_penalty非nothing时仅在network阶段对节点P/Q/H/质量平衡加入有单位的罚松弛，
设备、容量、端口、电压降和支路关系仍保持为硬约束；不保证任何输入都可被松弛救活。
modes可指定逐时电池充电状态，用于16种状态穷举的连续凸对照。
式(4-1)–(4-59)的采用范围见第4章台账；R4-P1–P7是显式项目补全。
返回模型、变量、公式映射、实际MOI类型与成本表达式。热网仅为稳态能量流包络。
详细温度/循环版本通过build_r4_thermal显式传入thermal；原接口不传时行为保持。
"""
function build_r4_model(
    c::R4Case;
    spec = R4Spec(),
    optimizer = nothing,
    stage = :central,
    actor = 0,
    frozen = nothing,
    modes = nothing,
    balance_penalty = nothing,
    switching = nothing,
    thermal = nothing,
)
    TOML.parse(c.source_text)==c.data || error("输入被原位改写，请构造新的R4Case")
    stage in (:central, :local, :network, :trading, :agent, :operator) || error("建模阶段错误")
    stage==:agent && !(actor in (2, 3)) && error("分布局部主体错误")
    stage==:local && !(actor in (2, 3)) && error("AG0只对聚合商A/B独立调度")
    stage==:network && frozen===nothing && error("网络校核必须提供冻结计划")
    thermal!==nothing && (
        stage==:central && switching!==nothing || error("详细稳态热模型目前仅支持显式重构集中调度")
    )
    balance_penalty!==nothing && (
        stage==:network && isfinite(balance_penalty) && balance_penalty>0 ||
        error("正的节点平衡罚系数仅适用于冻结网络诊断")
    )
    d=c.data
    if stage in (:central, :network, :operator)
        haskey(d, "network_control") == (switching!==nothing) || error("候选网络须显式调用重构接口")
    end
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
    active(i) =
        stage==:trading ? i>1 :
        stage==:operator ? i==1 : stage in (:local, :agent) ? i==actor : true
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
                preferred=on ? r4_preferred_demand(a, carrier, t) : 0.0
                # (4-4)、R4-B1：显式偏好与可调范围分离；旧输入仍按原上界取锚点。
                if on && a["sat_"*carrier]>0
                    # 新版w直接表示每小时不满意度成本，避免5000倍目标系数乘微小平方量。
                    # a>0下为完全等价的变量缩放，结果元数据保存单位；旧版保持MW²。
                    cost_scaled=get(d, "preference_model", "")=="explicit_reference_v1"
                    scale=cost_scaled ? sqrt(a["sat_"*carrier]) : 1.0
                    @constraint(
                        model,
                        [w, 0.5, scale*(preferred-v[carrier*"_D"][i, t])] in
                        RotatedSecondOrderCone()
                    )
                    add_to_expression!(
                        dissatisfaction,
                        dt*(cost_scaled ? 1.0 : a["sat_"*carrier]),
                        w,
                    )
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
            # R4-P3：t对应时段，E列1对应初态；Δt从MW转为MWh。
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
    P_device=@expression(
        model,
        [i=1:3, t=1:T],
        v["P_CHP"][i, t]+v["P_PV"][i, t]+v["P_dis"][i, t]-v["P_ch"][i, t]-v["P_HP"][i, t]-v["P_EB"][
            i,
            t,
        ]-v["P_D"][i, t]
    )
    # R4-D1：运营商只持有边界副本；不在其问题中优化聚合商设备。
    # Q负荷及热源/热负荷总量分别通信，不能仅从电热净注入猜测。
    if stage==:operator
        for key in ("P_interface", "Q_interface", "Hs_interface", "Hd_interface")
            v[key]=@variable(model, [1:2, 1:T], base_name=key)
        end
        for j in 1:2, t in 1:T
            a=actors[j+1]
            set_lower_bound(v["P_interface"][j, t], -a["retail_limit"])
            set_upper_bound(v["P_interface"][j, t], a["retail_limit"])
            for key in ("Q_interface", "Hs_interface", "Hd_interface")
                set_lower_bound(v[key][j, t], 0)
                set_upper_bound(v[key][j, t], a["retail_limit"])
            end
            set_upper_bound(v["Q_interface"][j, t], a["Q_ratio"]*a["P_load"][t]*(1+a["flex"]))
        end
    end
    P_net=[
        stage==:operator && i>1 ? v["P_interface"][i-1, t] : P_device[i, t] for i in 1:3, t in 1:T
    ]
    Q_load=[
        stage==:operator && i>1 ? v["Q_interface"][i-1, t] : actors[i]["Q_ratio"]*v["P_D"][i, t] for
        i in 1:3, t in 1:T
    ]
    H_source=[
        stage==:operator && i>1 ? v["Hs_interface"][i-1, t] : v["H_src"][i, t] for
        i in 1:3, t in 1:T
    ]
    H_demand=[
        stage==:operator && i>1 ? v["Hd_interface"][i-1, t] : v["H_D"][i, t] for i in 1:3, t in 1:T
    ]
    H_net=H_source-H_demand
    if stage!=:local && get(d, "admission_policy", "unrestricted")=="import_only_v1"
        # R4-B2：预先声明仅购能接入；集中/本地/网络三阶段采用同一边界。
        # 该制度不自动保证网络容量足够，仍须冻结计划并独立校核。
        for i in 2:3, t in 1:T
            (active(i) || stage==:operator) || continue
            @constraint(model, P_net[i, t]<=0)
            @constraint(model, H_net[i, t]<=0)
        end
    end
    external=AffExpr(0.0)
    settlement=AffExpr(0.0)
    penalty=AffExpr(0.0)
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
            if get(d, "admission_policy", "unrestricted")=="import_only_v1"
                # 买价严格大于卖价：净购能时同时买卖只会增加成本，故可等价消去卖量。
                # net=-buy与buy>=0已经施加R4-B2，不再重复添加退化的不等式。
                foreach(x->fix(x, 0.0; force = true), sell)
            end
            net=carrier=="P" ? P_net : H_net
            for t in 1:T
                @constraint(model, net[actor, t]==sell[t]-buy[t])
                add_to_expression!(settlement, dt*price[carrier*"_buy"], buy[t])
                add_to_expression!(settlement, -dt*price[carrier*"_sell"], sell[t])
            end
        end
    elseif stage==:agent
        # 资源成本局部问题不含内部支付；合同副本由分布协调接口显式添加。
    elseif stage==:trading
        price=d["settlement"]
        for carrier in ("P", "H")
            buy=@variable(model, [1:3, 1:T], lower_bound=0, base_name=carrier*"_buy")
            sell=@variable(model, [1:3, 1:T], lower_bound=0, base_name=carrier*"_sell")
            qmax=d["p2p_enabled"] ? minimum(actors[i]["retail_limit"] for i in 2:3) : 0.0
            q=@variable(
                model,
                [1:T],
                lower_bound=-qmax,
                upper_bound=qmax,
                base_name=carrier*"_peer"
            )
            qabs=@variable(
                model,
                [1:T],
                lower_bound=0,
                upper_bound=qmax,
                base_name=carrier*"_peer_abs"
            )
            v[carrier*"_buy"]=buy
            v[carrier*"_sell"]=sell
            v[carrier*"_peer"]=q
            v[carrier*"_peer_abs"]=qabs
            net=carrier=="P" ? P_net : H_net
            for t in 1:T
                fix(buy[1, t], 0; force = true)
                fix(sell[1, t], 0; force = true)
                @constraint(model, qabs[t]>=q[t])
                @constraint(model, qabs[t]>=-q[t])
                add_to_expression!(settlement, dt*price["fee"], qabs[t])
                for i in 2:3
                    set_upper_bound(buy[i, t], actors[i]["retail_limit"])
                    set_upper_bound(sell[i, t], actors[i]["retail_limit"])
                    # R4-T1：q>0为A出售给B；内部双边支付抵消，但卖方网络费只收一次。
                    @constraint(model, net[i, t]==sell[i, t]-buy[i, t]+(i==2 ? q[t] : -q[t]))
                    add_to_expression!(settlement, dt*price[carrier*"_buy"], buy[i, t])
                    add_to_expression!(settlement, -dt*price[carrier*"_sell"], sell[i, t])
                end
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
        if switching!==nothing
            resource+=r4_switching_variables!(model, v, c, switching)
        end
        Eon(p, t) = switching===nothing ? 1.0 : v["u_E"][p, t]
        if balance_penalty!==nothing
            scales=r4_tspa_scales(c)
            for carrier in ("P", "Q", "H", "m"), side in ("pos", "neg")
                key="slack_"*carrier*"_"*side
                v[key]=@variable(model, [1:3, 1:T], lower_bound=0, base_name=key)
                for i in 1:3, t in 1:T
                    add_to_expression!(penalty, dt*balance_penalty/scales[carrier], v[key][i, t])
                end
            end
        end
        slack(carrier, i, t) =
            balance_penalty===nothing ? 0.0 :
            v["slack_"*carrier*"_pos"][i, t]-v["slack_"*carrier*"_neg"][i, t]
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
            v[k]=@variable(model, [1:length(edges), 1:T], base_name=k)
        end
        v["ell"]=@variable(model, [1:length(edges), 1:T], lower_bound=0, base_name="ell")
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
                if switching===nothing
                    @constraint(model, v["v"][j, t]==vi-2*(r*P+x*Q)+(r^2+x^2)*ell)
                else
                    # R4-N2：开路时P/Q/ell均零，电压差可取完整边界跨度。
                    for (var, cap) in ((P, edge["P_max"]/base), (Q, edge["Q_max"]/base))
                        @constraint(model, var<=cap*Eon(p, t))
                        @constraint(model, var>=-cap*Eon(p, t))
                    end
                    @constraint(model, ell<=edge["ell_max"]*Eon(p, t))
                    drop=v["v"][j, t]-vi+2*(r*P+x*Q)-(r^2+x^2)*ell
                    M=e["v_max"]^2-e["v_min"]^2
                    @constraint(model, drop<=M*(1-Eon(p, t)))
                    @constraint(model, drop>=-M*(1-Eon(p, t)))
                end
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
                    )==sum(v["P_branch"][p, t] for p in outgoing; init = 0)+slack("P", i, t)/base
                )
                @constraint(
                    model,
                    -Q_load[i, t]/base+(i==1 ? v["Q_grid"][t]/base : 0)+sum(
                        v["Q_branch"][p, t]-edges[p]["x"]*v["ell"][p, t] for p in incoming;
                        init = 0,
                    )==sum(v["Q_branch"][p, t] for p in outgoing; init = 0)+slack("Q", i, t)/base
                )
            end
        end
        h=d["heat"]
        pipes=h["pipes"]
        for k in ("H_in", "H_out", "m_pipe")
            v[k]=@variable(model, [1:length(pipes), 1:T], lower_bound=0, base_name=k)
        end
        for k in ("m_source", "m_load")
            v[k]=@variable(model, [1:3, 1:T], lower_bound=0, base_name=k)
        end
        for t in 1:T
            for (p, pipe) in enumerate(pipes)
                set_upper_bound(v["m_pipe"][p, t], pipe["flow_max"])
                set_upper_bound(v["H_in"][p, t], pipe["H_max"])
                set_upper_bound(v["H_out"][p, t], pipe["H_max"])
                Hon=switching===nothing ? 1.0 : v["u_H_arc"][p, t]
                if switching!==nothing
                    @constraint(model, v["m_pipe"][p, t]<=pipe["flow_max"]*Hon)
                    @constraint(model, v["H_in"][p, t]<=pipe["H_max"]*Hon)
                    @constraint(model, v["H_out"][p, t]<=pipe["H_max"]*Hon)
                end
                if thermal===nothing
                    @constraint(model, v["H_out"][p, t]==v["H_in"][p, t]-r4_loss(pipe)*Hon)
                end
            end
            for i in 1:3
                ms=v["m_source"][i, t]
                ml=v["m_load"][i, t]
                set_upper_bound(ms, actors[i]["port_flow_max"])
                set_upper_bound(ml, actors[i]["port_flow_max"])
                for (m, H, port) in ((ms, H_source[i, t], "source"), (ml, H_demand[i, t], "load"))
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
                    )+slack("m", i, t)
                )
                @constraint(
                    model,
                    H_source[i, t]+sum(v["H_out"][p, t] for p in incoming; init = 0)==H_demand[
                        i,
                        t,
                    ]+sum(v["H_in"][p, t] for p in outgoing; init = 0)+slack("H", i, t)
                )
            end
        end
    end
    thermal===nothing || r4_thermal_constraints!(model, v, c, thermal)
    @objective(model, Min, resource+dissatisfaction+external+settlement+penalty)
    types=string.(list_of_constraint_types(model))
    return (;
        model,
        variables,
        resource,
        dissatisfaction,
        external,
        settlement,
        penalty,
        boundary = (; P_net, Q_load, H_source, H_demand),
        stage,
        actor,
        formula_map = merge(
            Dict(
                "devices"=>"ch04-004:013",
                "electric"=>"ch04-026:033",
                "heat"=>"ch04-041:047",
                "balance"=>"R4-P1:7",
            ),
            thermal===nothing ? Dict{String,String}() : Dict("thermal"=>"R4-T1:T6"),
        ),
        model_types = types,
        model_class = thermal!==nothing && thermal.mass_schedule===nothing ?
                      (
            thermal.spec.loss==:exponential ? "nonconvex_nonlinear" : "nonconvex_quadratic"
        ) :
                      spec.electric==:exact && stage in (:central, :network) ?
                      "nonconvex_quadratic" :
                      any(is_binary, all_variables(model)) ? "MISOCP" : "SOCP",
    )
end
