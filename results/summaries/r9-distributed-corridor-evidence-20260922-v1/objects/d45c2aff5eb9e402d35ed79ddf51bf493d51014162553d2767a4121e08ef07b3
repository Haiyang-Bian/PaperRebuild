function r4_nash_inputs(u, d, weights)
    length(u)==length(d)==length(weights)>=2 || error("效用、分歧点、权重须等长且至少两方")
    all(x->x isa Real && isfinite(x), vcat(u, d, weights)) || error("议价输入须有限")
    all(>(0), weights) || error("本批解析式要求严格正权重")
    uf, df, wf=Float64.(u), Float64.(d), Float64.(weights)
    all(isfinite, vcat(uf, df, wf)) || error("议价输入超出Float64范围")
    total=sum(wf)
    isfinite(total) && total>0 || error("权重和必须有限正数")
    surplus=sum(uf .- df)
    isfinite(surplus) || error("剩余溢出")
    return uf, df, wf, wf ./ total, surplus
end

"""
    r4_nash_allocation(prepayment_utility, disagreement, weights)

按论文式(4-82)/(4-94)分配固定物理计划的可转移效用。输入单位为合成美元，
权重严格为正；净支付正值表示收款，负值表示付款，所有支付之和为零。
采用无限额、无交易摩擦的转移假设。负剩余明确返回不可满足个体理性；
恰好零剩余只返回退化分配，不计算log(0)，也不以容差把负剩余改成零。
返回的总支付替代原内部结算；不能再次叠加到已经结算后的效用。
函数不求解物理模型、不写文件；不证明任意子联盟稳定或物理计划全局最优。
"""
function r4_nash_allocation(u, d, weights)
    u, d, weights, fractions, S=r4_nash_inputs(u, d, weights)
    out=Dict{String,Any}(
        "schema"=>"r4-nash-allocation-v1",
        "model"=>"r4_nash_checked_v1",
        "unit"=>"USD_synthetic",
        "transfer_convention"=>"positive_receipt_total_internal_payment",
        "transfer_domain"=>"unrestricted_budget_balanced",
        "prepayment_utility"=>u,
        "disagreement_utility"=>d,
        "weights"=>weights,
        "weight_fractions"=>fractions,
        "surplus"=>S,
        "status"=>S<0 ? "negative_surplus" : S==0 ? "zero_surplus_degenerate" : "allocated",
    )
    S<0 && return out
    # 固定物理计划后，最大化加权log增益；一阶条件给出增益=权重份额×总剩余。
    gain=fractions .* S
    out["gain"]=gain
    out["total_transfer"]=d .- u .+ gain
    out["utility_after"]=u .+ out["total_transfer"]
    if S>0
        all(>(0), gain) || error("正增益低于Float64可表达范围")
        # 以1合成美元为对数参考单位；归一化权重不改变最优分配。
        out["log_nash"]=sum(fractions .* log.(gain))
    end
    return out
end

"""
    r4_bargaining_weights(case; rule=:capacity_load_v1)

返回预先声明的议价权重及组成。capacity_load_v1参考论文PDF72页：
聚合商按CHP电功率、PV、HP/EB输入功率、电池功率和参考电/热峰荷之和计权，
运营商权重等于聚合商权重之和。电池MWh不与MW相加，CHP热功率不重复计入。
这是原文“容量加峰荷”的项目映射，不宣称是作者未公开的精确权重。
equal_v1为三方等权对照。权重是分配规则，不是物理能量或贡献因果估计。
"""
function r4_bargaining_weights(c::R4Case; rule = :capacity_load_v1)
    rule in (:capacity_load_v1, :equal_v1) || error("未知议价权重规则")
    a=c.data["actors"]
    components=[
        Dict(
            "actor"=>a[i]["id"],
            "CHP_electric_MW"=>a[i]["CHP_max"],
            "PV_MW"=>a[i]["PV_max"],
            "HP_input_MW"=>a[i]["HP_max"],
            "EB_input_MW"=>a[i]["EB_max"],
            "battery_power_MW"=>a[i]["BS_power_max"],
            "peak_electric_load_MW"=>maximum(a[i]["P_load"]),
            "peak_heat_load_MW"=>maximum(a[i]["H_load"]),
        ) for i in 2:3
    ]
    ag=[sum(Float64(v) for (k, v) in row if k!="actor") for row in components]
    weights=rule==:equal_v1 ? ones(3) : [sum(ag); ag]
    all(>(0), weights) || error("容量计权存在零权重；须另行声明分配规则")
    return Dict(
        "rule"=>String(rule),
        "actors"=>[x["id"] for x in a],
        "weights"=>weights,
        "components"=>components,
        "interpretation"=>"project_mapping_of_thesis_capacity_plus_peak_load",
    )
end

"""
    r4_allocate_coordination(case, independent, central; weights)

对已有、同输入且通过A1的AG0/SWM进行单阶段议价核算，不改变调度。
先独立验收物理候选和费用恒等式，再按式(4-94)计算总内部支付、相对旧结算的
增量补偿及最终效用。总支付与增量补偿分别保存，避免重复计费。
保留父运行的最优性证据限制；此接口不把候选计划升级为全局最优计划。
"""
function r4_allocate_coordination(c::R4Case, independent, central; weights)
    surplus=r4_coordination_surplus(c, independent, central)
    surplus["eligible"] && surplus["accounting_identity_pass"] ||
        error("没有同输入、可实施且账本合格的分歧点与合作计划")
    ledger=r4_ledger(c, central["values"])
    u=[-row["prepayment_cost"] for row in ledger["actors"]]
    d=[row["disagreement_utility"] for row in surplus["actors"]]
    allocation=r4_nash_allocation(u, d, weights)
    out=Dict{String,Any}(
        "schema"=>"r4-coordination-allocation-v1",
        "origin"=>"synthetic",
        "input_sha256"=>c.sha256,
        "method"=>"single_stage_fixed_dispatch_nash",
        "allocation"=>allocation,
        "parent_evidence"=>surplus,
        "actors"=>[row["id"] for row in c.data["actors"]],
        "physical_values_sha256"=>bytes2hex(sha256(r4_text(central["values"]))),
        "scope"=>"adopted_static_heat_model; unrestricted_transfer; not_coalition_core",
    )
    if haskey(allocation, "total_transfer")
        oldcash=[row["internal_net_cash"] for row in ledger["actors"]]
        out["previous_internal_net_cash"]=oldcash
        out["incremental_compensation"]=allocation["total_transfer"] .- oldcash
        out["previous_utility"]=[row["utility"] for row in ledger["actors"]]
    end
    out["validation"]=validate_r4_allocation(allocation)
    return out
end
