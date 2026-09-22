function r4_tspa_row!(rows, id, entity, t, value, unit, tol; scope = "tspa")
    residual=abs(Float64(value))
    push!(
        rows,
        Dict(
            "equation"=>id,
            "entity"=>string(entity),
            "t"=>t,
            "residual"=>residual,
            "unit"=>unit,
            "tolerance"=>Float64(tol),
            "pass"=>isfinite(residual)&&residual<=tol,
            "scope"=>scope,
        ),
    )
end

"""
    validate_r4_trading(case, result)

独立检查AGNB的设备/状态、合同反对称性、有限交易边界和费用。不检查物理网络。
沿用局部设备验算，合同平衡另行计入双边出售量；不把缺少网络列解释为零残差。
网络费按实际绝对交易一次计入，必须核对绝对值辅助变量没有虚假费用。
"""
function validate_r4_trading(c::R4Case, r)
    r["input_sha256"]==c.sha256 || error("交易输入哈希不符")
    rows=Dict{String,Any}[]
    haskey(r, "values") || return Dict("model_pass"=>false, "network_checked"=>false, "rows"=>rows)
    d=c.data
    s=r["values"]
    power_tol=1e-6*(1+d["electric"]["grid_max"])
    # 只复用设备、状态和边界检查；旧R4-P1不含P2P，必须用下面的新合同方程替代。
    for i in 2:3
        local_values=deepcopy(s)
        for carrier in ("P", "H"), side in ("buy", "sell")
            key=carrier*"_"*side
            local_values[key]=copy(s[key][i])
        end
        local_view=Dict(
            "input_sha256"=>c.sha256,
            "spec"=>r["spec"],
            "stage"=>"local",
            "actor"=>i,
            "values"=>local_values,
            "solver_objective"=>r["solver_objective"],
        )
        local_check=validate_r4_solution(c, local_view)
        append!(
            rows,
            filter(x->!(x["equation"] in ("R4-P1", "cost_recomputed")), local_check["rows"]),
        )
    end
    V(k, i, t) = s[k][i][t]
    for carrier in ("P", "H"), t in 1:d["T"]
        q=s[carrier*"_peer"][t]
        qa=s[carrier*"_peer_abs"][t]
        cap=d["p2p_enabled"] ? minimum(d["actors"][i]["retail_limit"] for i in 2:3) : 0.0
        r4_tspa_row!(
            rows,
            "R4-T1-peer-bound",
            carrier,
            t,
            max(abs(q)-cap, -qa, qa-cap, 0),
            "MW",
            power_tol,
        )
        r4_tspa_row!(rows, "R4-T1-absolute-fee", carrier, t, qa-abs(q), "MW", power_tol)
        for i in 2:3
            p=V("P_CHP", i, t)+V("P_PV", i, t)+V("P_dis", i, t)-V("P_ch", i, t)-V("P_HP", i, t)-V(
                "P_EB",
                i,
                t,
            )-V("P_D", i, t)
            h=V("H_src", i, t)-V("H_D", i, t)
            exportq=i==2 ? q : -q
            residual=(carrier=="P" ? p : h)-V(carrier*"_sell", i, t)+V(carrier*"_buy", i, t)-exportq
            r4_tspa_row!(rows, "R4-T1-contract", string(i)*carrier, t, residual, "MW", power_tol)
        end
    end
    ledger=r4_trading_ledger(c, s)
    cost=ledger["aggregator_cost"]
    r4_tspa_row!(
        rows,
        "R4-T1-objective",
        "AG",
        0,
        cost-r["solver_objective"],
        "USD",
        1e-6*max(1, abs(cost)),
    )
    # 运营商在忽略网络的第一阶段没有控制变量或外部物理供能。
    for key in R4_CONTROL_KEYS, t in eachindex(s[key][1])
        r4_tspa_row!(
            rows,
            "R4-T1-inactive-DSO",
            key,
            t,
            s[key][1][t],
            key=="E" ? "MWh" : "native",
            1e-6,
        )
    end
    return Dict(
        "model_pass"=>all(x["pass"] for x in rows),
        "network_checked"=>false,
        "aggregator_cost"=>cost,
        "rows"=>rows,
    )
end

