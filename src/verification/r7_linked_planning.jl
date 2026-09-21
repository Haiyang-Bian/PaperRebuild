function r7_linked_witness(c, s, n, w)
    pair=(event = w["event"], fault = w["fault"])
    ev=r7_linked_event(c, s, n, pair)
    w["objective_kind"]=="recovery_feasibility_witness" || error("详细恢复见证目标错误")
    !haskey(w, "lower_bound_MWh") || error("存在性见证不能含失供下界")
    r=Dict{String,Any}(
        "schema"=>"r7-transport-result-v1",
        "version"=>ev.spec["version"],
        "case_sha256"=>ev.case.sha256,
        "spec_sha256"=>r7_digest(ev.spec),
        "fault"=>pair.fault,
        "objective_kind"=>r7_loss_objective_kind(ev.case.data),
        "status"=>"feasibility_witness",
        "values"=>w["values"],
        "thermal_values"=>w["thermal_values"],
        "solver_objective_MWh"=>w["witness_loss_MWh"],
    )
    q=validate_r7_transport_recovery(ev.case, ev.spec, r)
    H=c.specification["events"][pair.event]["event_start"]-1
    nv=Dict(side=>r7_unpack(n["values"], "τ_$side") for side in ("S", "R"))
    expected=Set(
        "$a/$side/$j" for a in eachindex(c.normal.data["heat"]["pipes"]) for side in ("S", "R") for
        j in eachindex(c.normal.data["probabilities"])
    )
    Set(keys(w["normal_inlets"]))==expected || error("灾前入口历史缺失或重复")
    residual=0.0
    for (a, p) in enumerate(c.normal.data["heat"]["pipes"]),
        side in ("S", "R"),
        j in eachindex(c.normal.data["probabilities"])

        x=w["normal_inlets"]["$a/$side/$j"]
        length(x)==H && all(isfinite, x) || error("灾前入口历史维度或有限性错误")
        node=p[side=="S" ? "from" : "to"]
        for t in 1:H
            residual=max(residual, abs(x[t]-nv[side][node, t, j]))
        end
    end
    limit=ev.case.data["loss_limit_MWh"]
    Dict(
        "key"=>r7_planning_pair_key(pair),
        "check"=>q,
        "prefix_residual_K"=>residual,
        "threshold_pass"=>q["model_pass"]&&residual<=1e-4&&q["loss_MWh"]<=limit+1e-6*(
            1+max(1, limit)
        ),
        "event_evidence_sha256"=>r7_digest(ev.evidence),
    )
end

function r7_linked_master_check(c, s, m)
    r7_check_currency_record(c.normal.data, m)
    out=Dict{String,Any}("normal_pass"=>false, "included_pass"=>false, "witness_checks"=>Any[])
    r7_currency_record!(out, c.normal.data)
    included=[r7_planning_pair_key((event = p["event"], fault = p["fault"])) for p in m["included"]]
    allowed=Set(r7_planning_pair_key.(r7_planning_pairs(c)))
    length(included)==length(unique(included)) && all(k->k in allowed, included) ||
        error("主问题故障集合错误")
    m["status"]=="infeasible_certified" &&
        get(m, "termination_status", "")!="INFEASIBLE" &&
        error("详细规划不可行缺终止证据")
    haskey(m, "normal") || return out
    m["status"] in ("candidate", "time_limit_with_solution") || error("主问题状态与原值冲突")
    n=m["normal"]
    !haskey(n, r7_money_key(c.normal.data, "lower_bound_USD")) || error("正常子记录混入安全费用界")
    q=validate_r7_normal(c.normal, n)
    out["normal_check"]=q
    out["normal_pass"]=q["model_pass"]&&q["pipe_reference_pass"]
    out["normal_pass"] || return out
    out[r7_money_key(c.normal.data, "cost_USD")]=q[r7_money_key(c.normal.data, "cost_USD")]
    checks=[r7_linked_witness(c, s, n, w) for w in m["witnesses"]]
    sort([w["key"] for w in checks])==sort(included) || error("详细恢复见证缺失或重复")
    out["witness_checks"]=checks
    out["included_pass"]=all(w["threshold_pass"] for w in checks)
    out
end

function r7_linked_audit_check(c, s, n, a, pair)
    a["event"]==pair.event && a["fault"]==pair.fault || error("故障审计顺序/身份错误")
    ev=r7_linked_event(c, s, n, pair)
    isequal(a["event_evidence"], ev.evidence) || error("详细事件未绑定本轮正常状态")
    r=a["result"]
    r["fault"]==pair.fault || error("审计使用了其他故障")
    q=validate_r7_transport_recovery(ev.case, ev.spec, r)
    isequal(q, r["validation"]) || error("详细故障原值与摘要不同")
    lb=r["status"]=="infeasible_certified" ? Inf : get(r, "lower_bound_MWh", 0.0)
    ub=q["model_pass"] ? q["loss_MWh"] : Inf
    if isnan(lb) || (isfinite(ub)&&lb>ub+1e-6*(1+abs(ub)))
        error("详细故障界矛盾")
    end
    limit=ev.case.data["loss_limit_MWh"]
    Dict(
        "key"=>r7_planning_pair_key(pair),
        "check"=>q,
        "lower_bound_MWh"=>lb,
        "upper_bound_MWh"=>ub,
        "safe"=>ub<=limit+1e-6*(1+max(1, limit)),
        "violating"=>lb>limit+1e-6*(1+max(1, limit)),
    )
