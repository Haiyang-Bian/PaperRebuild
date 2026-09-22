const R6_METHOD_ALGORITHM_FILE = @__FILE__

"""
    r6_dispatch_day(physical, trajectory; id)

将通道×时段的无量纲完整日映射为R5物理输入；PV按额定MW乘比例，
正调用变alpha_up、负调用的绝对值变alpha_down，逐时互斥(R6-M1)。
只改变PV可用量、调用与名称，历史/初末规则保持；模板award为占位，不是优化成交。
"""
function r6_dispatch_day(c::R6PhysicalCase, v::AbstractMatrix; id::AbstractString)
    r6_assert_physical(c)
    T=c.data["dispatch"]["T"]
    size(v)==(2, T) && all(isfinite, v) || error("日轨迹形状或有限性错误")
    all(x->0<=x<=1, v[1, :]) && all(x->-1<=x<=1, v[2, :]) || error("日轨迹比例越界")
    occursin(r"^[A-Za-z0-9_-]+$", id) || error("日轨迹ID错误")
    d=deepcopy(c.data["dispatch"])
    d["name"]=String(id)
    for a in d["devices"]
        a["kind"]=="PV" && (a["available_MW"]=a["p_max_MW"] .* v[1, :])
    end
    d["realtime"]["alpha_up"]=max.(v[2, :], 0.0)
    d["realtime"]["alpha_down"]=max.(-v[2, :], 0.0)
    R5DispatchCase(d)
end

"""
    r6_training_case(physical, protocol, training, representatives, method;
                     development_count=nothing)

仅用train构造六方法的连续策略报价R5StrategicCase；默认使用全部冻结代表。
development_count显式截取最先的代表并条件归一原簇权重，仅用于开发耗时，不能冒充正式比较。
D取全部训练日的平均PV和零调用。RO以距离最大值覆盖有限支持单纯形(R6-M3)。
共同市场、容量、历史、价格、终端完全相同；方法、父输入和支持选择写入哈希来源链。
"""
function r6_training_case(
    c::R6PhysicalCase,
    p::R6Protocol,
    s::R6TrajectorySet,
    reps,
    spec::R6MethodSpec;
    development_count = nothing,
)
    r6_assert_physical(c)
    r6_assert_protocol(p)
    r6_assert_set(s)
    r6_assert_method(spec)
    s.split=="train" && s.protocol_sha256==p.sha256 || error("训练接口禁止验证/测试分组")
    size(s.values, 2)==p.data["T"]==c.data["dispatch"]["T"] &&
    p.data["dt_h"]==c.data["dispatch"]["dt_h"] || error("轨迹和物理时域不一致")
    length(s.ids)==p.data["samples"]["train"] || error("训练分组不完整")
    spec.data["epsilon"]==p.data["statistics"]["epsilon"] || error("方法风险目标与预声明协议不同")
    # 全量重算聚类身份/权重，防止把验证集选出的支持或人为概率伪装为冻结代表。
    r6_fit_representatives(s, p)==reps && reps["converged"] || error("训练代表不符合冻结聚类")
    n=length(reps["representative_indices"])
    if development_count!==nothing
        development_count isa Integer && 1<=development_count<=n || error("开发代表数量错误")
        n=Int(development_count)
    end
    ids=Int.(reps["representative_indices"][1:n])
    probabilities=Float64.(reps["probabilities"][1:n])
    mass=sum(probabilities)
    development_count===nothing || (probabilities ./= mass)
    D=r6_support_distance(s, reps)[1:n, 1:n]
    all(i==j || D[i, j]>0 for i in 1:n, j in 1:n) ||
        error("重复支持点须另行声明合并规则；不能将零距离运输当唯一经验分布")
    method=spec.data["method"]
    if method=="D"
        day=zeros(2, p.data["T"])
        day[1, :]=vec(sum(s.values[1, :, :]; dims = 2))/length(s.ids)
        scenarios=[
            Dict(
                "id"=>"training_mean_zero_call",
                "probability"=>1.0,
                "case"=>r6_dispatch_day(c, day; id = "training_mean_zero_call").data,
            ),
        ]
        D=zeros(1, 1)
    else
        scenarios=[
            Dict(
                "id"=>s.ids[i],
                "probability"=>probabilities[j],
                "case"=>r6_dispatch_day(c, s.values[:, :, i]; id = s.ids[i]).data,
            ) for (j, i) in enumerate(ids)
        ]
    end
    radius=method=="RO" ? maximum(D) : spec.data["radius"]
    epsilon=method in ("CCP", "DRJCC") ? spec.data["epsilon"] : 0.0
    T=p.data["T"]
    risk=Dict{String,Any}(
        "schema"=>"r5-risk-case-v1",
        "name"=>c.data["name"]*"_"*method,
        "origin"=>"synthetic",
        "objective"=>"worst_expected_net_cost",
        "event"=>"any_building_time_comfort_violation",
        "epsilon"=>epsilon,
        "temperature_domain"=>deepcopy(c.data["temperature_domain"]),
        "ambiguity"=>Dict(
            "support"=>"fixed_scenarios",
            "distance_unit"=>"normalized_trajectory",
            "distance_provenance"=>"R6-S6 full PV/signed-call day RMS; RO uses maximum distance (R6-M3)",
            "distance"=>[collect(D[i, :]) for i in axes(D, 1)],
            "radius"=>radius,
        ),
        "commitment"=>Dict(
            "schema"=>"r5-commitment-case-v1",
            "name"=>c.data["name"]*"_"*method,
            "origin"=>"synthetic",
            "objective"=>"expected_net_cost",
            "comfort"=>"hard_each_scenario",
            "recourse_information"=>"complete_trajectory",
            "uncertain_fields"=>[
                "devices.available_MW",
                "realtime.alpha_up",
                "realtime.alpha_down",
            ],
            "bounds"=>deepcopy(c.data["bounds"]),
            "day_ahead"=>Dict(k=>zeros(T) for k in ("energy_price", "up_price", "down_price")),
            "scenarios"=>scenarios,
        ),
    )
    meta=Dict{String,Any}(
        "schema"=>"r6-training-provenance-v1",
        "physical_sha256"=>c.sha256,
        "protocol_sha256"=>p.sha256,
        "training_sha256"=>s.sha256,
        "representatives_sha256"=>bytes2hex(sha256(r5_market_text(reps))),
        "method"=>deepcopy(spec.data),
        "method_sha256"=>spec.sha256,
        "scope"=>development_count===nothing ? "full_training_support" : "development_subset",
        "selection_rule"=>method=="D" ? "all_training_mean_pv_zero_call" :
                          "first_representatives_in_frozen_order",
        "selected_training_ids"=>method=="D" ? copy(s.ids) : s.ids[ids],
        "selected_cluster_mass"=>method=="D" ? 1.0 : mass,
        "effective_radius"=>radius,
        "effective_epsilon"=>epsilon,
    )
    R5StrategicCase(
        Dict(
            "schema"=>"r5-strategic-case-v1",
            "name"=>c.data["name"]*"_"*method,
            "origin"=>"synthetic",
            "selection"=>c.data["selection"],
            "quantity_rule"=>"fixed_offer_capacities",
            "leader_id"=>c.data["leader_id"],
            "market"=>deepcopy(c.data["market"]),
            "bid_bounds"=>deepcopy(c.data["bid_bounds"]),
            "risk"=>risk,
            "provenance"=>Dict("r6"=>meta),
        ),
    )
