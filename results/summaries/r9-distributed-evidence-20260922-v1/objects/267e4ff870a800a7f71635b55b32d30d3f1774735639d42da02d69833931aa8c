const R9_EVALUATION_CORE_FILE = @__FILE__

"""
    R9ReservePolicy(data)

第7.4节已锁定的固定价格操作：共同日前成交、原电热输入、训练代表及舒适分支。
MW、h、K和输入显式币种保持；不接受R6策略出清的市场身份作为CNY成交来源。
策略身份包含训练来源，操作身份只比较实际输入和操作规则；相同操作可共用逐日计算，不能当作独立算法样本。
正式策略须由r9_reserve_policy_from_training经原训练验证器提取；直接构造也用于明确标注的解析夹具。
"""
struct R9ReservePolicy
    data::Dict{String,Any}
    sha256::String
    operation_sha256::String
end

function r9_operation_data(d)
    Dict(
        k => d[k] for k in (
            "evaluation_version",
            "information",
            "currency",
            "template",
            "temperature_domain",
            "support",
        )
    )
end
# 沿用同一TOML字节和既有IO摘要，避免Julia 1.12对大CodeUnits的反复别名检查。
r9_evaluation_hash(x) = r5_market_digest(x)

function R9ReservePolicy(input::AbstractDict)
    d = deepcopy(Dict{String,Any}(string(k) => v for (k, v) in input))
    d["schema"] == "r9-reserve-policy-v1" &&
    d["evaluation_version"] == "r9_nearest_recourse_v1" &&
    d["information"] == "complete_trajectory" || error("R9操作版本或信息边界错误")
    c = R5DispatchCase(d["template"])
    d["template"] = c.data
    r5_dispatch_currency(c.data) == d["currency"] || error("R9操作币种不同")
    c.data["award"]["origin"] == "synthetic" || error("本接口固定外生价格，不继承策略出清身份")
    r6_physical_day(c, d["temperature_domain"])
    support = d["support"]
    !isempty(support) && length(unique(s["id"] for s in support)) == length(support) ||
        error("训练代表缺失或重复")
    T = c.data["T"]
    for s in support
        length(s["pv_fraction"]) == length(s["activation_signed"]) == T || error("训练代表时域错误")
        all(x -> isfinite(x) && 0 <= x <= 1, s["pv_fraction"]) &&
        all(x -> isfinite(x) && -1 <= x <= 1, s["activation_signed"]) || error("训练轨迹越界")
        s["label"] isa Integer &&
        !(s["label"] isa Bool) &&
        s["label"] in (0, 1) &&
        isfinite(s["raw_z"]) &&
        abs(s["raw_z"] - s["label"]) <= 1e-8 || error("训练舒适分支不是合法整数")
        isfinite(s["probability"]) && s["probability"] > 0 || error("训练权重非法")
    end
    abs(sum(s["probability"] for s in support) - 1) <= 1e-12 || error("训练权重未归一")
    haskey(d, "training") || error("操作缺少训练来源")
    R9ReservePolicy(d, r9_evaluation_hash(d), r9_evaluation_hash(r9_operation_data(d)))
end

function r9_assert_policy(p::R9ReservePolicy)
    r9_evaluation_hash(p.data) == p.sha256 &&
    r9_evaluation_hash(r9_operation_data(p.data)) == p.operation_sha256 || error("锁定操作被修改")
end