"""
    validate_r4_elastic(case, result; frozen)

独立验收节点弹性网络：重算带符号P/Q/H/质量违反与正负松弛、罚项及物理费用。
保留无松弛A1检查，relaxed_model_pass不意味着original_physical_pass。
仅四类声明的节点平衡可软化；设备、容量、端口与电网版本全部保持硬约束。
"""
function validate_r4_elastic(c::R4Case, r; frozen)
    r["input_sha256"]==c.sha256 || error("弹性网络输入不符")
    rows=Dict{String,Any}[]
    haskey(r, "values") ||
        return Dict("relaxed_model_pass"=>false, "original_physical_pass"=>false, "rows"=>rows)
    s=r["values"]
    d=c.data
    e=d["electric"]
    h=d["heat"]
    dt=d["dt_h"]
    scales=r4_tspa_scales(c)
    r["normalization_scales"]==scales || error("松弛尺度不是冻结输入定义")
    penalty=r["balance_penalty"]
    isfinite(penalty) && penalty>0 || error("无效罚系数")
    V(k, i, t) = s[k][i][t]
    penalty_cost=dt*penalty*sum(
        V("slack_"*k*"_"*side, i, t)/scales[k] for
        k in ("P", "Q", "H", "m"), side in ("pos", "neg"), i in 1:3, t in 1:d["T"]
    )
    # 独立物理验证的目标是资源成本；另保存并验证真正的求解目标含罚项。
    view=deepcopy(r)
    view["solver_objective"]=r["solver_objective"]-penalty_cost
    view["local_stages"]=frozen
    physical=validate_r4_solution(c, view)
    soft=("electric_balance", "reactive_balance", "heat_balance", "mass_balance")
    append!(rows, filter(x->!(x["equation"] in soft), physical["rows"]))
    for t in 1:d["T"], i in 1:3
        ein=findall(x->x["to"]==i, e["edges"])
        eout=findall(x->x["from"]==i, e["edges"])
        hin=findall(x->x["to"]==i, h["pipes"])
        hout=findall(x->x["from"]==i, h["pipes"])
        pnet=V("P_CHP", i, t)+V("P_PV", i, t)+V("P_dis", i, t)-V("P_ch", i, t)-V("P_HP", i, t)-V(
            "P_EB",
            i,
            t,
        )-V("P_D", i, t)
        residuals=Dict(
            "P"=>pnet+(i==1 ? s["P_grid"][t] : 0)+e["S_base_MVA"]*(
                sum(V("P_branch", p, t)-e["edges"][p]["r"]*V("ell", p, t) for p in ein; init = 0)-sum(
                    V("P_branch", p, t) for p in eout;
                    init = 0,
                )
            ),
            "Q"=>-d["actors"][i]["Q_ratio"]*V("P_D", i, t)+(i==1 ? s["Q_grid"][t] : 0)+e["S_base_MVA"]*(
                sum(V("Q_branch", p, t)-e["edges"][p]["x"]*V("ell", p, t) for p in ein; init = 0)-sum(
                    V("Q_branch", p, t) for p in eout;
                    init = 0,
                )
            ),
            "H"=>V("H_src", i, t)-V("H_D", i, t)+sum(V("H_out", p, t) for p in hin; init = 0)-sum(
                V("H_in", p, t) for p in hout;
                init = 0,
            ),
            "m"=>V("m_source", i, t)-V("m_load", i, t)+sum(
                V("m_pipe", p, t) for p in hin;
                init = 0,
            )-sum(V("m_pipe", p, t) for p in hout; init = 0),
        )
        for k in ("P", "Q", "H", "m")
            unit=k=="m" ? "kg/s" : k=="Q" ? "Mvar" : "MW"
            tol=k=="m" ? 1e-6*(1+maximum(p["flow_max"] for p in h["pipes"])) :
                1e-6*(1+e["grid_max"])
            pos=V("slack_"*k*"_pos", i, t)
            neg=V("slack_"*k*"_neg", i, t)
            r4_tspa_row!(
                rows,
                "R4-T2-slack-nonnegative",
                string(i)*k,
                t,
                max(-pos, -neg, 0),
                unit,
                tol,
            )
            r4_tspa_row!(
                rows,
                "R4-T2-signed-balance",
                string(i)*k,
                t,
                residuals[k]-pos+neg,
                unit,
                tol,
            )
        end
    end
    resource=r4_ledger(c, s)["operating_cost"]
    r4_tspa_row!(
        rows,
        "R4-T2-objective",
        "all",
        0,
        resource+penalty_cost-r["solver_objective"],
        "USD",
        1e-6*max(1, abs(r["solver_objective"])),
    )
    return Dict(
        "relaxed_model_pass"=>all(x["pass"] for x in rows if x["scope"]!="electric_original"),
        "original_physical_pass"=>physical["model_pass"]&&physical["electric_original_pass"],
        "physical_validation"=>physical,
        "resource_cost"=>resource,
        "penalty_cost"=>penalty_cost,
        "normalized_violation_h"=>penalty_cost/penalty,
        "rows"=>rows,
    )