end

function r6_training_pattern(c::R5StrategicCase)
    r5_strategic_assert_case(c)
    meta=c.data["provenance"]["r6"]
    meta["schema"]=="r6-training-provenance-v1" || error("不是R6训练模型")
    d=meta["method"]
    spec=R6MethodSpec(d["method"]; radius = d["radius"], epsilon = d["epsilon"])
    spec.data==d && spec.sha256==meta["method_sha256"] || error("方法声明失效")
    rc=c.data["risk"]
    D=r5_market_array(rc["ambiguity"]["distance"])
    rho=d["method"]=="RO" ? maximum(D) : d["radius"]
    eps=d["comfort_rule"]=="hard_all_support" ? 0.0 : d["epsilon"]
    rc["ambiguity"]["radius"]==rho==meta["effective_radius"] &&
    rc["epsilon"]==eps==meta["effective_epsilon"] || error("实际费用/风险模型与方法不符")
    if d["method"]=="D"
        length(rc["commitment"]["scenarios"])==1 || error("确定性模型不能包含多情景")
        rt=only(rc["commitment"]["scenarios"])["case"]["realtime"]
        all(iszero, vcat(rt["alpha_up"], rt["alpha_down"])) || error("D要求显式零调用")
    end
    d["comfort_rule"]=="hard_all_support" ? zeros(Int, length(rc["commitment"]["scenarios"])) :
    nothing
end

"""
    build_r6_model(training_case; optimizer=nothing, complementarity_pattern=nothing)

按R6方法声明构建同市场策略模型；硬舒适方法固定全部z=0，机会方法保留情景二进制量。
不求解、不写文件；返回已有建模对象及真实MOI类型。固定市场互补分支只认证该分支。
"""
function build_r6_model(c::R5StrategicCase; optimizer = nothing, complementarity_pattern = nothing)
    build_r5_strategic(c; optimizer, risk_pattern = r6_training_pattern(c), complementarity_pattern)
end

"""
    solve_r6_training(training_case; optimizer, oracle_optimizer, budget_sec=600)

执行已冻结R6训练模型，沿用策略求解的共享预算、独立市场/运输验证及失败分类。
返回可由save_r5_strategic_run保存的完整原值；这里只评价训练支持，不访问验证/测试集。
"""
function solve_r6_training(c::R5StrategicCase; optimizer, oracle_optimizer, budget_sec = 600.0)
    solve_r5_strategic(
        c;
        optimizer,
        oracle_optimizer,
        budget_sec,
        risk_pattern = r6_training_pattern(c),
    )
end
