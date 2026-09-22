const R6_METHOD_CORE_FILE = @__FILE__

"""
    R6PhysicalCase(data)

R6共用24小时设备、市场、热历史及室温物理域，项目版本r6-physical-case-v1。
内嵌R5DispatchCase与市场模板；不含训练/测试轨迹，不按优化结果调整容量。
保留第5章线性电网、固定流量热输运及完整未来轨迹补救边界，不能称交流/水力认证。
对应R6-M1；测试R6-PHYSICAL。构造不抽样、不求解、不写文件。
"""
struct R6PhysicalCase
    data::Dict{String,Any}
    sha256::String
end

function R6PhysicalCase(input::AbstractDict)
    d = deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"] == "r6-physical-case-v1" || error("R6物理模板版本错误")
    d["origin"] == "synthetic" || error("当前24小时模板须明确为合成输入")
    dispatch = R5DispatchCase(d["dispatch"])
    T, dt = dispatch.data["T"], dispatch.data["dt_h"]
    abs(T*dt-24)<=1e-12 || error("物理模板必须覆盖24小时")
    # 通过已有完整输入契约验证共同边界；该名义零轨迹不作为正式训练样本。
    risk = Dict{String,Any}(
        "schema"=>"r5-risk-case-v1",
        "name"=>d["name"],
        "origin"=>d["origin"],
        "objective"=>"worst_expected_net_cost",
        "event"=>"any_building_time_comfort_violation",
        "epsilon"=>0.0,
        "temperature_domain"=>d["temperature_domain"],
        "ambiguity"=>Dict(
            "support"=>"fixed_scenarios",
            "distance_unit"=>"normalized_trajectory",
            "distance_provenance"=>"R6 physical input validation only",
            "distance"=>[[0.0]],
            "radius"=>0.0,
        ),
        "commitment"=>Dict(
            "schema"=>"r5-commitment-case-v1",
            "name"=>d["name"],
            "origin"=>d["origin"],
            "objective"=>"expected_net_cost",
            "comfort"=>"hard_each_scenario",
            "recourse_information"=>"complete_trajectory",
            "bounds"=>d["bounds"],
            "day_ahead"=>Dict(k=>zeros(T) for k in ("energy_price", "up_price", "down_price")),
            "uncertain_fields"=>[
                "devices.available_MW",
                "realtime.alpha_up",
                "realtime.alpha_down",
            ],
            "scenarios"=>[Dict("id"=>"nominal", "probability"=>1.0, "case"=>dispatch.data)],
        ),
    )
    probe = R5StrategicCase(
        Dict(
            "schema"=>"r5-strategic-case-v1",
            "name"=>d["name"],
            "origin"=>d["origin"],
            "selection"=>d["selection"],
            "quantity_rule"=>"fixed_offer_capacities",
            "leader_id"=>d["leader_id"],
            "market"=>d["market"],
            "bid_bounds"=>d["bid_bounds"],
            "risk"=>risk,
        ),
    )
    d["dispatch"] = dispatch.data
    d["market"] = probe.data["market"]
    d["bounds"] = probe.data["risk"]["commitment"]["bounds"]
    d["bid_bounds"] = probe.data["bid_bounds"]
    any(a["kind"]=="PV" for a in dispatch.data["devices"]) || error("PV轨迹缺少对应设备")
    all(a["p_min_MW"]==0 for a in dispatch.data["devices"] if a["kind"]=="PV") ||
        error("夜间零出力要求PV最小功率为零")
    R6PhysicalCase(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r6_physical_case(path)

读取独立冻结的24小时物理/市场模板，核验单位、历史、共同容量、报价界及温度域。
不读取测试轨迹，不运行优化；物理模板哈希与轨迹哈希分别保存。
"""
load_r6_physical_case(path::AbstractString) = R6PhysicalCase(TOML.parsefile(path))
r6_assert_physical(c) =
    bytes2hex(sha256(r5_market_text(c.data)))==c.sha256 || error("R6物理模板被修改")

"""
    R6MethodSpec(method; radius=0.0, epsilon=0.05)

六方法的共同语义：D为训练均值PV/零调用，SP为经验期望/硬舒适，RO为有限支持最坏费用/硬舒适，
DRO为运输球最坏费用/硬舒适，CCP为经验期望/联合机会约束，DRJCC为运输球费用/联合机会约束。
只有DRO/DRJCC可传非零radius；epsilon是机会约束的整日上限，不是小时比例。
R6-M2/M3是明确的项目采用解释；RO仅覆盖冻结支持，不保证连续未知轨迹。
"""
struct R6MethodSpec
    data::Dict{String,Any}
    sha256::String
end

function R6MethodSpec(method::AbstractString; radius = 0.0, epsilon = 0.05)
    method in R6_METHODS || error("未知R6方法")
    isfinite(radius) && radius>=0 || error("半径须有限非负")
    isfinite(epsilon) && 0<=epsilon<=1 || error("风险上限错误")
    method in ("DRO", "DRJCC") || iszero(radius) || error("该方法不接受运输球半径")
    d = Dict{String,Any}(
        "schema"=>"r6-method-v1",
        "method"=>String(method),
        "radius"=>Float64(radius),
        "epsilon"=>Float64(epsilon),
        "deterministic_rule"=>"training_mean_pv_zero_call",
        "cost_rule"=>method in ("D", "SP", "CCP") ? "empirical_expectation" :
                     method=="RO" ? "finite_support_maximum" : "transport_ball_worst_expectation",
        "comfort_rule"=>method in ("CCP", "DRJCC") ? "joint_chance" : "hard_all_support",
    )
    R6MethodSpec(d, bytes2hex(sha256(r5_market_text(d))))
end
r6_assert_method(s) = bytes2hex(sha256(r5_market_text(s.data)))==s.sha256 || error("方法规则被修改")
