"""
    R9ReserveStudySpec(data)

第7.4节三方案的冻结比较口径；不抽样、不求解、不写文件。
3A在有限支持上取最坏费用且不牺牲舒适，3B使用经验概率机会约束，3C加入概率运输球。
三者统一delta=0严格交付；epsilon只约束整日联合室温违约，不能与交付误差互换。
半径是预声明合成参数，未校准为统计置信半径；不认证任意未知调用或在线控制。
"""
struct R9ReserveStudySpec
    data::Dict{String,Any}
    sha256::String
end

function R9ReserveStudySpec(input::AbstractDict)
    d=deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"]=="r9-reserve-study-v1" &&
    d["origin"]=="synthetic" &&
    d["currency"]=="CNY" &&
    d["schemes"]==["3A", "3B", "3C"] || error("R9风险协议身份错误")
    !isempty(strip(d["id"])) && d["delivery_delta"]==0.0 && d["epsilon"]==0.05 ||
        error("主比较必须统一严格交付及5%联合舒适风险")
    isfinite(d["radius"]) && d["radius"]>0 || error("概率运输半径必须显式为正")
    d["support_count"]==100 && d["pilot_count"]==4 || error("正式/预运行情景数不符")
    for (key, value) in (
        "recourse_information"=>"complete_trajectory",
        "guarantee_scope"=>"finite_frozen_support_only_not_all_24h_calls",
        "uncertainty"=>"synthetic_correlated_PV_and_signed_reserve_call",
        "radius_rule"=>"predeclared_sensitivity_parameter_not_statistical_confidence_radius",
        "radius_selection"=>"none_no_validation_or_test_tuning",
        "pilot_rule"=>"first_four_frozen_representatives_renormalize_training_frequencies",
        "reserve_bound_rule"=>"sum_device_electric_ranges_plus_local_P2H_nameplates",
        "test_policy"=>"nearest_frozen_representative_comfort_branch_full_trajectory_recourse",
        "test_gate"=>"lock_all_training_candidates_before_out_of_sample_optimization",
        "source_policy"=>"freeze_exact_source_and_input_before_first_solve_commit_at_checkpoint",
        "solver"=>"gurobi",
        "oracle_solver"=>"highs",
    )
        d[key]==value || error("未知R9风险规则: $key")
    end
    isfinite(d["budget_sec"]) &&
    d["budget_sec"]==600.0 &&
    isfinite(d["archive_reserve_sec"]) &&
    0<d["archive_reserve_sec"]<d["budget_sec"] || error("完整方法预算或存档预留非法")
    R9ReserveStudySpec(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r9_reserve_study(path)

读取第7.4节三方案、共同交付约束、有限支持风险与运行预算；不运行实验。
"""
load_r9_reserve_study(path::AbstractString) = R9ReserveStudySpec(TOML.parsefile(path))

"""
    r9_reserve_risk_case(template, training, representatives, spec, scheme; pilot=false)

将独立冻结的训练代表轨迹迁入44电/38热节点人民币模型，返回R5RiskCase。
只读取train；调用正号为上调，PV比例乘各自铭牌，设备/热历史/边界不随情景改变。
3A运输半径取支持直径，等价于支持上任意概率分布；3B半径0，3C使用冻结半径。
pilot仅取前四代表并显式重标训练频数，不能解释为100情景或5%收益实验。
对应项目式R9-RK1至R9-RK4；原始模板、训练集与代表记录保持不变。
"""
function r9_reserve_risk_case(
    template::R5DispatchCase,
    training::R6TrajectorySet,
    reps,
    spec::R9ReserveStudySpec,
    scheme::AbstractString;
    pilot = false,
)
    s=spec.data
    bytes2hex(sha256(r5_market_text(s)))==spec.sha256 || error("研究协议已改变")
    r6_assert_set(training)
    training.split=="train" &&
    reps["fitted_split"]=="train" &&
    reps["training_sha256"]==training.sha256 &&
    reps["protocol_sha256"]==training.protocol_sha256 &&
    reps["converged"] || error("只允许冻结训练代表")
    scheme in s["schemes"] || error("方案不支持")
    audit_r9_reserve_input(template)["reference_pass"] || error("原模板初始参考不合格")
    td=template.data
    td["currency"]==s["currency"] && td["T"]==size(training.values, 2)==24 || error("币种/时域不符")
    length(reps["counts"])==s["support_count"] &&
    all(>(0), reps["counts"]) &&
    sum(reps["counts"])==length(training.ids) &&
    length(reps["representative_indices"])==s["support_count"] || error("训练代表频数不符")
    probs=Float64.(reps["counts"]) ./ length(training.ids)
    probs==reps["probabilities"] || error("代表概率不是训练频数")
    distance=r6_support_distance(training, reps)
    count=pilot ? s["pilot_count"] : s["support_count"]
    positions=1:count
    weights=probs[positions]
    pilot && (weights=weights ./ sum(weights)) # 正式保留训练频数；预运行明确为条件支持。
    D=distance[positions, positions]
    rho=scheme=="3A" ? maximum(D) : scheme=="3B" ? 0.0 : s["radius"]
    # 这是宽松铭牌盒；真正可交付备用仍受各情景电热关系限制，不能当灵活性认证。
    reserve_cap=sum(a["p_max_MW"]-a["p_min_MW"] for a in td["devices"]) +
                sum(b["P_DH_max_MW"] for b in td["buildings"])
    T=td["T"]
    scenarios=Dict{String,Any}[]
    for (j, pos) in enumerate(positions)
        i=reps["representative_indices"][pos]
        d=deepcopy(td)
        d["name"]=td["name"]*"-"*training.ids[i]
        for a in d["devices"]
            a["kind"]=="PV" && (a["available_MW"]=a["p_max_MW"] .* training.values[1, :, i])
        end
        d["realtime"]["alpha_up"]=max.(training.values[2, :, i], 0.0)
        d["realtime"]["alpha_down"]=max.(-training.values[2, :, i], 0.0)
        d["realtime"]["delta"]=s["delivery_delta"]
        push!(scenarios, Dict("id"=>training.ids[i], "probability"=>weights[j], "case"=>d))
    end
    commitment=Dict{String,Any}(
        "schema"=>"r5-commitment-case-v1",
        "name"=>s["id"]*"-"*scheme,
        "origin"=>"synthetic",
        "objective"=>"expected_net_cost",
        "comfort"=>"hard_each_scenario",
        "recourse_information"=>s["recourse_information"],
        "uncertain_fields"=>["devices.available_MW", "realtime.alpha_up", "realtime.alpha_down"],
        "scenarios"=>scenarios,
        "bounds"=>Dict(
            k=>Dict(
                "lower"=>zeros(T),
                "upper"=>fill(k=="P_DA_MW" ? td["electric"]["pcc_max_MW"] : reserve_cap, T),
            ) for k in R5_COMMITMENT_KEYS
        ),
        "day_ahead"=>Dict(
            k=>copy(td["award"][k]) for k in ("energy_price", "up_price", "down_price")
        ),
    )
    R5RiskCase(
        Dict{String,Any}(
            "schema"=>"r5-risk-case-v1",
            "name"=>s["id"]*"-"*scheme*(pilot ? "-pilot4" : "-full100"),
            "origin"=>"synthetic",
            "objective"=>"worst_expected_net_cost",
            "event"=>"any_building_time_comfort_violation",
            "epsilon"=>scheme=="3A" ? 0.0 : s["epsilon"],
            "commitment"=>commitment,
            "ambiguity"=>Dict(
                "support"=>"fixed_scenarios",
                "distance_unit"=>"normalized_trajectory",
                "distance_provenance"=>"Frozen training representative RMS(PV,signed_call/2); no held-out tuning",
                "distance"=>[collect(D[i, :]) for i in 1:count],
                "radius"=>rho,
            ),
            "temperature_domain"=>Dict(
                b["id"]=>Dict(
                    "lower_K"=>td["r9_reserve"]["protocol"]["building"]["physical_domain_K"][1],
                    "upper_K"=>td["r9_reserve"]["protocol"]["building"]["physical_domain_K"][2],
                ) for b in td["buildings"]
            ),
            "r9_study"=>Dict(
                "protocol"=>s,
                "protocol_sha256"=>spec.sha256,
                "scheme"=>scheme,
                "template_sha256"=>template.sha256,
                "training_sha256"=>training.sha256,
                "trajectory_protocol_sha256"=>training.protocol_sha256,
                "representatives_sha256"=>r9_hash(reps),
                "support_positions"=>collect(positions),
                "pilot"=>pilot,
                "reserve_bound_MW"=>reserve_cap,
                "original_input_reproduction"=>false,
                "continuous_call_guarantee"=>false,
                "delta_override"=>Dict("from"=>td["realtime"]["delta"], "to"=>s["delivery_delta"]),
            ),
        ),
    )
end
