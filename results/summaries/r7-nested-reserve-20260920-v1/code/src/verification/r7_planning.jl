# 恢复块是可行性见证，不是失供最优化结果。适配器只调用既有独立数值验证，不提供失供下界。
function r7_planning_witness(c, w)
    r=Dict{String,Any}(
        "schema"=>"r7-recovery-result-v1",
        "version"=>"r7_recovery_checked_v1",
        "case_sha256"=>c.sha256,
        "preplan_id"=>c.data["preplan_id"],
        "preplan_optimality_verified"=>false,
        "objective_kind"=>"expected_unserved_energy_MWh",
        "fault"=>w["fault"],
        "status"=>"feasibility_witness",
        "values"=>w["values"],
        "solver_objective_MWh"=>w["witness_loss_MWh"],
    )
    validate_r7_recovery(c, r)
end

function r7_planning_event(c, n, s)
    e=c.specification["events"][s]
    r7_normal_event(
        c.normal,
        n;
        event_start = e["event_start"],
        periods = e["periods"],
        renewable_factor = e["renewable_factor"],
        loss_limit_MWh = e["loss_limit_MWh"],
    )
end

function r7_planning_master_check(c, m)
    out=Dict{String,Any}("normal_pass"=>false, "included_pass"=>false, "witness_checks"=>Any[])
    allowed=Set(r7_planning_pair_key(p) for p in r7_planning_pairs(c))
    included=[r7_planning_pair_key((event = p["event"], fault = p["fault"])) for p in m["included"]]
    length(included)==length(unique(included)) && all(k->k in allowed, included) ||
        error("主问题故障集合错误")
    haskey(m, "normal") || return out
    m["status"] in ("candidate", "time_limit_with_solution") || error("主问题状态与原值矛盾")
    n=m["normal"]
    # 主问题界属于安全规划，不能冒充无灾害正常调度的最优下界。
    !haskey(n, "lower_bound_USD") || error("正常子记录混入安全规划费用界")
    q=validate_r7_normal(c.normal, n)
    out["normal_check"]=q
    out["normal_pass"]=q["model_pass"]&&q["pipe_reference_pass"]
    out["normal_pass"] || return out
    out["cost_USD"]=q["cost_USD"]
    events=Any[]
    for s in eachindex(c.specification["events"])
        event=try
            r7_planning_event(c, n, s)
        catch err
            out["handoff_error"]=sprint(showerror, err)
            return out
        end
        push!(events, event)
    end
    keys=String[]
    for w in m["witnesses"]
        key=r7_planning_pair_key((event = w["event"], fault = w["fault"]))
        push!(keys, key)
        key in included || error("恢复见证不属于主问题")
        w["objective_kind"]=="recovery_feasibility_witness" || error("恢复见证目标类型被改写")
        event=events[w["event"]]
        v=r7_planning_witness(event.case, w)
        limit=event.case.data["loss_limit_MWh"]
        push!(
            out["witness_checks"],
            Dict(
                "key"=>key,
                "check"=>v,
                "threshold_pass"=>v["model_pass"]&&v["loss_MWh"]<=limit+1e-6*(1+max(1, limit)),
            ),
        )
    end
    sort(keys)==sort(included) || error("恢复见证缺失或重复")
    out["included_pass"]=all(v["threshold_pass"] for v in out["witness_checks"])
    out
end

# 每次重新从该轮正常原值构造事件。旧计划即使曾安全，也不能继承其安全证书。
function r7_planning_audit_check(c, n, s, a)
    event=r7_planning_event(c, n, s)
    isequal(a["event_evidence"], event.evidence) || error("事件证据未绑定当前正常计划")
    oracle=a["oracle"]
    ec=event.case
    oracle["case_sha256"]==ec.sha256 && oracle["preplan_id"]==ec.data["preplan_id"] ||
        error("故障审计父记录错误")
    if oracle["schema"]=="r7-adversary-result-v1"
        q=validate_r7_adversary(ec,oracle)
        isequal(q,oracle["validation"]) || error("内层故障对手摘要与原值不同")
        limit=ec.data["loss_limit_MWh"]
        bad=Any[]
        for it in oracle["iterations"]
            haskey(it,"recovery") || continue
            rec=it["recovery"]
            lb=rec["status"]=="infeasible_certified" ? Inf : get(rec,"lower_bound_MWh",0.0)
            lb>limit+1e-6*(1+max(1,limit)) && push!(bad,Dict("event"=>s,"fault"=>rec["fault"]))
        end
        return Dict("event"=>s,"status"=>q["threshold_status"],
            "lower_bound_MWh"=>q["lower_bound_MWh"],"upper_bound_MWh"=>q["upper_bound_MWh"],
            "violating_pairs"=>unique(bad))
    end
    faults=r7_faults(ec)
    runs=oracle["runs"]
    length(runs)<=length(faults) || error("故障记录过多")
    lower=0.0
    upper=0.0
    bad=Any[]
    for (k, r) in enumerate(runs)
        r["fault"]==faults[k] || error("故障漏项、重排或重复")
        q=validate_r7_recovery(ec, r)
        isequal(q, r["validation"]) && r["candidate_accepted"]==q["model_pass"] ||
            error("故障原值与摘要不同")
        lb=r["status"]=="infeasible_certified" ? Inf : get(r, "lower_bound_MWh", 0.0)
        ub=q["model_pass"] ? q["loss_MWh"] : Inf
        isnan(lb) && error("故障下界非数")
        isfinite(ub)&&lb>ub+1e-6*(1+abs(ub)) && error("故障上下界矛盾")
        lower=max(lower, lb)
        upper=max(upper, ub)
        limit=ec.data["loss_limit_MWh"]
        lb>limit+1e-6*(1+max(1, limit)) && push!(bad, Dict("event"=>s, "fault"=>r["fault"]))
    end
    complete=length(runs)==length(faults)
    complete || (upper=Inf)
    limit=ec.data["loss_limit_MWh"]
    status=upper<=limit+1e-6*(1+max(1, limit)) ? "safe_adopted_model" :
           lower>limit+1e-6*(1+max(1, limit)) ? "violation_certified" : "unresolved"
    oracle["expected_faults"]==length(faults) &&
    oracle["all_faults_attempted"]==complete &&
    oracle["status"]==status &&
    oracle["lower_bound_MWh"]==lower &&
    oracle["upper_bound_MWh"]==upper || error("故障界或安全标签失步")
    Dict(
        "event"=>s,
        "status"=>status,
        "lower_bound_MWh"=>lower,
        "upper_bound_MWh"=>upper,
        "violating_pairs"=>bad,
    )
