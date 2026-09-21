"""
    validate_r9_detailed_preplan(case, spec, result)

R9-DP3：由保存的正常入口轨迹重新生成完整空间管温，独立回放每个详细恢复见证。
另行重算正常费用、事件最大失供、罚费与总目标。恢复见证没有独立失供最优下界。
通过只认证声明子步、零容积混合节点和给定流量；不扩大到交流电网、完整水力或全部故障。
"""
function validate_r9_detailed_preplan(c::R7PlanningCase, s, r)
    carrier = r9_detailed_preplan_check(c, s)
    base = s["base_spec"]
    r["schema"] == "r9-detailed-preplan-result-v1" &&
    r["version"] == s["version"] &&
    r["case_sha256"] == c.sha256 &&
    r["normal_sha256"] == c.normal.sha256 &&
    r["spec_sha256"] == r7_digest(s) &&
    r["carrier_sha256"] == carrier.sha256 &&
    r["currency"] == base["currency"] &&
    r["objective_kind"] == r9_preplan_objective(base) &&
    r["independent_recovery_performed"] === false &&
    r["full_thesis_domain_verified"] === false || error("详细灾前结果身份或证据范围错误")
    selected = r9_preplan_pairs(base)
    allpairs = r7_planning_pairs(c)
    q = Dict{String,Any}(
        "model_pass" => false,
        "objective_pass" => false,
        "objective_optimality_pass" => false,
        "detailed_disaster_heat_verified" => false,
        "selected_threshold_witness_pass" => false,
        "whole_fault_threshold_witness_pass" => false,
        "selected_fault_pairs" => length(selected),
        "whole_fault_pairs" => length(allpairs),
        "subset_covers_whole_faults" =>
            Set(r7_planning_pair_key.(selected)) == Set(r7_planning_pair_key.(allpairs)),
        "independent_recovery_performed" => false,
        "full_thesis_domain_verified" => false,
        "currency" => base["currency"],
    )
    r["status"] == "infeasible_certified" &&
        get(r, "termination_status", "") != "INFEASIBLE" &&
        error("不可行缺少原终止证据")
    haskey(r, "master") || return q
    r["status"] in ("candidate", "time_limit_with_solution") || error("失败状态混入候选")
    m = r["master"]
    m["status"] == r["status"] || error("主记录状态失步")
    expected = base["mode"] == "economic" ? Any[] : base["pairs"]
    isequal(m["included"], expected) || error("详细记录并非声明故障子集")
    check = r7_linked_master_check(carrier, s["linked_spec"], m)
    q["master_check"] = check
    check["normal_pass"] || return q
    worst = zeros(length(c.specification["events"]))
    threshold = true
    for (w, v) in zip(m["witnesses"], check["witness_checks"])
        loss = v["check"]["loss_MWh"]
        worst[w["event"]] = max(worst[w["event"]], loss)
        limit = base["limits_MWh"][w["event"]]
        threshold &= v["threshold_pass"] && loss <= limit + 1e-6 * (1 + max(1, limit))
    end
    cost = check[r7_money_key(c.normal.data, "cost_USD")]
    ζ = Float64.(r["epigraph_MWh"])
    caps = r8_loss_caps(c)
    if base["mode"] == "penalty"
        length(ζ) == length(caps) && all(isfinite, ζ) || error("最坏失供上图值非法")
        q["epigraph_pass"] = all(
            -1e-6 * (1 + max(1, cap)) <= z <= cap + 1e-6 * (1 + max(1, cap)) &&
                z + 1e-6 * (1 + max(1, cap)) >= v for (z, v, cap) in zip(ζ, worst, caps)
        )
        q["epigraph_slack_MWh"] = ζ - worst
    else
        isempty(ζ) || error("非罚费模式不能带上图变量")
        q["epigraph_pass"] = true
    end
    penalty = base["mode"] == "penalty" ? base["penalty_MWh"] * sum(ζ) : 0.0
    objective = cost + penalty
    q["normal_cost"], q["penalty_cost"], q["objective"] = cost, penalty, objective
    q["witness_worst_MWh"] = worst
    q["objective_residual"] = abs(r["solver_objective"] - objective)
    q["objective_pass"] =
        isfinite(r["solver_objective"]) && q["objective_residual"] <= 1e-6 * max(1, abs(objective))
    q["model_pass"] =
        check["normal_pass"] && check["included_pass"] && q["epigraph_pass"] && q["objective_pass"]
    q["detailed_disaster_heat_verified"] = q["model_pass"] && !isempty(m["witnesses"])
    q["selected_threshold_witness_pass"] = q["detailed_disaster_heat_verified"] && threshold
    q["whole_fault_threshold_witness_pass"] =
        q["selected_threshold_witness_pass"] && q["subset_covers_whole_faults"]
    if haskey(r, "objective_lower_bound")
        lb = r["objective_lower_bound"]
        isfinite(lb) || error("详细灾前目标下界非有限")
        gap = (objective - lb) / max(1, abs(objective))
        q["relative_gap"] = gap
        q["objective_optimality_pass"] = q["model_pass"] && -1e-6 <= gap <= 1e-4
    end
    q
end
