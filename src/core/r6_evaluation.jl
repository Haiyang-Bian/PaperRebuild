const R6_EVALUATION_CORE_FILE=@__FILE__

"""
    R6EvaluationSpec()

独立的舒适能力诊断：先求硬舒适最低费用；仅其明确不可行时，最小化最大室温越界，
再在最小越界加1e-8 K的数值面内最小化费用。物理域、成交、交付和终端约束始终保持。
这是R6-E1项目对照，不替代正式风险策略或冒称作者操作规则；仍使用完整未来日轨迹。
"""
struct R6EvaluationSpec
    data::Dict{String,Any}
    sha256::String
end
function R6EvaluationSpec()
    d=Dict{String,Any}(
        "schema"=>"r6-evaluation-spec-v1",
        "version"=>"r6_comfort_priority_v1",
        "information"=>"complete_trajectory",
        "rule"=>"hard_comfort_then_minimum_peak_excess_then_cost",
        "lexicographic_allowance_K"=>1e-8,
        "peak_gap_K"=>1e-8,
        "comfort_tolerance_K"=>1e-4,
    )
    R6EvaluationSpec(d, bytes2hex(sha256(r5_market_text(d))))
end
r6_assert_evaluation(s) =
    s.data==R6EvaluationSpec().data && s.sha256==R6EvaluationSpec().sha256 ||
    error("R6补救规则被修改")

"""
    R6Policy

已核验训练结果提取的共同日前成交、市场结算价格和训练代表的舒适开关，连同来源哈希冻结。
新日用evaluate_r6_policy_day显式外推；evaluate_r6_day只作为独立舒适能力诊断。
"""
struct R6Policy
    data::Dict{String,Any}
    sha256::String
end
function r6_assert_policy(p)
    bytes2hex(sha256(r5_market_text(p.data)))==p.sha256 || error("R6已冻结策略被修改")
    p.data["schema"]=="r6-policy-v1" && p.data["evaluation_version"]=="r6_support_nearest_v1" ||
        error("R6策略版本错误")
    nothing
end

