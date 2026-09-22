# 仅读取数值；与JuMP约束构造分开，用于独立成本/现金流和逐式回代。
function r9_trading_costs(c, s; actor = 0)
    d=c.data
    a=d["actors"]
    G=d["devices"]
    T=d["T"]
    dt=d["dt_h"]
    resource=zeros(length(a))
    discomfort=zeros(length(a))
    for (j, g) in enumerate(G), t in 1:T
        actor>0 && g["owner"]!=actor && continue
        q=g["kind"] in ("CHP", "PV") ? s["P_gen"][j][t] :
          g["kind"]=="BS" ? s["P_gen"][j][t]+s["P_cons"][j][t] :
          g["kind"]=="HS" ? s["H_gen"][j][t]+s["H_cons"][j][t] : 0.0
        resource[g["owner"]]+=dt*g["cost_CNY_MWh"]*q
    end
    for i in eachindex(a), t in 1:T, carrier in ("P", "H")
        actor>0 && i!=actor && continue
        discomfort[i]+=dt*a[i]["sat_"*carrier]*(
            a[i][carrier*"_preferred"][t]-s[carrier*"_D"][i][t]
        )^2
    end
    external=actor==0 && haskey(s, "P_grid") ? dt*sum(d["grid_price"] .* s["P_grid"]) : 0.0
    actor==0 && (resource[1]+=r9_switching_cost(c, s))
    (; resource, discomfort, external, total = sum(resource)+sum(discomfort)+external)
end

"""
    r9_trading_ledger(case, values; p2p=true, settlement=case.data["settlement"])

独立计算九主体资源成本及示例结算（R9-T6）。按主体ID依次匹配净余缺，MW乘Δt转MWh；
P2P服务费每笔只由卖方支付运营商一次，零售/P2P/服务费均保存双边现金流。
结算不反向改变物理调度；未提供原文总效用常数，输出成本与示例净收益，不冒称议价或公平。
仅用于完整网络计划；内部现金和为零，总示例效用和为负系统资源成本。
"""
function r9_trading_ledger(c::R9TradingCase, s; p2p = true, settlement = c.data["settlement"])
    d=c.data
    a=d["actors"]
    g=d["devices"]
    T=d["T"]
    A=length(a)
    dt=d["dt_h"]
    for key in ("P_buy", "P_sell", "H_buy", "H_sell", "P_peer", "H_peer", "fee")
        length(settlement[key])==T && all(x->isfinite(x)&&x>=0, settlement[key]) ||
            error("替代结算价格非法")
    end
    costs=r9_trading_costs(c, s)
    cash=zeros(A)
    payments=Dict{String,Any}[]
    contracts=Dict{String,Any}[]
    order=sort(collect(2:A); by = i->a[i]["id"])
    function pay(from, to, kind, carrier, t, q, price)
        q>=0 && isfinite(q) || error("现金流数量错误")
        q==0 && return
        amount=q*dt*price
        cash[from]-=amount
        cash[to]+=amount
        push!(
            payments,
            Dict(
                "from"=>a[from]["id"],
                "to"=>a[to]["id"],
                "kind"=>kind,
                "carrier"=>carrier,
                "t"=>t,
                "quantity_MWh"=>q*dt,
                "price_CNY_MWh"=>price,
                "amount_CNY"=>amount,
            ),
        )
    end
    for carrier in ("P", "H"), t in 1:T
        net=[
            sum(
                s[carrier*"_gen"][j][t]-s[carrier*"_cons"][j][t] for
                j in eachindex(g) if g[j]["owner"]==i;
                init = 0.0,
            )-s[carrier*"_D"][i][t] for i in 1:A
        ]
        remaining=copy(net)
        if p2p
            for seller in order, buyer in order
                seller==buyer && continue
                remaining[seller]>0 && remaining[buyer]<0 || continue
                q=min(remaining[seller], -remaining[buyer])
                remaining[seller]-=q
                remaining[buyer]+=q
                pay(buyer, seller, "p2p", carrier, t, q, settlement[carrier*"_peer"][t])
                pay(seller, 1, "service", carrier, t, q, settlement["fee"][t])
            end
        end
        for i in order
            buy=max(0.0, -remaining[i])
            sell=max(0.0, remaining[i])
            pay(i, 1, "retail_buy", carrier, t, buy, settlement[carrier*"_buy"][t])
            pay(1, i, "retail_sell", carrier, t, sell, settlement[carrier*"_sell"][t])
            push!(
                contracts,
                Dict(
                    "actor"=>a[i]["id"],
                    "carrier"=>carrier,
                    "t"=>t,
                    "net_MW"=>net[i],
                    "peer_export_MW"=>net[i]-remaining[i],
                    "retail_buy_MW"=>buy,
                    "retail_sell_MW"=>sell,
                ),
            )
        end
    end
    rows=[
        Dict(
            "actor"=>a[i]["id"],
            "resource_CNY"=>costs.resource[i],
            "discomfort_CNY"=>costs.discomfort[i],
            "external_CNY"=>i==1 ? costs.external : 0.0,
            "internal_cash_CNY"=>cash[i],
            "accounting_payoff_CNY"=>cash[i]-costs.resource[i]-costs.discomfort[i]-(
                i==1 ? costs.external : 0.0
            ),
        ) for i in 1:A
    ]
    Dict(
        "actors"=>rows,
        "payments"=>payments,
        "contracts"=>contracts,
        "system_cost_CNY"=>costs.total,
        "cash_balance_CNY"=>sum(cash),
        "payoff_identity_CNY"=>sum(x["accounting_payoff_CNY"] for x in rows)+costs.total,
        "p2p"=>p2p,
        "settlement"=>settlement,
        "bargaining"=>"not_performed",
        "gross_benefit_constant"=>"not_assumed",
    )