"""
    r9_reserve_policy_from_training(case, result)

先独立回算R5RiskCase训练候选的模型、有限支持风险和费用，再锁定日前成交及原z。
训练全局费用未完成可以保留，但缺失或未通过验证的候选不能变成策略。不会注入共同见证或参考解。
R9-OS1；保留原细小备用值，不以显示意义的数值零替换实际输入。不求解或写文件。
"""
function r9_reserve_policy_from_training(c::R5RiskCase, r)
    d = c.data
    commitment = d["commitment"]
    all(
        k -> k in ("devices.available_MW", "realtime.alpha_up", "realtime.alpha_down"),
        commitment["uncertain_fields"],
    ) || error("本外推仅声明PV和调用不确定性，不能丢弃其他不确定输入")
    for s in commitment["scenarios"]
        rt = s["case"]["realtime"]
        all((rt["alpha_up"] .== 0) .| (rt["alpha_down"] .== 0)) ||
            error("有符号调用不能表示同时上下调用；该训练输入未被本操作支持")
    end
    v = validate_r5_risk(c, r)
    v["model_pass"] && v["risk_pass"] && v["cost_pass"] ||
        error("训练候选未通过原模型/风险/费用检查")
    template = deepcopy(first(commitment["scenarios"])["case"])
    template["name"] = "r9_locked_recourse_template"
    template["award"]["origin"] = "synthetic"
    for k in R5_COMMITMENT_KEYS
        template["award"][k] = copy(r["first_stage"][k])
    end
    for k in ("energy_price", "up_price", "down_price")
        template["award"][k] = copy(commitment["day_ahead"][k])
    end
    support = Dict{String,Any}[]
    for (i, s) in enumerate(commitment["scenarios"])
        pvs = filter(g -> g["kind"] == "PV" && g["p_max_MW"] > 0, s["case"]["devices"])
        isempty(pvs) && error("最近代表距离需要明确的正容量PV")
        fraction = first(pvs)["available_MW"] ./ first(pvs)["p_max_MW"]
        all(
            g -> all(
                isapprox.(g["available_MW"] ./ g["p_max_MW"], fraction; atol = 1e-12, rtol = 0),
            ),
            pvs,
        ) || error("PV比例不是共同天气输入")
        rt = s["case"]["realtime"]
        raw = Float64(r["z"][i])
        isfinite(raw) || error("训练分支非有限")
        push!(
            support,
            Dict(
                "id" => s["id"],
                "probability" => s["probability"],
                "pv_fraction" => fraction,
                "activation_signed" => rt["alpha_up"] - rt["alpha_down"],
                "raw_z" => raw,
                "label" => round(Int, raw),
            ),
        )
    end
    R9ReservePolicy(
        Dict(
            "schema" => "r9-reserve-policy-v1",
            "evaluation_version" => "r9_nearest_recourse_v1",
            "information" => "complete_trajectory",
            "currency" => r5_dispatch_currency(template),
            "template" => template,
            "temperature_domain" => deepcopy(d["temperature_domain"]),
            "support" => support,
            "training" => Dict(
                "run_id" => r["run_id"],
                "case_sha256" => c.sha256,
                "result_sha256" => r9_evaluation_hash(r),
                "scheme" => get(get(d, "r9_study", Dict()), "scheme", "analytic_fixture"),
                "cost_optimization_complete" => get(r, "cost_optimization_complete", false),
                "model_pass" => v["model_pass"],
                "risk_pass" => v["risk_pass"],
                "cost_pass" => v["cost_pass"],
            ),
        ),
    )
end

"""
    r9_reserve_support_label(policy, trajectory)

R9-OS2：以训练时冻结的RMS(PV, signed_call/2)距离选择最近整日代表；等距取原顺序最早者。
只继承该代表的已锁定舒适分支，不拟合测试数据，不继承有限支持概率保证。
"""
function r9_reserve_support_label(p::R9ReservePolicy, x::AbstractMatrix)
    r9_assert_policy(p)
    T = p.data["template"]["T"]
    size(x) == (2, T) &&
    all(isfinite, x) &&
    all(y->0<=y<=1, x[1, :]) &&
    all(y->-1<=y<=1, x[2, :]) || error("新日轨迹形状或范围错误")
    distances = [
        sqrt(
            sum(
                (x[1, t]-s["pv_fraction"][t])^2 + ((x[2, t]-s["activation_signed"][t])/2)^2 for
                t in 1:T
            )/(2T),
        ) for s in p.data["support"]
    ]
    i = argmin(distances)
    Dict(
        "index"=>i,
        "scenario_id"=>p.data["support"][i]["id"],
        "label"=>p.data["support"][i]["label"],
        "distance"=>distances[i],
        "all_distances"=>distances,
        "tie_rule"=>"first_in_frozen_order",
    )
end

"""
    r9_reserve_evaluation_day(policy, trajectory; id)

将2×T新日PV比例/有符号调用映射到固定成交的R5DispatchCase；只改变这两类不确定输入及记录名。
原温区、热历史、设备、负荷、价格、时间步和币种保持。R9-OS1/OS2；不求解或写文件。
"""
function r9_reserve_evaluation_day(p::R9ReservePolicy, x::AbstractMatrix; id::AbstractString)
    r9_reserve_support_label(p, x)
    isempty(strip(id)) && error("新日身份为空")
    d = deepcopy(p.data["template"])
    d["name"] = "r9-heldout-" * String(id)
    for g in d["devices"]
        g["kind"] == "PV" && (g["available_MW"] = g["p_max_MW"] .* x[1, :])
    end
    d["realtime"]["alpha_up"] = max.(x[2, :], 0.0)
    d["realtime"]["alpha_down"] = max.(-x[2, :], 0.0)
    R5DispatchCase(d)
end
