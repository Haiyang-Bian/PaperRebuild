"""
    r4_ledger(case, values; p2p_enabled=true, settlement=case.data["settlement"])

从保存的数值独立核算资源、负荷不满意度及内部现金流；不调用JuMP。
电/热合同出售为正，按A/B净余缺匹配，每笔卖方服务费只记一次，DSO收款。
价格为合成美元/MWh，数量按MW乘时长。式(4-14/24/56/57)的采用方向见R4-P1、P6。
返回主体支付前成本、交易明细、结算后示例收益及平衡误差；未执行议价。
"""
function r4_ledger(
    c::R4Case,
    s;
    p2p_enabled = c.data["p2p_enabled"],
    settlement = c.data["settlement"],
)
    d=c.data
    T=d["T"]
    dt=d["dt_h"]
    a=d["actors"]
    V(k, i, t) = s[k][i][t]
    P=[
        V("P_CHP", i, t)+V("P_PV", i, t)+V("P_dis", i, t)-V("P_ch", i, t)-V("P_HP", i, t)-V(
            "P_EB",
            i,
            t,
        )-V("P_D", i, t) for i in 1:3, t in 1:T
    ]
    H=[
        a[i]["heat_ratio"]*V("P_CHP", i, t)+a[i]["COP_HP"]*V("P_HP", i, t)+a[i]["COP_EB"]*V(
            "P_EB",
            i,
            t,
        )-V("H_D", i, t) for i in 1:3, t in 1:T
    ]
    rows=Dict{String,Any}[]
    contracts=Dict{String,Any}[]
    cash=zeros(3)
    costs=Dict{String,Any}[]
    function pay(from, to, kind, carrier, t, amount, price)
        amount=max(0.0, amount)
        money=amount*price
        cash[from]-=money
        cash[to]+=money
        push!(
            rows,
            Dict(
                "from"=>a[from]["id"],
                "to"=>a[to]["id"],
                "kind"=>kind,
                "carrier"=>carrier,
                "t"=>t,
                "quantity_MWh"=>amount,
                "price"=>price,
                "amount"=>money,
            ),
        )
    end
    for (carrier, net) in (("P", P), ("H", H)), t in 1:T
        q=0.0
        if p2p_enabled
            if net[2, t]>0 && net[3, t]<0
                q=min(net[2, t], -net[3, t])
            elseif net[3, t]>0 && net[2, t]<0
                q=-min(net[3, t], -net[2, t])
            end
        end
        seller=q>=0 ? 2 : 3
        buyer=5-seller
        pay(buyer, seller, "p2p", carrier, t, abs(q)*dt, settlement[carrier*"_peer"])
        pay(seller, 1, "service", carrier, t, abs(q)*dt, settlement["fee"])
        for i in 2:3
            exportq=i==2 ? q : -q
            retail=net[i, t]-exportq
            buy=max(-retail, 0)
            sell=max(retail, 0)
            pay(i, 1, "retail_buy", carrier, t, buy*dt, settlement[carrier*"_buy"])
            pay(1, i, "retail_sell", carrier, t, sell*dt, settlement[carrier*"_sell"])
            push!(
                contracts,
                Dict(
                    "actor"=>a[i]["id"],
                    "carrier"=>carrier,
                    "t"=>t,
                    "net_MW"=>net[i, t],
                    "peer_export_MW"=>exportq,
                    "retail_buy_MW"=>buy,
                    "retail_sell_MW"=>sell,
                ),
            )
        end
    end
    for i in 1:3
        resource=dt*sum(
            a[i]["CHP_cost"]*V("P_CHP", i, t)+a[i]["PV_cost"]*V("P_PV", i, t)+a[i]["BS_cost"]*(
                V("P_ch", i, t)+V("P_dis", i, t)
            ) for t in 1:T
        )
        dissatisfaction=dt*sum(
            a[i]["sat_"*carrier]*((1+a[i]["flex"])*a[i][carrier*"_load"][t]-V(carrier*"_D", i, t))^2
            for carrier in ("P", "H"), t in 1:T
        )
        external=i==1 && haskey(s, "P_grid") ? dt*sum(d["grid_price"] .* s["P_grid"]) : 0.0
        cost=resource+dissatisfaction+external
        push!(
            costs,
            Dict(
                "actor"=>a[i]["id"],
                "resource"=>resource,
                "dissatisfaction"=>dissatisfaction,
                "external"=>external,
                "prepayment_cost"=>cost,
                "internal_net_cash"=>cash[i],
                "utility"=>cash[i]-cost,
            ),
        )
    end
    total=sum(x["prepayment_cost"] for x in costs)
    return Dict(
        "actors"=>costs,
        "payments"=>rows,
        "contracts"=>contracts,
        "operating_cost"=>total,
        "cash_balance"=>sum(cash),
        "utility_identity"=>sum(x["utility"] for x in costs)+total,
        "p2p_enabled"=>p2p_enabled,
        "settlement"=>settlement,
        "bargaining"=>"not_performed",
    )