end

"""
    validate_r7_linked_planning(case, spec, result)

R7-L3独立验算：从本轮正常原值重放完整空间状态，再逐故障检查设备、电网、逐管温度与失供。
同时核查历史连接、外层反例来源与费用/失供界的作用域。不会读取建模矩阵或调用优化器。
通过仅认证所声明流量与子步模型；不认证自由流量、水力、连续节点、交流电网或作者完整算法。
"""
function validate_r7_linked_planning(c::R7PlanningCase, s, r)
    r7_linked_spec_check(c, s)
    r7_check_currency_record(c.normal.data, r)
    r["schema"]==r7_money_schema(c.normal.data, "r7-linked-planning-result-v1") &&
    r["version"]==s["version"] &&
    r["case_sha256"]==c.sha256 &&
    r["spec_sha256"]==r7_digest(s) &&
    r["objective_kind"]==r7_normal_objective_kind(c.normal.data) &&
    r["method"] in ("extensive", "finite_fault_ccg") &&
    r["full_variable_flow_verified"]===false || error("详细规划身份/范围错误")
    out=Dict{String,Any}(
        "robust_model_pass"=>false,
        "conditional_optimality_pass"=>false,
        "substep_transport_verified"=>false,
        "full_variable_flow_verified"=>false,
        "continuous_node_dynamics_verified"=>false,
        "hydraulic_recovery_verified"=>false,
        "ac_grid_verified"=>false,
        "candidate_iteration"=>0,
        "iterations"=>Any[],
    )
    r7_currency_record!(out, c.normal.data)
    allpairs=r7_planning_pairs(c)
    allkeys=Set(r7_planning_pair_key.(allpairs))
    expected=Set{String}()
    lower, best=-Inf, Inf
    for (i, it) in enumerate(r["iterations"])
        m=it["master"]
        got=Set(
            r7_planning_pair_key((event = p["event"], fault = p["fault"])) for p in m["included"]
        )
        got==(r["method"]=="extensive" ? allkeys : expected) || error("详细规划外层递推错误")
        q=r7_linked_master_check(c, s, m)
        if haskey(m, r7_money_key(c.normal.data, "lower_bound_USD"))
            isfinite(m[r7_money_key(c.normal.data, "lower_bound_USD")]) ||
                error("详细规划费用界非有限")
            lower=max(lower, m[r7_money_key(c.normal.data, "lower_bound_USD")])
        end
        audits=Any[]
        robust=false
        if q["normal_pass"]&&q["included_pass"]
            if r["method"]=="extensive"
                isempty(it["audits"]) || error("全量参考混入外层审计")
                robust=true
            else
                length(it["audits"])<=length(allpairs) || error("故障审计过多")
                for (k, a) in enumerate(it["audits"])
                    push!(audits, r7_linked_audit_check(c, s, m["normal"], a, allpairs[k]))
                end
                robust=length(audits)==length(allpairs)&&all(a["safe"] for a in audits)
            end
            if robust&&q[r7_money_key(c.normal.data, "cost_USD")]<best
                best=q[r7_money_key(c.normal.data, "cost_USD")]
                out["candidate_iteration"]=i
            end
        elseif !isempty(it["audits"])
            error("不合格正常计划带有故障证书")
        end
        bad=Set(a["key"] for a in audits if a["violating"])
        for p in it["added_pairs"]
            key=r7_planning_pair_key((event = p["event"], fault = p["fault"]))
            key in bad && !(key in expected) || error("未认证或重复故障加入主问题")
            push!(expected, key)
        end
        push!(out["iterations"], Dict("master"=>q, "audits"=>audits, "robust_model_pass"=>robust))
    end
    r["status"]=="infeasible_certified" &&
        !any(it["master"]["status"]=="infeasible_certified" for it in r["iterations"]) &&
        error("详细规划总状态缺不可行证据")
    out["robust_model_pass"]=isfinite(best)
    out["substep_transport_verified"]=isfinite(best)
    isfinite(lower)&&(out[r7_money_key(c.normal.data, "lower_bound_USD")]=lower)
    if isfinite(best)
        out[r7_money_key(c.normal.data, "cost_USD")]=best
        if isfinite(lower)
            gap=(best-lower)/max(1, abs(best))
            out["relative_gap"]=gap
            out["conditional_optimality_pass"]=-1e-6<=gap<=1e-4
        end
    end
    out
end
