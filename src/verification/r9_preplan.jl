"""
    validate_r9_preplan(case, spec, result)

独立重算正常模型、连续输运、灾前状态继承、所选恢复见证与费用账本（R9-RP1至RP3）。
罚项由逐事件上图量计算，同时报告它与见证最大失供的差；见证不会取得失供最优下界。
费用最优性限声明子集和采用模型，精确热交换诊断保留，独立详细灾后恢复仍须另行执行。
"""
function validate_r9_preplan(c::R7PlanningCase, s, r)
    r9_preplan_check(c, s)
    carrier=r9_preplan_carrier(c, s)
    r["schema"]=="r9-preplan-result-v1" &&
    r["version"]==s["version"] &&
    r["case_sha256"]==c.sha256 &&
    r["normal_sha256"]==c.normal.sha256 &&
    r["spec_sha256"]==r7_digest(s) &&
    r["carrier_sha256"]==carrier.sha256 &&
    r["currency"]==s["currency"] &&
    r["objective_kind"]==r9_preplan_objective(s) &&
    r["independent_recovery_performed"]===false &&
    r["full_thesis_domain_verified"]===false || error("灾前结果身份、目标或证据范围错误")
    selected=r9_preplan_pairs(s)
    allpairs=r7_planning_pairs(c)
    q=Dict{String,Any}(
        "model_pass"=>false,
        "objective_pass"=>false,
        "objective_optimality_pass"=>false,
        "selected_threshold_witness_pass"=>false,
        "whole_fault_threshold_witness_pass"=>false,
        "selected_fault_pairs"=>length(selected),
        "whole_fault_pairs"=>length(allpairs),
        "subset_covers_whole_faults"=>Set(r7_planning_pair_key.(selected))==Set(
            r7_planning_pair_key.(allpairs),
        ),
        "normal_model_pass"=>false,
        "normal_pipe_reference_pass"=>false,
        "independent_recovery_performed"=>false,
        "detailed_disaster_heat_verified"=>false,
        "currency"=>s["currency"],
        "full_thesis_domain_verified"=>false,
    )
    haskey(r, "master") || return q
    r["status"] in ("candidate", "time_limit_with_solution") || error("灾前失败状态带有候选")
    m=r["master"]
    m["status"]==r["status"] || error("灾前主记录状态失步")
    expected=s["mode"]=="economic" ? Any[] : s["pairs"]
    isequal(m["included"], expected) || error("灾前记录并非声明故障子集")
    check=r7_planning_master_check(carrier, m)
    q["master_check"]=check
    q["normal_model_pass"]=get(get(check, "normal_check", Dict()), "model_pass", false)
    q["normal_pipe_reference_pass"]=get(
        get(check, "normal_check", Dict()),
        "pipe_reference_pass",
        false,
    )
    check["normal_pass"] || return q
    normalcost=check[r7_money_key(c.normal.data, "cost_USD")]
    worst=zeros(length(c.specification["events"]))
    threshold=true
    for (w, v) in zip(m["witnesses"], check["witness_checks"])
        loss=v["check"]["loss_MWh"]
        worst[w["event"]]=max(worst[w["event"]], loss)
        limit=s["limits_MWh"][w["event"]]
        threshold &= v["check"]["model_pass"] && loss<=limit+1e-6*(1+max(1, limit))
    end
    q["normal_cost"]=normalcost
    q["witness_worst_MWh"]=worst
    q["selected_threshold_witness_pass"]=!isempty(m["witnesses"]) && threshold
    q["whole_fault_threshold_witness_pass"]=q["selected_threshold_witness_pass"] &&
                                            q["subset_covers_whole_faults"]
    ζ=Float64.(r["epigraph_MWh"])
    caps=r8_loss_caps(c)
    if s["mode"]=="penalty"
        length(ζ)==length(caps) && all(isfinite, ζ) || error("最坏失供上图值形状错误")
        q["epigraph_pass"]=all(
            -1e-6*(1+max(1, cap))<=z<=cap+1e-6*(1+max(1, cap)) && z+1e-6*(1+max(1, cap))>=v for
            (z, v, cap) in zip(ζ, worst, caps)
        )
        q["epigraph_slack_MWh"]=ζ-worst
    else
        isempty(ζ) || error("非罚费模式不能带上图失供变量")
        q["epigraph_pass"]=true
    end
    penalty=s["mode"]=="penalty" ? s["penalty_MWh"]*sum(ζ) : 0.0
    objective=normalcost+penalty
    q["penalty_cost"], q["objective"]=penalty, objective
    q["objective_residual"]=abs(r["solver_objective"]-objective)
    q["objective_pass"]=isfinite(r["solver_objective"]) &&
                        q["objective_residual"]<=1e-6*max(1, abs(objective))
    q["model_pass"]=check["normal_pass"] &&
                    check["included_pass"] &&
                    q["epigraph_pass"] &&
                    q["objective_pass"]
    if haskey(r, "objective_lower_bound")
        lb=r["objective_lower_bound"]
        isfinite(lb) || error("灾前目标下界非有限")
        gap=(objective-lb)/max(1, abs(objective))
        q["relative_gap"]=gap
        q["objective_optimality_pass"]=q["model_pass"] && -1e-6<=gap<=1e-4
    end
    q
end
