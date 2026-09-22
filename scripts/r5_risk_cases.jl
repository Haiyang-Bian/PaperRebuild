using PaperRebuild, TOML, SHA

# 全部规则在首次求解前构造；只读取旧输入，不读取旧最优解或费用。
function r5_risk_case(base; name, epsilon = 0.0, radius = 0.0)
    b=deepcopy(base)
    n=length(b["scenarios"])
    Dict{String,Any}(
        "schema"=>"r5-risk-case-v1",
        "name"=>name,
        "origin"=>"synthetic",
        "objective"=>"worst_expected_net_cost",
        "event"=>"any_building_time_comfort_violation",
        "epsilon"=>epsilon,
        "commitment"=>b,
        "ambiguity"=>Dict(
            "support"=>"fixed_scenarios",
            "radius"=>radius,
            "distance_unit"=>"normalized_trajectory",
            "distance_provenance"=>"Euclidean distance between one-hot labels of the three frozen full-call regimes, divided by sqrt(2); synthetic categorical trajectory metric, not calibrated from thesis samples.",
            "distance"=>[[i==j ? 0.0 : 1.0 for j in 1:n] for i in 1:n],
        ),
        "temperature_domain"=>Dict(
            x["id"]=>Dict("lower_K"=>x["T_min_K"]-1.0, "upper_K"=>x["T_max_K"]+1.0) for
            x in first(b["scenarios"])["case"]["buildings"]
        ),
    )
end

function r5_risk_inputs()
    root=normpath(joinpath(@__DIR__, "..", "configs", "r5", "commitment"))
    hand=TOML.parsefile(joinpath(root, "hand.toml"))
    quarter=TOML.parsefile(joinpath(root, "quarter.toml"))
    future=TOML.parsefile(joinpath(root, "four_period_future.toml"))
    cases=Dict{String,Any}()
    for (name, b, rho) in (
        ("hard_zero", hand, 0.0),
        ("quarter", quarter, 0.0),
        ("hard_r020", hand, 0.2),
        ("hard_r100", hand, 1.0),
    )
        cases[name]=r5_risk_case(b; name, radius = rho)
    end
    # 可手算热灵活性：0.1小时无损管延迟，源温固定，负荷回温有界；末端室温显式free。
    # 舒适界仍为293.15 K；所加物理域292.15..294.15 K，不改变设备/备用和初始热历史。
    thermal=deepcopy(hand)
    thermal["name"]="risk_thermal_hand"
    for s in thermal["scenarios"]
        s["case"]["heat"]["pipes"][1]["length_m"]=36.0
        b=s["case"]["buildings"][1]
        b["R_min_K"], b["R_max_K"], b["terminal_rule"]=303.15, 330.15, "free"
    end
    for (name, eps, rho) in (
        ("thermal_hard", 0.0, 0.0),
        ("thermal_e025_r000", 0.25, 0.0),
        ("thermal_e025_r005", 0.25, 0.05),
        ("thermal_e030_r005", 0.30, 0.05),
        ("thermal_e100_r000", 1.0, 0.0),
        ("thermal_e000_r005", 0.0, 0.05),
    )
        cases[name]=r5_risk_case(thermal; name, epsilon = eps, radius = rho)
    end
    for (name, eps, rho) in (("future_hard", 0.0, 0.0), ("future_e030_r005", 0.3, 0.05))
        cases[name]=r5_risk_case(future; name, epsilon = eps, radius = rho)
    end
    bad=deepcopy(thermal)
    for s in bad["scenarios"]
        s["case"]["electric"]["P_load_MW"][2]=[2.0]
    end
    cases["physical_infeasible"]=r5_risk_case(bad; name = "physical_infeasible", epsilon = 1.0)
    cases
end
