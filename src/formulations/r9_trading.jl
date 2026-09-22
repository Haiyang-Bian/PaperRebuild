"""
    build_r9_trading_model(case; electric=:socp, stage=:central, actor=0,
        frozen=nothing, modes=nothing, optimizer=nothing)

构造多聚合商调度，不求解、不写文件。旧输入固定拓扑；v2输入按显式网络控制块建模。
stage=:local仅优化指定主体；:network冻结
全部聚合商控制后校核运营商/网络；:central联合优化资源。合同不作为指定支路的潮流。
电网使用原节点编号与标幺平方量，可显式选择原支路等式:exact。
热网允许每时段双向交换；正反两个弧互斥，共用一对管道容量和一次参考供回水损耗。
质量守恒、端口和管道热功率包络同时施加；没有恢复混合温度/水压，不能认证完整热物理。
电池与热储能分别逐时互斥，初末能量相等。设备×时间与主体×时间维度不混用。
modes可固定z_storage与heat_direction矩阵供连续对照；v2还必须给u_E与u_H，不放松整数域。
分布接口新增:agent/:operator，分别保留主体资源或运营商与网络；原三种stage行为不变。
R9-T1—T6与R9-RN1—N5，热阀门整日固定，不限制热流参考方向。
"""
function build_r9_trading_model(
    c::R9TradingCase;
    electric = :socp,
    stage = :central,
    actor = 0,
    frozen = nothing,
    modes = nothing,
    optimizer = nothing,
)
    TOML.parse(c.source_text)==c.data || error("输入被原位改写")
    electric in (:socp, :exact) && stage in (:central, :local, :network, :agent, :operator) ||
        error("模型选择错误")
    d=c.data
    T=d["T"]
    dt=d["dt_h"]
    a, g=d["actors"], d["devices"]
    A, G=length(a), length(g)
    stage in (:local, :agent) && !(actor in 2:A) && error("局部主体编号错误")
    stage==:operator && actor!=1 && error("运营商主体编号错误")
    stage==:network && frozen===nothing && error("网络阶段缺少独立计划")
    active(i) = stage in (:local, :agent) ? i==actor : stage==:operator ? i==1 : true
    model=optimizer===nothing ? Model() : Model(optimizer)
    v=Dict{String,Any}()
    cs=Dict{String,Vector{Any}}()
    add(id, con) = r2_add!(cs, id, con)
    for key in ("P_gen", "P_cons", "H_gen", "H_cons")
        v[key]=@variable(model, [1:G, 1:T], lower_bound=0, base_name=key)
    end
    v["E"]=@variable(model, [1:G, 1:(T+1)], lower_bound=0, base_name="E")
    v["z_storage"]=@variable(model, [1:G, 1:T], lower_bound=0, upper_bound=1, base_name="z_storage")
    function binary_mode(var, key, i, t, enabled)
        if !enabled
            fix(var, 0; force = true)
        elseif modes===nothing
            set_binary(var)
        else
            haskey(modes, key) || error("显式模式缺少$key")
            matrix=modes[key]
            size(matrix)==size(v[key]) && all(x->x in (0, 1), matrix) || error("模式矩阵错误")
            fix(var, matrix[i, t]; force = true)
        end
    end
    resource=AffExpr(0.0)
    discomfort=AffExpr(0.0)
    external=AffExpr(0.0)
    retail=AffExpr(0.0)
    switching=AffExpr(0.0)
    for (j, x) in enumerate(g)
        kind=x["kind"]
        on=active(x["owner"])
        for t in 1:T
            cap=on ? x["availability_MW"][t] : 0.0
            for key in ("P_gen", "P_cons", "H_gen", "H_cons")
                allowed=(key=="P_gen" && kind in ("CHP", "PV", "BS")) ||
                        (key=="P_cons" && kind in ("P2H", "BS")) ||
                        (key=="H_gen" && kind in ("CHP", "P2H", "HS")) ||
                        (key=="H_cons" && kind=="HS")
                upper=key=="H_gen" && kind in ("CHP", "P2H") ? cap*x["heat_ratio"] : cap
                set_upper_bound(v[key][j, t], allowed ? upper : 0.0)
            end
            if kind=="CHP"
                set_lower_bound(v["P_gen"][j, t], on ? x["power_min_MW"] : 0.0)
                add(
                    "R9-T2-CHP",
                    @constraint(model, v["H_gen"][j, t]==x["heat_ratio"]*v["P_gen"][j, t])
                )
            elseif kind=="P2H"
                add(
                    "R9-T2-P2H",
                    @constraint(model, v["H_gen"][j, t]==x["heat_ratio"]*v["P_cons"][j, t])
                )
            end
            store=kind in ("BS", "HS") && on
            binary_mode(v["z_storage"][j, t], "z_storage", j, t, store)
            if store
                ch, dis=kind=="BS" ? (v["P_cons"][j, t], v["P_gen"][j, t]) :
                        (v["H_cons"][j, t], v["H_gen"][j, t])
                add(
                    "R9-T3-state",
                    @constraint(
                        model,
                        v["E"][j, t+1]==(1-x["loss_per_h"])^dt*v["E"][j, t]+dt*(
                            x["eta_ch"]*ch-dis/x["eta_dis"]
                        )
                    )
                )
                add("R9-T3-exclusive", @constraint(model, ch<=cap*v["z_storage"][j, t]))
                add("R9-T3-exclusive", @constraint(model, dis<=cap*(1-v["z_storage"][j, t])))
                add_to_expression!(resource, dt*x["cost_CNY_MWh"], ch)
                add_to_expression!(resource, dt*x["cost_CNY_MWh"], dis)
            elseif kind in ("CHP", "PV")
                add_to_expression!(resource, dt*x["cost_CNY_MWh"], v["P_gen"][j, t])
            end
        end
        for t in 1:(T+1)
            set_upper_bound(v["E"][j, t], on ? x["energy_max_MWh"] : 0.0)
        end
        add("R9-T3-boundary", @constraint(model, v["E"][j, 1]==(on ? x["initial_MWh"] : 0.0)))
        add("R9-T3-boundary", @constraint(model, v["E"][j, T+1]==(on ? x["initial_MWh"] : 0.0)))
    end
    for key in ("P_D", "H_D", "w_P", "w_H")
        v[key]=@variable(model, [1:A, 1:T], lower_bound=0, base_name=key)
    end
    for (i, x) in enumerate(a), t in 1:T, carrier in ("P", "H")
        ref=active(i) ? x[carrier*"_load"][t] : 0.0
        var=v[carrier*"_D"][i, t]
        set_lower_bound(var, (1-x["flex"])*ref)
        set_upper_bound(var, (1+x["flex"])*ref)
        w=v["w_"*carrier][i, t]
        if active(i) && x["sat_"*carrier]>0
            preferred=x[carrier*"_preferred"][t]
            scale=sqrt(x["sat_"*carrier])
            add(
                "R9-T2-preference",
                @constraint(model, [w, 0.5, scale*(preferred-var)] in RotatedSecondOrderCone())
            )
            add_to_expression!(discomfort, dt, w)
        else
            fix(w, 0; force = true)
        end
    end
    P_actor=@expression(
        model,
        [i=1:A, t=1:T],
        sum(v["P_gen"][j, t]-v["P_cons"][j, t] for j in 1:G if g[j]["owner"]==i; init = 0)-v["P_D"][
            i,
            t,
        ]
    )
    H_actor=@expression(
        model,
        [i=1:A, t=1:T],
        sum(v["H_gen"][j, t]-v["H_cons"][j, t] for j in 1:G if g[j]["owner"]==i; init = 0)-v["H_D"][
            i,
            t,
        ]
    )
    if stage==:operator
        contract=r9_boundary_contract(c)
        v["boundary"]=@variable(model, [1:4(A-1), 1:T], base_name="boundary")
        for k in axes(v["boundary"], 1), t in 1:T
            # R9-DC1：有限盒只取原参数的必要界，不把上轮AG调度固定进运营商块。
            set_lower_bound(v["boundary"][k, t], contract.lower[k, t])
            set_upper_bound(v["boundary"][k, t], contract.upper[k, t])
        end
        boundary=v["boundary"]
    else
        boundary=r9_trading_message_expressions(c, v)
    end
    if stage==:local
        for carrier in ("P", "H"), side in ("buy", "sell")
            key=carrier*"_"*side
            v[key]=@variable(
                model,
                [1:T],
                lower_bound=0,
                upper_bound=a[actor]["retail_limit_MW"],
                base_name=key
            )
            for t in 1:T
                add_to_expression!(
                    retail,
                    dt*d["settlement"][key][t]*(side=="buy" ? 1 : -1),
                    v[key][t],
                )
            end
        end
        for t in 1:T, (carrier, net) in (("P", P_actor), ("H", H_actor))
            add(
                "R9-T6-retail",
                @constraint(model, net[actor, t]+v[carrier*"_buy"][t]-v[carrier*"_sell"][t]==0)
            )
        end
    elseif stage!=:agent
        if stage==:network
            length(frozen)==A-1 && Set(r["actor"] for r in frozen)==Set(2:A) ||
                error("独立计划不完整")
            for r in frozen
                r["input_sha256"]==c.sha256 && r["stage"]=="local" && haskey(r, "values") ||
                    error("独立计划身份错误")
                i=r["actor"]
                s=r["values"]
                for key in ("P_D", "H_D"), t in 1:T
                    add("R9-T6-frozen", @constraint(model, v[key][i, t]==s[key][i][t]))
                end
                # 加等式保留原边界，不用force固定删除原始容量约束。
                for j in 1:G
                    g[j]["owner"]==i || continue
                    for key in ("P_gen", "P_cons", "H_gen", "H_cons", "E", "z_storage"),
                        t in axes(v[key], 2)

                        add("R9-T6-frozen", @constraint(model, v[key][j, t]==s[key][j][t]))
                    end
                end
            end
        end
        e, h=d["electric"], d["heat"]
        n, k, base=e["nodes"], h["nodes"], e["base_MVA"]
        edges, pipes=e["edges"], h["pipes"]
        L, R=length(edges), length(pipes)
        network=haskey(d, "network_control")
        network && (switching=r9_network_variables!(model, v, cs, c, modes))
        v["P_grid"]=@variable(
            model,
            [1:T],
            lower_bound=0,
            upper_bound=e["grid_max_MW"],
            base_name="P_grid"
        )
        v["Q_grid"]=@variable(
            model,
            [1:T],
            lower_bound=-e["grid_Q_max_Mvar"],
            upper_bound=e["grid_Q_max_Mvar"],
            base_name="Q_grid"
        )
        v["v"]=@variable(
            model,
            [1:n, 1:T],
            lower_bound=e["v_min_pu"]^2,
            upper_bound=e["v_max_pu"]^2,
            base_name="v"
        )
        v["ell"]=@variable(model, [1:L, 1:T], lower_bound=0, base_name="ell")
        for key in ("P_branch", "Q_branch")
            v[key]=@variable(model, [1:L, 1:T], base_name=key)
        end
        for t in 1:T
            fix(v["v"][e["root"], t], 1; force = true)
            add_to_expression!(external, dt*d["grid_price"][t], v["P_grid"][t])
            for (j, line) in enumerate(edges)
                i, o=line["from"], line["to"]
                P, Q, l, vi=v["P_branch"][j, t], v["Q_branch"][j, t], v["ell"][j, t], v["v"][i, t]
                r, x=line["r_pu"], line["x_pu"]
                for (var, cap) in ((P, line["P_max_MW"]/base), (Q, line["Q_max_Mvar"]/base))
                    set_lower_bound(var, -cap)
                    set_upper_bound(var, cap)
                end
                set_upper_bound(l, line["ell_max_pu"])
                if network
                    u=v["u_E"][j, t]
                    for (var, cap) in ((P, line["P_max_MW"]/base), (Q, line["Q_max_Mvar"]/base))
                        add("R9-RN2", @constraint(model, var<=cap*u))
                        add("R9-RN2", @constraint(model, var>=-cap*u))
                    end
                    add("R9-RN2", @constraint(model, l<=line["ell_max_pu"]*u))
                    # 开路使P/Q/ell=0，平方电压跨度就是足够且可推导的M。
                    drop=v["v"][o, t]-vi+2(r*P+x*Q)-(r^2+x^2)*l
                    M=e["v_max_pu"]^2-e["v_min_pu"]^2
                    add("R9-RN2", @constraint(model, drop<=M*(1-u)))
                    add("R9-RN2", @constraint(model, drop>=-M*(1-u)))
                else
                    add("ch04-032", @constraint(model, v["v"][o, t]==vi-2(r*P+x*Q)+(r^2+x^2)*l))
                end
                if electric==:socp
                    add("ch04-033", @constraint(model, [vi+l, 2P, 2Q, vi-l] in SecondOrderCone()))
                else
                    add("R9-T4-original-grid", @constraint(model, vi*l==P^2+Q^2))
                end
            end
            for i in 1:n
                pinj=sum(
                    v["P_gen"][j, t]-v["P_cons"][j, t] for j in 1:G if g[j]["electric_node"]==i;
                    init = AffExpr(0.0),
                )-sum(v["P_D"][j, t] for j in 2:A if a[j]["electric_node"]==i; init = 0)-e["P_background_MW"][i][t]
                qload=e["Q_background_Mvar"][i][t]+sum(
                    a[j]["Q_ratio"]*v["P_D"][j, t] for j in 2:A if a[j]["electric_node"]==i;
                    init = 0,
                )
                if stage==:operator
                    pinj+=sum(boundary[4j-7, t] for j in 2:A if a[j]["electric_node"]==i; init = 0)
                    qload+=sum(boundary[4j-6, t] for j in 2:A if a[j]["electric_node"]==i; init = 0)
                end
                for (key, net, grid, loss) in
                    (("P", pinj, v["P_grid"], "r_pu"), ("Q", -qload, v["Q_grid"], "x_pu"))
                    branches=v[key*"_branch"]
                    add(
                        "ch04-030:031",
                        @constraint(
                            model,
                            (net+(i==e["root"] ? grid[t] : 0))/base+sum(
                                branches[j, t]-edges[j][loss]*v["ell"][j, t] for
                                j in 1:L if edges[j]["to"]==i;
                                init = 0,
                            )==sum(branches[j, t] for j in 1:L if edges[j]["from"]==i; init = 0)
                        )
                    )
                end
            end
        end
        for key in ("H_plus_in", "H_plus_out", "H_minus_in", "H_minus_out", "m_plus", "m_minus")
            v[key]=@variable(model, [1:R, 1:T], lower_bound=0, base_name=key)
        end
        v["heat_direction"]=@variable(
            model,
            [1:R, 1:T],
            lower_bound=0,
            upper_bound=1,
            base_name="heat_direction"
        )
        for key in ("m_source", "m_load")
            v[key]=@variable(model, [1:k, 1:T], lower_bound=0, base_name=key)
        end
        cp=h["cp_J_kgK"]/1e6
        low=cp*h["delta_min_K"]
        high=cp*h["delta_max_K"]
        for t in 1:T
            for (j, pipe) in enumerate(pipes)
                z=v["heat_direction"][j, t]
                binary_mode(z, "heat_direction", j, t, true)
                open=network ? v["u_H"][j, 1] : 1
                network && add("R9-RN4", @constraint(model, z<=open))
                # 正反向共用管对，损耗只施加于实际方向；不用双弧同时开放制造虚假循环。
                for (side, on) in (("plus", z), ("minus", open-z))
                    hi, ho, m=v["H_"*side*"_in"][j, t],
                    v["H_"*side*"_out"][j, t],
                    v["m_"*side][j, t]
                    set_upper_bound(m, pipe["flow_max_kg_s"])
                    add("R9-T5-direction", @constraint(model, m<=pipe["flow_max_kg_s"]*on))
                    for H in (hi, ho)
                        set_upper_bound(H, pipe["H_max_MW"])
                        add("R9-T5-direction", @constraint(model, H<=pipe["H_max_MW"]*on))
                        add("R9-T5-envelope", @constraint(model, H>=low*m))
                        add("R9-T5-envelope", @constraint(model, H<=high*m))
                    end
                    add("R9-T5-loss", @constraint(model, ho==hi-pipe["loss_MW"]*on))
                end
            end
            for i in 1:k
                src=sum(v["H_gen"][j, t] for j in 1:G if g[j]["heat_node"]==i; init = AffExpr(0.0))
                dem=h["H_background_MW"][i][t]+sum(
                    v["H_D"][j, t] for j in 2:A if a[j]["heat_node"]==i;
                    init = 0,
                )+sum(v["H_cons"][j, t] for j in 1:G if g[j]["heat_node"]==i; init = 0)
                if stage==:operator
                    src+=sum(boundary[4j-5, t] for j in 2:A if a[j]["heat_node"]==i; init = 0)
                    dem+=sum(boundary[4j-4, t] for j in 2:A if a[j]["heat_node"]==i; init = 0)
                end
                cap_src=sum(
                    g[j]["kind"] in ("CHP", "P2H") ? g[j]["power_max_MW"]*g[j]["heat_ratio"] :
                    g[j]["kind"]=="HS" ? g[j]["power_max_MW"] : 0.0 for
                    j in 1:G if g[j]["heat_node"]==i;
                    init = 0.0,
                )
                cap_dem=maximum(h["H_background_MW"][i])+sum(
                    (1+a[j]["flex"])*maximum(a[j]["H_load"]) for j in 2:A if a[j]["heat_node"]==i;
                    init = 0.0,
                )+sum(
                    g[j]["power_max_MW"] for j in 1:G if g[j]["heat_node"]==i && g[j]["kind"]=="HS";
                    init = 0.0,
                )
                for (mass, H, cap) in
                    ((v["m_source"][i, t], src, cap_src), (v["m_load"][i, t], dem, cap_dem))
                    set_upper_bound(mass, cap/low)
                    add("R9-T5-port", @constraint(model, H>=low*mass))
                    add("R9-T5-port", @constraint(model, H<=high*mass))
                end
                hin=sum(
                    v["H_plus_out"][j, t]-v["H_minus_in"][j, t] for j in 1:R if pipes[j]["to"]==i;
                    init = 0,
                )
                hout=sum(
                    v["H_plus_in"][j, t]-v["H_minus_out"][j, t] for j in 1:R if pipes[j]["from"]==i;
                    init = 0,
                )
                mi=sum(
                    v["m_plus"][j, t]-v["m_minus"][j, t] for j in 1:R if pipes[j]["to"]==i;
                    init = 0,
                )
                mo=sum(
                    v["m_plus"][j, t]-v["m_minus"][j, t] for j in 1:R if pipes[j]["from"]==i;
                    init = 0,
                )
                add("R9-T5-heat-balance", @constraint(model, src+hin==dem+hout))
                add(
                    "R9-T5-mass-balance",
                    @constraint(model, v["m_source"][i, t]+mi==v["m_load"][i, t]+mo)
                )
            end
        end
    end
    @objective(model, Min, resource+discomfort+external+retail+switching)
    return (;
        model,
        variables = v,
        constraints = cs,
        resource,
        discomfort,
        external,
        retail,
        switching,
        boundary,
        objective_kind = stage==:local ? "local_resource_plus_retail" :
                         stage==:agent ? "agent_resource_cost" :
                         stage==:operator ? "operator_resource_cost" : "system_resource_cost",
        model_class = electric==:exact && stage in (:central, :network, :operator) ?
                      (any(is_binary, all_variables(model)) ? "nonconvex_MIQCP" : "nonconvex_QCP") :
                      r2_model_class(model),
        model_types = string.(list_of_constraint_types(model)),
        stage,
        actor,
        electric,
        heat_scope = "steady_energy_mass_envelope",
        full_thermal_physics_certified = false,
    )
end