end

"""
    validate_r9_trading_solution(case, result)

从保存数值逐式检查设备/储能/负荷、双向管道、节点质量和热量、电压/电流平方及费用。
不调用JuMP或优化器。共用热节点先求和，源荷端口保持非负且分开。
模型、电网原支路等式、热能量/质量包络与账本分别报告；完整温度/水力始终未认证。
局部自调度只检查其声明主体；网络阶段必须回对完整冻结控制，不以重新调度替代AG0。
沿用A1，尺度仅来自输入；原电网等式失败不被SOCP通过覆盖。
"""
function validate_r9_trading_solution(c::R9TradingCase, r)
    TOML.parse(c.source_text)==c.data && r["input_sha256"]==c.sha256 || error("输入身份改变")
    d=c.data
    T=d["T"]
    dt=d["dt_h"]
    a=d["actors"]
    g=d["devices"]
    e=d["electric"]
    h=d["heat"]
    A, G, N, K=length(a), length(g), e["nodes"], h["nodes"]
    rows=Dict{String,Any}[]
    fail=Dict{String,Any}(
        "model_pass"=>false,
        "electric_original_pass"=>false,
        "heat_energy_mass_pass"=>false,
        "ledger_pass"=>false,
        "full_thermal_physics_certified"=>false,
        "rows"=>rows,
    )
    haskey(r, "values") || return fail
    r["stage"] in ("central", "local", "network") && r["electric"] in ("socp", "exact") ||
        error("运行模型身份错误")
    r["operation"] in ("central", "independent") || error("运行方式错误")
    isfinite(r["solver_objective"]) || error("费用数值非有限")
    localonly=r["stage"]=="local"
    actor=localonly ? r["actor"] : 0
    localonly && !(actor in 2:A) && error("局部主体错误")
    active(i) = !localonly || i==actor
    s=r["values"]
    V(key, i, t) = s[key][i][t]
    shapes=Dict(key=>(G, T) for key in ("P_gen", "P_cons", "H_gen", "H_cons", "z_storage"))
    shapes["E"]=(G, T+1)
    for key in ("P_D", "H_D", "w_P", "w_H")
        shapes[key]=(A, T)
    end
    if !localonly
        for key in ("P_branch", "Q_branch", "ell")
            shapes[key]=(length(e["edges"]), T)
        end
        shapes["v"]=(N, T)
        for key in (
            "H_plus_in",
            "H_plus_out",
            "H_minus_in",
            "H_minus_out",
            "m_plus",
            "m_minus",
            "heat_direction",
        )
            shapes[key]=(length(h["pipes"]), T)
        end
        for key in ("m_source", "m_load")
            shapes[key]=(K, T)
        end
    end
    for (key, (n, nt)) in shapes
        haskey(s, key) && length(s[key])==n && all(x->length(x)==nt && all(isfinite, x), s[key]) ||
            error("数值维度或有限性错误：$key")
    end
    for key in (localonly ? ("P_buy", "P_sell", "H_buy", "H_sell") : ("P_grid", "Q_grid"))
        haskey(s, key) && length(s[key])==T && all(isfinite, s[key]) || error("边界数值错误")
    end
    ptol=1e-6*(1+e["grid_max_MW"])
    etol=1e-6*(1+maximum(x["energy_max_MWh"] for x in g; init = 0.0))
    mtol=1e-6*(1+maximum(x["flow_max_kg_s"] for x in h["pipes"]; init = 0.0))
    function row(id, scope, i, t, value, unit, tol)
        residual=abs(Float64(value))
        push!(
            rows,
            Dict(
                "equation"=>id,
                "scope"=>scope,
                "entity"=>string(i),
                "t"=>t,
                "residual"=>residual,
                "unit"=>unit,
                "tolerance"=>tol,
                "pass"=>isfinite(residual)&&residual<=tol,
            ),
        )
    end
    bound(id, i, t, x, lo, hi, unit, tol) = row(id, "model", i, t, max(0.0, lo-x, x-hi), unit, tol)
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
                upper=allowed ?
                      (key=="H_gen" && kind in ("CHP", "P2H") ? cap*x["heat_ratio"] : cap) : 0.0
                lo=on && key=="P_gen" && kind=="CHP" ? x["power_min_MW"] : 0.0
                bound("R9-T2-"*key, j, t, V(key, j, t), lo, upper, "MW", ptol)
            end
            if kind in ("CHP", "P2H")
                row(
                    "R9-T2-conversion",
                    "model",
                    j,
                    t,
                    V("H_gen", j, t)-x["heat_ratio"]*V(kind=="CHP" ? "P_gen" : "P_cons", j, t),
                    "MW",
                    ptol,
                )
            end
            z=V("z_storage", j, t)
            if kind in ("BS", "HS") && on
                ch=V(kind=="BS" ? "P_cons" : "H_cons", j, t)
                dis=V(kind=="BS" ? "P_gen" : "H_gen", j, t)
                bound("R9-T3-z", j, t, z, 0, 1, "1", 1e-6)
                row("R9-T3-integer", "model", j, t, z-round(z), "1", 1e-6)
                row("R9-T3-exclusive", "model", j, t, max(0, ch-cap*z, dis-cap*(1-z)), "MW", ptol)
                row(
                    "R9-T3-state",
                    "model",
                    j,
                    t,
                    V("E", j, t+1)-(1-x["loss_per_h"])^dt*V("E", j, t)-dt*(
                        x["eta_ch"]*ch-dis/x["eta_dis"]
                    ),
                    "MWh",
                    etol,
                )
            else
                row("R9-T3-inactive", "model", j, t, z, "1", 1e-6)
            end
        end
        for t in 1:(T+1)
            bound(
                "R9-T3-energy",
                j,
                t,
                V("E", j, t),
                0,
                on ? x["energy_max_MWh"] : 0.0,
                "MWh",
                etol,
            )
        end
        for t in (1, T+1)
            row(
                "R9-T3-boundary",
                "model",
                j,
                t,
                V("E", j, t)-(on ? x["initial_MWh"] : 0.0),
                "MWh",
                etol,
            )
        end
    end
    for (i, x) in enumerate(a), t in 1:T, carrier in ("P", "H")
        D=V(carrier*"_D", i, t)
        ref=active(i) ? x[carrier*"_load"][t] : 0.0
        bound("R9-T2-demand-"*carrier, i, t, D, (1-x["flex"])*ref, (1+x["flex"])*ref, "MW", ptol)
        w=V("w_"*carrier, i, t)
        sat=x["sat_"*carrier]
        if active(i) && sat>0
            normalized=max(0.0, (x[carrier*"_preferred"][t]-D)^2-w/sat)/max(
                1.0,
                maximum(x[carrier*"_preferred"])^2,
            )
            row("R9-T2-preference", "model", i, t, normalized, "1", 1e-6)
        else
            row("R9-T2-inactive-preference", "model", i, t, w, "CNY/h", 1e-6)
        end
        row("R9-T2-nonnegative-preference", "model", i, t, max(0.0, -w), "CNY/h", 1e-6)
    end
    costs=r9_trading_costs(c, s; actor)
    expected=costs.total
    if localonly
        for carrier in ("P", "H"), t in 1:T
            net=sum(
                V(carrier*"_gen", j, t)-V(carrier*"_cons", j, t) for
                j in 1:G if g[j]["owner"]==actor;
                init = 0.0,
            )-V(carrier*"_D", actor, t)
            for side in ("buy", "sell")
                key=carrier*"_"*side
                q=s[key][t]
                bound("R9-T6-retail-bound", actor, t, q, 0, a[actor]["retail_limit_MW"], "MW", ptol)
                expected+=dt*d["settlement"][key][t]*q*(side=="buy" ? 1 : -1)
            end
            row(
                "R9-T6-retail",
                "model",
                actor,
                t,
                net+s[carrier*"_buy"][t]-s[carrier*"_sell"][t],
                "MW",
                ptol,
            )
        end
    else
        edges, pipes=e["edges"], h["pipes"]
        network=haskey(d, "network_control")
        network && append!(rows, validate_r9_network(c, s)["rows"])
        base=e["base_MVA"]
        cp=h["cp_J_kgK"]/1e6
        for t in 1:T
            bound("R9-T4-P-grid", 0, t, s["P_grid"][t], 0, e["grid_max_MW"], "MW", ptol)
            bound(
                "R9-T4-Q-grid",
                0,
                t,
                s["Q_grid"][t],
                -e["grid_Q_max_Mvar"],
                e["grid_Q_max_Mvar"],
                "Mvar",
                ptol,
            )
            row("R9-T4-root", "model", e["root"], t, V("v", e["root"], t)-1, "1", 1e-6)
            for (j, line) in enumerate(edges)
                i, o=line["from"], line["to"]
                P=V("P_branch", j, t)
                Q=V("Q_branch", j, t)
                l=V("ell", j, t)
                vi=V("v", i, t)
                rr=line["r_pu"]
                xx=line["x_pu"]
                open=network ? V("u_E", j, t) : 1.0
                for (key, q, cap) in
                    (("P", P, line["P_max_MW"]/base), ("Q", Q, line["Q_max_Mvar"]/base))
                    bound("R9-T4-"*key, j, t, q, -cap*open, cap*open, "pu", 1e-6)
                end
                bound("R9-T4-ell", j, t, l, 0, line["ell_max_pu"]*open, "pu²", 1e-6)
                drop=V("v", o, t)-vi+2(rr*P+xx*Q)-(rr^2+xx^2)*l
                M=e["v_max_pu"]^2-e["v_min_pu"]^2
                row(
                    "ch04-032",
                    "model",
                    j,
                    t,
                    network ? max(0.0, abs(drop)-M*(1-open)) : drop,
                    "pu²",
                    1e-6,
                )
                gap=vi*l-P^2-Q^2
                row(
                    "R9-T4-grid",
                    "model",
                    j,
                    t,
                    r["electric"]=="exact" ? gap : min(0.0, gap),
                    "pu²",
                    1e-6,
                )
                row("R9-T4-original-grid", "electric_original", j, t, gap, "pu²", 1e-6)
            end
            for i in 1:N
                bound(
                    "R9-T4-voltage",
                    i,
                    t,
                    V("v", i, t),
                    e["v_min_pu"]^2,
                    e["v_max_pu"]^2,
                    "pu²",
                    1e-6,
                )
                P=sum(
                    V("P_gen", j, t)-V("P_cons", j, t) for j in 1:G if g[j]["electric_node"]==i;
                    init = 0.0,
                )-sum(V("P_D", j, t) for j in 2:A if a[j]["electric_node"]==i; init = 0.0)-e["P_background_MW"][i][t]
                Q=-e["Q_background_Mvar"][i][t]-sum(
                    a[j]["Q_ratio"]*V("P_D", j, t) for j in 2:A if a[j]["electric_node"]==i;
                    init = 0.0,
                )
                for (key, net, loss) in (("P", P, "r_pu"), ("Q", Q, "x_pu"))
                    residual=net+(i==e["root"] ? s[key*"_grid"][t] : 0.0)
                    residual+=base*sum(
                        V(key*"_branch", j, t)-line[loss]*V("ell", j, t) for
                        (j, line) in enumerate(edges) if line["to"]==i;
                        init = 0.0,
                    )
                    residual-=base*sum(
                        V(key*"_branch", j, t) for (j, line) in enumerate(edges) if line["from"]==i;
                        init = 0.0,
                    )
                    row(
                        "ch04-030:031-"*key,
                        "model",
                        i,
                        t,
                        residual,
                        key=="P" ? "MW" : "Mvar",
                        ptol,
                    )
                end
            end
            for (j, pipe) in enumerate(pipes)
                z=V("heat_direction", j, t)
                open=network ? V("u_H", j, 1) : 1.0
                bound("R9-T5-direction", j, t, z, 0, open, "1", 1e-6)
                row("R9-T5-integer", "model", j, t, z-round(z), "1", 1e-6)
                for (side, on) in (("plus", z), ("minus", open-z))
                    m=V("m_"*side, j, t)
                    hi=V("H_"*side*"_in", j, t)
                    ho=V("H_"*side*"_out", j, t)
                    bound("R9-T5-m-"*side, j, t, m, 0, pipe["flow_max_kg_s"]*on, "kg/s", mtol)
                    for (label, H) in (("in", hi), ("out", ho))
                        bound("R9-T5-H-"*side*label, j, t, H, 0, pipe["H_max_MW"]*on, "MW", ptol)
                        bound(
                            "R9-T5-envelope",
                            j,
                            t,
                            H,
                            cp*h["delta_min_K"]*m,
                            cp*h["delta_max_K"]*m,
                            "MW",
                            ptol,
                        )
                    end
                    row("R9-T5-loss", "model", j, t, ho-hi+r4_loss(pipe)*on, "MW", ptol)
                end
            end
            for i in 1:K
                src=sum(V("H_gen", j, t) for j in 1:G if g[j]["heat_node"]==i; init = 0.0)
                dem=h["H_background_MW"][i][t]+sum(
                    V("H_D", j, t) for j in 2:A if a[j]["heat_node"]==i;
                    init = 0.0,
                )+sum(V("H_cons", j, t) for j in 1:G if g[j]["heat_node"]==i; init = 0.0)
                ms, ml=V("m_source", i, t), V("m_load", i, t)
                cap_src=sum(
                    x["kind"] in ("CHP", "P2H") ? x["power_max_MW"]*x["heat_ratio"] :
                    x["kind"]=="HS" ? x["power_max_MW"] : 0.0 for x in g if x["heat_node"]==i;
                    init = 0.0,
                )
                cap_dem=maximum(h["H_background_MW"][i])+sum(
                    (1+x["flex"])*maximum(x["H_load"]) for x in a[2:end] if x["heat_node"]==i;
                    init = 0.0,
                )+sum(
                    x["power_max_MW"] for x in g if x["heat_node"]==i && x["kind"]=="HS";
                    init = 0.0,
                )
                bound(
                    "R9-T5-source-capacity",
                    i,
                    t,
                    ms,
                    0,
                    cap_src/(cp*h["delta_min_K"]),
                    "kg/s",
                    mtol,
                )
                bound(
                    "R9-T5-load-capacity",
                    i,
                    t,
                    ml,
                    0,
                    cap_dem/(cp*h["delta_min_K"]),
                    "kg/s",
                    mtol,
                )
                for (name, m, H) in (("source", ms, src), ("load", ml, dem))
                    row("R9-T5-nonnegative-port", "model", i, t, max(0.0, -m), "kg/s", mtol)
                    bound(
                        "R9-T5-port-"*name,
                        i,
                        t,
                        H,
                        cp*h["delta_min_K"]*m,
                        cp*h["delta_max_K"]*m,
                        "MW",
                        ptol,
                    )
                end
                hres=src-dem
                mres=ms-ml
                for (j, pipe) in enumerate(pipes)
                    if pipe["to"]==i
                        hres+=V("H_plus_out", j, t)-V("H_minus_in", j, t)
                        mres+=V("m_plus", j, t)-V("m_minus", j, t)
                    elseif pipe["from"]==i
                        hres-=V("H_plus_in", j, t)-V("H_minus_out", j, t)
                        mres-=V("m_plus", j, t)-V("m_minus", j, t)
                    end
                end
                row("R9-T5-heat-balance", "model", i, t, hres, "MW", ptol)
                row("R9-T5-mass-balance", "model", i, t, mres, "kg/s", mtol)
            end
        end
        if r["stage"]=="network"
            plans=r["frozen_plans"]
            length(plans)==A-1 && Set(x["actor"] for x in plans)==Set(2:A) || error("冻结计划丢失")
            for plan in plans
                plan["input_sha256"]==c.sha256 || error("冻结计划来源改变")
                i=plan["actor"]
                for key in ("P_D", "H_D"), t in 1:T
                    row(
                        "R9-T6-frozen-"*key,
                        "model",
                        i,
                        t,
                        V(key, i, t)-plan["values"][key][i][t],
                        "MW",
                        ptol,
                    )
                end
                for j in 1:G
                    g[j]["owner"]==i || continue
                    for key in ("P_gen", "P_cons", "H_gen", "H_cons", "E", "z_storage"),
                        t in eachindex(s[key][j])

                        unit, tol=key=="E" ? ("MWh", etol) :
                                  key=="z_storage" ? ("1", 1e-6) : ("MW", ptol)
                        row(
                            "R9-T6-frozen-"*key,
                            "model",
                            j,
                            t,
                            V(key, j, t)-plan["values"][key][j][t],
                            unit,
                            tol,
                        )
                    end
                end
            end
        end
    end
    ctol=1e-6*max(1.0, abs(expected))
    row("R9-T6-objective", "model", "total", 0, r["solver_objective"]-expected, "CNY", ctol)
    ledger=nothing
    if !localonly
        ledger=r9_trading_ledger(c, s; p2p = r["operation"]!="independent")
        row("R9-T6-cash", "ledger", "all", 0, ledger["cash_balance_CNY"], "CNY", ctol)
        row("R9-T6-payoff", "ledger", "all", 0, ledger["payoff_identity_CNY"], "CNY", ctol)
        for contract in ledger["contracts"]
            residual=contract["net_MW"]-contract["peer_export_MW"]-contract["retail_sell_MW"]+contract["retail_buy_MW"]
            row("R9-T6-contract", "ledger", contract["actor"], contract["t"], residual, "MW", ptol)
            i=only(findall(x->x["id"]==contract["actor"], a))
            row(
                "R9-T6-retail-capacity",
                "ledger",
                contract["actor"],
                contract["t"],
                max(
                    0.0,
                    contract["retail_buy_MW"]-a[i]["retail_limit_MW"],
                    contract["retail_sell_MW"]-a[i]["retail_limit_MW"],
                ),
                "MW",
                ptol,
            )
        end
    end
    modelpass=all(x["pass"] for x in rows if x["scope"]=="model")
    Dict(
        "model_pass"=>modelpass,
        "electric_original_pass"=>!localonly &&
                                  all(x["pass"] for x in rows if x["scope"]=="electric_original"),
        "heat_energy_mass_pass"=>!localonly &&
                                 all(x["pass"] for x in rows if startswith(x["equation"], "R9-T5")),
        "ledger_pass"=>!localonly && all(x["pass"] for x in rows if x["scope"]=="ledger"),
        "full_thermal_physics_certified"=>false,
        "recomputed_objective_CNY"=>expected,
        "system_cost_CNY"=>costs.total,
        "rows"=>rows,
    )
end