end

"""
    validate_r4_solution(case, result)

独立回代设备、负荷、端口、径向电网、稳态热能流及账本；不复用JuMP约束。
A1功率/能量/流量为1e-6绝对项加冻结输入尺度的1e-6；无量纲及整数1e-6。
模型通过、电网原等式、热能流和内部现金流分别返回，热网不含动态温度。
缺解不生成零残差；局部AG0解只检查本地主体，网络阶段额外检查冻结计划。
"""
function validate_r4_solution(c::R4Case, result)
    rows=Dict{String,Any}[]
    result["input_sha256"]==c.sha256 || error("结果输入哈希不匹配")
    haskey(result, "values") || return Dict(
        "model_pass"=>false,
        "electric_original_pass"=>false,
        "heat_pass"=>false,
        "ledger_pass"=>false,
        "rows"=>rows,
        "status"=>"not_evaluated",
    )
    d=c.data
    s=result["values"]
    a=d["actors"]
    e=d["electric"]
    h=d["heat"]
    T=d["T"]
    dt=d["dt_h"]
    local_only=get(result, "stage", "")=="local"
    inds=local_only ? [result["actor"]] : collect(1:3)
    V(k, i, t) = s[k][i][t]
    power_tol=1e-6*(1+e["grid_max"])
    flow_tol=1e-6*(1+maximum(p["flow_max"] for p in h["pipes"]))
    energy_tol=1e-6*(1+maximum(x["BS_energy_max"] for x in a))
    function row(id, scope, i, t, r, unit, tol)
        value=abs(Float64(r))
        push!(
            rows,
            Dict(
                "equation"=>id,
                "scope"=>scope,
                "entity"=>string(i),
                "t"=>t,
                "residual"=>value,
                "unit"=>unit,
                "tolerance"=>tol,
                "pass"=>isfinite(value)&&value<=tol,
            ),
        )
    end
    bound(id, scope, i, t, x, lo, hi, unit, tol) =
        row(id, scope, i, t, max(lo-x, x-hi, 0.0), unit, tol)
    for i in inds
        x=a[i]
        for t in 1:T
            for (k, cap) in (
                ("P_CHP", "CHP_max"),
                ("P_HP", "HP_max"),
                ("P_EB", "EB_max"),
                ("P_ch", "BS_power_max"),
                ("P_dis", "BS_power_max"),
            )
                bound("devices", "model", i, t, V(k, i, t), 0, x[cap], "MW", power_tol)
            end
            bound(
                "PV",
                "model",
                i,
                t,
                V("P_PV", i, t),
                0,
                x["PV_max"]*x["PV_profile"][t],
                "MW",
                power_tol,
            )
            for carrier in ("P", "H")
                ref=x[carrier*"_load"][t]
                bound(
                    "demand",
                    "model",
                    i,
                    t,
                    V(carrier*"_D", i, t),
                    (1-x["flex"])*ref,
                    (1+x["flex"])*ref,
                    "MW",
                    power_tol,
                )
                if x["sat_"*carrier]>0
                    row(
                        "dissatisfaction_epigraph",
                        "model",
                        i,
                        t,
                        max(((1+x["flex"])*ref-V(carrier*"_D", i, t))^2-V("w_"*carrier, i, t), 0),
                        "MW²",
                        1e-6,
                    )
                end
            end
            source=x["heat_ratio"]*V("P_CHP", i, t)+x["COP_HP"]*V("P_HP", i, t)+x["COP_EB"]*V(
                "P_EB",
                i,
                t,
            )
            row("heat_conversion", "model", i, t, V("H_src", i, t)-source, "MW", power_tol)
            row(
                "R4-P2",
                "model",
                i,
                t,
                V("E", i, t+1)-V("E", i, t)-dt*(
                    x["eta_ch"]*V("P_ch", i, t)-V("P_dis", i, t)/x["eta_dis"]
                ),
                "MWh",
                energy_tol,
            )
            if x["BS_power_max"]>0
                z=s["z"][t]
                bound("battery_mode", "model", i, t, z, 0, 1, "1", 1e-6)
                row("binary", "model", i, t, z-round(z), "1", 1e-6)
                row(
                    "charge_exclusive",
                    "model",
                    i,
                    t,
                    max(V("P_ch", i, t)-x["BS_power_max"]*z, 0),
                    "MW",
                    power_tol,
                )
                row(
                    "discharge_exclusive",
                    "model",
                    i,
                    t,
                    max(V("P_dis", i, t)-x["BS_power_max"]*(1-z), 0),
                    "MW",
                    power_tol,
                )
            end
        end
        for t in 1:(T+1)
            bound("energy", "model", i, t, V("E", i, t), 0, x["BS_energy_max"], "MWh", energy_tol)
        end
        row("initial", "model", i, 0, V("E", i, 1)-x["BS_initial"], "MWh", energy_tol)
        row("terminal", "model", i, T, V("E", i, T+1)-x["BS_initial"], "MWh", energy_tol)
    end
    Pnet(i, t) =
        V("P_CHP", i, t)+V("P_PV", i, t)+V("P_dis", i, t)-V("P_ch", i, t)-V("P_HP", i, t)-V(
            "P_EB",
            i,
            t,
        )-V("P_D", i, t)
    Hnet(i, t) = V("H_src", i, t)-V("H_D", i, t)
    if local_only
        i=only(inds)
        for carrier in ("P", "H"), t in 1:T
            for side in ("buy", "sell")
                bound(
                    "retail_bound",
                    "model",
                    i,
                    t,
                    s[carrier*"_"*side][t],
                    0,
                    a[i]["retail_limit"],
                    "MW",
                    power_tol,
                )
            end
            row(
                "R4-P1",
                "model",
                i,
                t,
                (carrier=="P" ? Pnet(i, t) : Hnet(i, t))-s[carrier*"_sell"][t]+s[carrier*"_buy"][t],
                "MW",
                power_tol,
            )
        end
    else
        for t in 1:T
            bound("grid", "model", 1, t, s["P_grid"][t], 0, e["grid_max"], "MW", power_tol)
            bound(
                "reactive_grid",
                "model",
                1,
                t,
                s["Q_grid"][t],
                -e["Q_grid_max"],
                e["Q_grid_max"],
                "Mvar",
                power_tol,
            )
            row("root_voltage", "model", 1, t, V("v", 1, t)-1, "pu²", 1e-6)
            for (p, edge) in enumerate(e["edges"])
                i=edge["from"]
                j=edge["to"]
                r=edge["r"]
                x=edge["x"]
                base=e["S_base_MVA"]
                P=V("P_branch", p, t)
                Q=V("Q_branch", p, t)
                ell=V("ell", p, t)
                vi=V("v", i, t)
                bound(
                    "P_branch",
                    "model",
                    p,
                    t,
                    P*base,
                    -edge["P_max"],
                    edge["P_max"],
                    "MW",
                    power_tol,
                )
                bound(
                    "Q_branch",
                    "model",
                    p,
                    t,
                    Q*base,
                    -edge["Q_max"],
                    edge["Q_max"],
                    "Mvar",
                    power_tol,
                )
                bound("ell", "model", p, t, ell, 0, edge["ell_max"], "pu²", 1e-6)
                row(
                    "voltage_drop",
                    "model",
                    p,
                    t,
                    V("v", j, t)-vi+2*(r*P+x*Q)-(r^2+x^2)*ell,
                    "pu²",
                    1e-6,
                )
                gap=vi*ell-P^2-Q^2
                row("branch_socp", "model", p, t, max(-gap, 0), "pu⁴", 1e-6)
                row("branch_equality", "electric_original", p, t, gap, "pu⁴", 1e-6)
                result["spec"]["electric"]=="exact" &&
                    row("branch_equality", "model", p, t, gap, "pu⁴", 1e-6)
            end
            for i in 1:3
                bound(
                    "voltage",
                    "model",
                    i,
                    t,
                    V("v", i, t),
                    e["v_min"]^2,
                    e["v_max"]^2,
                    "pu²",
                    1e-6,
                )
                edges=e["edges"]
                incoming=findall(x->x["to"]==i, edges)
                outgoing=findall(x->x["from"]==i, edges)
                base=e["S_base_MVA"]
                pr=Pnet(i, t)+(i==1 ? s["P_grid"][t] : 0)+base*(
                    sum(
                        V("P_branch", p, t)-edges[p]["r"]*V("ell", p, t) for p in incoming;
                        init = 0,
                    )-sum(V("P_branch", p, t) for p in outgoing; init = 0)
                )
                qr=-a[i]["Q_ratio"]*V("P_D", i, t)+(i==1 ? s["Q_grid"][t] : 0)+base*(
                    sum(
                        V("Q_branch", p, t)-edges[p]["x"]*V("ell", p, t) for p in incoming;
                        init = 0,
                    )-sum(V("Q_branch", p, t) for p in outgoing; init = 0)
                )
                row("electric_balance", "model", i, t, pr, "MW", power_tol)
                row("reactive_balance", "model", i, t, qr, "Mvar", power_tol)
                pipes=h["pipes"]
                inc=findall(x->x["to"]==i, pipes)
                out=findall(x->x["from"]==i, pipes)
                row(
                    "mass_balance",
                    "heat",
                    i,
                    t,
                    V("m_source", i, t)-V("m_load", i, t)+sum(
                        V("m_pipe", p, t) for p in inc;
                        init = 0,
                    )-sum(V("m_pipe", p, t) for p in out; init = 0),
                    "kg/s",
                    flow_tol,
                )
                row(
                    "heat_balance",
                    "heat",
                    i,
                    t,
                    Hnet(i, t)+sum(V("H_out", p, t) for p in inc; init = 0)-sum(
                        V("H_in", p, t) for p in out;
                        init = 0,
                    ),
                    "MW",
                    power_tol,
                )
                for (key, H, port) in
                    (("m_source", V("H_src", i, t), "source"), ("m_load", V("H_D", i, t), "load"))
                    m=V(key, i, t)
                    bound("port_mass", "heat", i, t, m, 0, a[i]["port_flow_max"], "kg/s", flow_tol)
                    bound(
                        "port_heat",
                        "heat",
                        i,
                        t,
                        H,
                        h["cp"]*h[port*"_delta_min"]*m/1e6,
                        h["cp"]*h[port*"_delta_max"]*m/1e6,
                        "MW",
                        power_tol,
                    )
                end
            end
            for (p, pipe) in enumerate(h["pipes"])
                loss=pipe["U_W_mK"]*pipe["length_m"]*(
                    (pipe["S_ref_K"]-pipe["ambient_K"])+(pipe["R_ref_K"]-pipe["ambient_K"])
                )/1e6
                row("R4-P4", "heat", p, t, V("H_in", p, t)-V("H_out", p, t)-loss, "MW", power_tol)
                for k in ("H_in", "H_out")
                    bound("pipe_heat", "heat", p, t, V(k, p, t), 0, pipe["H_max"], "MW", power_tol)
                end
                bound(
                    "pipe_mass",
                    "heat",
                    p,
                    t,
                    V("m_pipe", p, t),
                    0,
                    pipe["flow_max"],
                    "kg/s",
                    flow_tol,
                )
            end
        end
        for local_run in get(result, "local_stages", Any[])
            haskey(local_run, "values") || continue
            i=local_run["actor"]
            for k in ("P_CHP", "P_PV", "P_HP", "P_EB", "P_ch", "P_dis", "P_D", "H_D", "E"),
                t in eachindex(s[k][i])

                row(
                    "AG0_frozen",
                    "model",
                    k*string(i),
                    t,
                    s[k][i][t]-local_run["values"][k][i][t],
                    k=="E" ? "MWh" : "MW",
                    k=="E" ? energy_tol : power_tol,
                )
            end
        end
    end
    ledger=r4_ledger(
        c,
        s;
        p2p_enabled = !local_only && result["spec"]["operation"]=="central" && d["p2p_enabled"],
    )
    if local_only
        i=only(inds)
        cost=ledger["actors"][i]["prepayment_cost"]
        cost+=dt*sum(
            d["settlement"][carrier*"_buy"]*s[carrier*"_buy"][t]-d["settlement"][carrier*"_sell"]*s[carrier*"_sell"][t]
            for carrier in ("P", "H"), t in 1:T
        )
    else
        cost=ledger["operating_cost"]
        row(
            "cash_cancellation",
            "ledger",
            "all",
            0,
            ledger["cash_balance"],
            "USD",
            1e-6*max(1, abs(cost)),
        )
        row(
            "utility_identity",
            "ledger",
            "all",
            0,
            ledger["utility_identity"],
            "USD",
            1e-6*max(1, abs(cost)),
        )
        for x in ledger["contracts"]
            i=x["actor"]=="A" ? 2 : 3
            row(
                "contract_balance",
                "ledger",
                i,
                x["t"],
                x["net_MW"]-x["peer_export_MW"]-x["retail_sell_MW"]+x["retail_buy_MW"],
                "MW",
                power_tol,
            )
            row(
                "contract_bound",
                "ledger",
                i,
                x["t"],
                max(
                    x["retail_buy_MW"]-a[i]["retail_limit"],
                    x["retail_sell_MW"]-a[i]["retail_limit"],
                    0,
                ),
                "MW",
                power_tol,
            )
        end
    end
    row(
        "cost_recomputed",
        "model",
        "all",
        0,
        cost-result["solver_objective"],
        "USD",
        1e-6*max(1, abs(cost)),
    )
    pass(scope) = all(r["pass"] for r in rows if r["scope"] in scope)
    return Dict(
        "model_pass"=>pass(["model", "heat", "ledger"]),
        "electric_original_pass"=>!local_only&&pass(["electric_original"]),
        "heat_pass"=>!local_only&&pass(["heat"]),
        "ledger_pass"=>!local_only&&pass(["ledger"]),
        "rows"=>rows,
        "operating_cost"=>cost,
        "status"=>"evaluated",
    )
end