end

"""
    validate_r7_planning(case, result)

独立回代共享正常轨迹、每个故障的恢复见证和逐轮事件证书。恢复损失界与正常费用界分开，
全故障存在合格恢复才认证本采用模型安全；成本认证限给定管流/固定正常电拓扑的有限故障域。
不将恢复可行性见证称为失供最优，也不认证详细灾后热网、交流潮流或作者完整算法。
"""
function validate_r7_planning(c::R7PlanningCase, r)
    r7_planning_assert(c)
    r["schema"]=="r7-planning-result-v1" &&
    r["case_sha256"]==c.sha256 &&
    r["normal_domain"]==c.specification["normal_domain"] &&
    r["objective_kind"]=="expected_normal_cost_USD" &&
    r["full_preplan_optimality_verified"]===false &&
    r["author_nested_algorithm_verified"]===false || error("规划身份或范围错误")
    r["method"] in ("extensive", "finite_fault_ccg", "nested_indicator_ccg") || error("规划方法错误")
    out=Dict{String,Any}(
        "robust_model_pass"=>false,
        "conditional_optimality_pass"=>false,
        "detailed_disaster_heat_verified"=>false,
        "ac_grid_verified"=>false,
        "iterations"=>Any[],
        "candidate_iteration"=>0,
    )
    allkeys=Set(r7_planning_pair_key(p) for p in r7_planning_pairs(c))
    expected=Set{String}()
    lower=-Inf
    best=Inf
    for (i, it) in enumerate(r["iterations"])
        m=it["master"]
        got=Set(
            r7_planning_pair_key((event = p["event"], fault = p["fault"])) for p in m["included"]
        )
        got==(r["method"]=="extensive" ? allkeys : expected) || error("外层故障递推错误")
        q=r7_planning_master_check(c, m)
        if haskey(m, "lower_bound_USD")
            isfinite(m["lower_bound_USD"]) || error("主问题费用界非有限")
            lower=max(lower, m["lower_bound_USD"])
        end
        audits=Any[]
        robust=false
        if q["normal_pass"]&&q["included_pass"]
            if r["method"]=="extensive"
                isempty(it["audits"]) || error("全故障参考不混入外层证书")
                robust=true
            else
                for (s, a) in enumerate(it["audits"])
                    s<=length(c.specification["events"]) || error("事件记录过多")
                    expected_schema=r["method"]=="nested_indicator_ccg" ?
                        "r7-adversary-result-v1" : "r7-fault-audit-v1"
                    a["oracle"]["schema"]==expected_schema || error("故障对手与声明方法不同")
                    push!(audits, r7_planning_audit_check(c, m["normal"], s, a))
                end
                robust=length(audits)==length(c.specification["events"]) &&
                       all(a["status"]=="safe_adopted_model" for a in audits)
            end
            if robust && q["cost_USD"]<best
                best=q["cost_USD"]
                out["candidate_iteration"]=i
            end
        elseif !isempty(it["audits"])
            error("不合格正常计划不应生成故障证书")
        end
        bad=Set(
            r7_planning_pair_key((event = p["event"], fault = p["fault"])) for a in audits for
            p in a["violating_pairs"]
        )
        added=String[]
        for p in it["added_pairs"]
            k=r7_planning_pair_key((event = p["event"], fault = p["fault"]))
            k in bad && !(k in expected) && !(k in added) || error("未认证或重复故障割")
            push!(added, k)
            push!(expected, k)
        end
        push!(out["iterations"], Dict("master"=>q, "audits"=>audits, "robust_model_pass"=>robust))
    end
    out["robust_model_pass"]=isfinite(best)
    if isfinite(lower)
        out["lower_bound_USD"]=lower
    end
    if isfinite(best)
        out["cost_USD"]=best
        if isfinite(lower)
            gap=(best-lower)/max(1, abs(best))
            out["relative_gap"]=gap
            out["conditional_optimality_pass"]=-1e-6<=gap<=1e-4
        end
    end
    out
end