end

"""
    validate_r4_tspa(case, result)

从保存值重验两阶段流程、候选选择、冻结控制与两种罚项口径。不求解、不改写父记录。
分别报告交易模型、严格网络、弹性网络和分配；失败运行可以有完整且正确的记录。
仅有合作计划通过A1才输出其分配，不宣称松弛分歧点本身可执行或联盟普遍稳定。
"""
function validate_r4_tspa(c::R4Case, r)
    r["input_sha256"]==c.sha256 || error("TSPA输入不一致")
    r["tspa_spec"]["elastic_scope"]=="nodal_balance_elastic_v1" || error("未知松弛范围")
    parents=r["parents"]
    all(x["input_sha256"]==c.sha256 for x in values(parents)) || error("父输入不一致")
    local_checks=[validate_r4_solution(c, x) for x in parents["independent"]["local_stages"]]
    all(x["model_pass"] for x in local_checks) || error("父局部计划不合格")
    original=r["trading_solver"]
    solvercheck=validate_r4_trading(c, original)
    incumbent=r4_trading_incumbent(c, parents["independent"]["local_stages"])
    choose=solvercheck["model_pass"] &&
           r4_trading_ledger(c, original["values"])["aggregator_cost"]<=incumbent["solver_objective"]
    expected=choose ? "solver_candidate" : "known_independent_incumbent"
    selected=r["trading_selected"]
    r["selection"]==expected && selected["values"]==(choose ? original : incumbent)["values"] ||
        error("候选选择/数值改变")
    tc=validate_r4_trading(c, selected)
    strict=deepcopy(r["strict_network"])
    frozen=r4_tspa_frozen(selected)
    strict["local_stages"]=frozen
    sc=validate_r4_solution(c, strict)
    r["elastic_network"]["balance_penalty"]==r["tspa_spec"]["penalty"] || error("罚系数漂移")
    ec=validate_r4_elastic(c, r["elastic_network"]; frozen)
    economics=r4_tspa_economics(c, r)
    economics==r["economics"] || error("账本/分配重算不一致")
    # 罚项只改分歧效用；两口径的合作物理控制没有任何变化。
    rows=Dict{String,Any}[]
    for x in economics["stage2"]
        gap=x["allocation"]["surplus"]-x["resource_surplus"]-x["included_penalty"]
        r4_tspa_row!(
            rows,
            "R4-T3-surplus-accounting",
            x["variant"],
            0,
            gap,
            "USD",
            1e-6*max(1, abs(x["allocation"]["surplus"])),
        )
    end
    checks_match=solvercheck==original["validation"] &&
                 tc==selected["validation"] &&
                 sc==r["strict_network"]["validation"] &&
                 ec==r["elastic_network"]["validation"]
    return Dict(
        "record_pass"=>checks_match&&all(x["pass"] for x in rows),
        "trading_model_pass"=>tc["model_pass"],
        "strict_network_physical_pass"=>sc["model_pass"]&&sc["electric_original_pass"],
        "relaxed_network_pass"=>ec["relaxed_model_pass"],
        "relaxed_point_physical_pass"=>ec["original_physical_pass"],
        "stage1_allocation_pass"=>economics["stage1"]["validation"]["allocation_pass"],
        "stage2_allocation_pass"=>[x["validation"]["allocation_pass"] for x in economics["stage2"]],
        "rows"=>rows,
    )
end