"""
    r6_policy_from_training(physical, training_case, result)

先独立核验训练候选，再提取成交和所选市场价格；不以参考解替换该策略。
对应R6-E2，日前净支付只计一次。保留乐观出清边界和训练费用完成状态。
"""
function r6_policy_from_training(p::R6PhysicalCase, c::R5StrategicCase, r)
    r6_assert_physical(p)
    r6_training_pattern(c)
    c.data["provenance"]["r6"]["physical_sha256"]==p.sha256 || error("训练物理来源不同")
    commitment=c.data["risk"]["commitment"]
    uncertain=["devices.available_MW", "realtime.alpha_up", "realtime.alpha_down"]
    signature=r5_commitment_signature(p.data["dispatch"], uncertain)
    all(
        r5_commitment_signature(s["case"], uncertain)==signature for s in commitment["scenarios"]
    ) || error("训练共同物理参数不匹配，不能只凭来源哈希替换模板")
    c.data["market"]==p.data["market"] &&
    c.data["bid_bounds"]==p.data["bid_bounds"] &&
    commitment["bounds"]==p.data["bounds"] &&
    c.data["risk"]["temperature_domain"]==p.data["temperature_domain"] ||
        error("训练市场或共同边界不符")
    v=validate_r5_strategic(c, r)
    v["model_pass"] && v["risk_pass"] && v["cost_pass"] || error("训练候选未通过独立检查")
    T=p.data["dispatch"]["T"]
    a=Dict{String,Any}(
        "origin"=>"verified_market",
        "dt_h"=>p.data["dispatch"]["dt_h"],
        "parent_run_id"=>r["run_id"],
        "parent_case_sha256"=>c.sha256,
        "parent_result_sha256"=>bytes2hex(sha256(IOBuffer(r5_market_text(r)))),
        "ies_id"=>c.data["leader_id"],
    )
    for k in ("P_DA_MW", "R_up_MW", "R_down_MW")
        a[k]=copy(r["risk_policy"]["first_stage"][k])
    end
    a["energy_price"]=copy(v["selected_market"]["LMP_USD_MWh"][1])
    a["up_price"]=copy(v["selected_market"]["reserve_up_price"])
    a["down_price"]=copy(v["selected_market"]["reserve_down_price"])
    payment=a["dt_h"]*sum(
        a["energy_price"][t]*a["P_DA_MW"][t] - a["up_price"][t]*a["R_up_MW"][t]-a["down_price"][t]*a["R_down_MW"][t]
        for t in 1:T
    )
    abs(payment-v["selected_payment_USD"])<=1e-6*max(1, abs(payment)) || error("日前支付不一致")
    d=Dict{String,Any}(
        "schema"=>"r6-policy-v1",
        "physical"=>deepcopy(p.data),
        "physical_sha256"=>p.sha256,
        "award"=>a,
        "day_ahead_net_payment_USD"=>payment,
        "method"=>c.data["provenance"]["r6"]["method"],
        "training_provenance"=>c.data["provenance"]["r6"],
        "training_cost_complete"=>get(r, "cost_optimization_complete", false),
    )
    support=Dict{String,Any}[]
    for (i, scenario) in enumerate(c.data["risk"]["commitment"]["scenarios"])
        pvs=filter(x->x["kind"]=="PV"&&x["p_max_MW"]>0, scenario["case"]["devices"])
        isempty(pvs) && error("策略距离需要正额定容量PV以还原训练比例")
        pv=pvs[1]
        fraction=pv["available_MW"] ./ pv["p_max_MW"]
        all(
            all(isapprox.(g["available_MW"] ./ g["p_max_MW"], fraction; atol = 1e-12, rtol = 0)) for
            g in pvs
        ) || error("PV轨迹比例不一致")
        rt=scenario["case"]["realtime"]
        raw=Float64(r["risk_policy"]["z"][i])
        label=round(Int, raw)
        label in (0, 1)&&abs(raw-label)<=1e-8 || error("训练舒适开关不满足离散验收")
        push!(
            support,
            Dict(
                "id"=>scenario["id"],
                "probability"=>scenario["probability"],
                "pv_fraction"=>fraction,
                "activation_signed"=>rt["alpha_up"]-rt["alpha_down"],
                "raw_z"=>raw,
                "label"=>label,
            ),
        )
    end
    d["support"]=support
    d["evaluation_version"]="r6_support_nearest_v1"
    R6Policy(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    r6_evaluation_day(policy, trajectory; id)

将2×T光伏比例/有符号调用转换为固定成交的一天；仅未来轨迹变化，价格、容量、历史和初末状态保持。
id记录完整日身份。对应R6-E2；不求解或写文件，此转换本身不决定新日的舒适开关。
"""
function r6_evaluation_day(p::R6Policy, trajectory::AbstractMatrix; id::AbstractString)
    r6_assert_policy(p)
    physical=R6PhysicalCase(p.data["physical"])
    physical.sha256==p.data["physical_sha256"] || error("冻结物理模板不符")
    d=deepcopy(r6_dispatch_day(physical, trajectory; id).data)
    d["award"]=deepcopy(p.data["award"])
    R5DispatchCase(d)
end

function r6_physical_day(c::R5DispatchCase, domain)
    r5_dispatch_assert_case(c)
    Set(keys(domain))==Set(b["id"] for b in c.data["buildings"]) || error("温度物理域清单不符")
    d=deepcopy(c.data)
    for b in d["buildings"]
        z=domain[b["id"]]
        lo, hi=z["lower_K"], z["upper_K"]
        isfinite(lo)&&isfinite(hi)&&0<lo<=b["T_min_K"]<=b["T_max_K"]<=hi ||
            error("温度物理域不能收缩舒适域或含非有限边界")
        b["T_min_K"], b["T_max_K"]=Float64(lo), Float64(hi)
    end
    R5DispatchCase(d)
end
