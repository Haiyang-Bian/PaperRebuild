function r7_linked_master(c, s, pairs, optimizer, deadline, id)
    start=time()
    r=Dict{String,Any}(
        "status"=>"budget_exhausted",
        "included"=>[Dict("event"=>p.event, "fault"=>p.fault) for p in pairs],
        "witnesses"=>Any[],
    )
    if time()<deadline
        try
            b=build_r7_linked_planning(c, s; optimizer, included = pairs, deadline)
            r["model_class"]=b.model_class
            r["build_sec"]=time()-start
            if time()<deadline
                set_silent(b.model)
                set_time_limit_sec(b.model, deadline-time())
                optimize!(b.model)
                ts, pr=termination_status(b.model), primal_status(b.model)
                r["termination_status"], r["primal_status"]=string(ts), string(pr)
                r["solver_name"], r["raw_status"]=solver_name(b.model), raw_status(b.model)
                try
                    r["solver_version"]=MOI.get(backend(b.model), MOI.SolverVersion())
                catch err
                    r["solver_version_unavailable"]=sprint(showerror, err)
                end
                r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                            ts==MOI.TIME_LIMIT ? "time_limit_no_solution" :
                            "solver_"*lowercase(string(ts))
                if has_values(b.model)&&pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                    r["normal"]=Dict{String,Any}(
                        "schema"=>"r7-normal-result-v1",
                        "version"=>"r7_normal_prescribed_v1",
                        "run_id"=>id,
                        "case_sha256"=>c.normal.sha256,
                        "objective_kind"=>"expected_normal_cost_USD",
                        "thermal_model"=>c.normal.data["thermal_model"],
                        "full_preplan_optimality_verified"=>false,
                        "status"=>"candidate",
                        "values"=>Dict(k=>r7_pack(value.(a)) for (k, a) in b.normal_variables),
                        "chp_values"=>Dict(
                            g=>Dict(k=>r7_pack(value.(a)) for (k, a) in block) for
                            (g, block) in b.chp_variables
                        ),
                        "solver_objective_USD"=>objective_value(b.model),
                    )
                    r["witnesses"]=[
                        Dict(
                            "event"=>w.pair.event,
                            "fault"=>w.pair.fault,
                            "objective_kind"=>"recovery_feasibility_witness",
                            "witness_loss_MWh"=>value(w.loss),
                            "values"=>Dict(k=>r7_pack(value.(a)) for (k, a) in w.variables),
                            "thermal_values"=>Dict(
                                k=>r7_pack(value.(a)) for (k, a) in w.thermal_variables
                            ),
                            "normal_inlets"=>Dict(
                                "$a/$side/$j"=>value.(v) for ((a, side, j), v) in w.prefix
                            ),
                        ) for w in b.recovery
                    ]
                end
                try
                    lb=objective_bound(b.model)
                    isfinite(lb) ? (r["lower_bound_USD"]=lb) : (r["bound_unavailable"]="nonfinite")
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            r["error"]=sprint(showerror, err)
            r["status"]=occursin("linked_build_deadline", r["error"]) ? "budget_exhausted" :
                        occursin("licen", lowercase(r["error"])) ? "license_unavailable" :
                        "solver_or_build_error"
        end
    end
    r["elapsed_sec"]=time()-start
    r
end

"""
    solve_r7_linked_planning(case, spec; optimizer, method=:finite_fault_ccg, budget_sec=600)

R7-L2/L3详细热状态的条件安全规划。extensive纳入全部故障；finite_fault_ccg从正常模型开始，
逐故障重新优化详细恢复，仅认证的超门槛/不可行反例进入共同主问题。旧轮事件证据不复用。
建模、外层、子问题与验证共享600秒以内预算；负结果和未决分别保留，不自动改温区/门槛/流量。
不调用旧双水箱内层对偶，不声称完整变流量算法；每个候选须通过同一正常空间状态的独立回放。
"""
function solve_r7_linked_planning(
    c::R7PlanningCase,
    s;
    optimizer,
    method = :finite_fault_ccg,
    budget_sec = 600.0,
)
    started=time()
    r7_linked_spec_check(c, s)
    method in (:extensive, :finite_fault_ccg) || error("详细热规划方法未实现")
    isfinite(budget_sec)&&0<=budget_sec<=600 || error("详细热规划预算须在0至600秒")
    deadline=started+budget_sec
    r=Dict{String,Any}(
        "schema"=>"r7-linked-planning-result-v1",
        "version"=>s["version"],
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "run_id"=>"r7-linked-"*string(uuid4()),
        "objective_kind"=>"expected_normal_cost_USD",
        "method"=>string(method),
        "full_variable_flow_verified"=>false,
        "source_hashes_at_solve"=>r7_linked_science_hashes(),
        "julia_version"=>string(VERSION),
        "utc"=>string(now(UTC)),
        "budget_sec"=>Float64(budget_sec),
        "status"=>"budget_exhausted",
        "iterations"=>Any[],
    )
    allpairs=r7_planning_pairs(c)
    pairs=method==:extensive ? copy(allpairs) : eltype(allpairs)[]
    for k in 1:(length(allpairs)+1)
        time()<deadline || break
        m=r7_linked_master(c, s, pairs, optimizer, deadline, r["run_id"]*"_normal_$k")
        it=Dict{String,Any}("master"=>m, "audits"=>Any[], "added_pairs"=>Any[])
        push!(r["iterations"], it)
        if !haskey(m, "normal")
            r["status"]=m["status"]
            break
        end
        try
            q=r7_linked_master_check(c, s, m)
            if !(q["normal_pass"]&&q["included_pass"])
                r["status"]="master_validation_failed"
                break
            end
            if method==:extensive
                r["status"]="robust_candidate"
                break
            end
            for p in allpairs
                time()<deadline || break
                ev=r7_linked_event(c, s, m["normal"], p)
                run=solve_r7_transport_recovery(
                    ev.case,
                    p.fault,
                    ev.spec;
                    optimizer,
                    budget_sec = max(0, deadline-time()),
                    deadline,
                )
                push!(
                    it["audits"],
                    Dict(
                        "event"=>p.event,
                        "fault"=>p.fault,
                        "event_evidence"=>ev.evidence,
                        "result"=>run,
                    ),
                )
            end
            checks=[
                r7_linked_audit_check(c, s, m["normal"], a, allpairs[i]) for
                (i, a) in enumerate(it["audits"])
            ]
            if length(checks)==length(allpairs)&&all(q["safe"] for q in checks)
                r["status"]="robust_candidate"
                break
            end
            existing=Set(r7_planning_pair_key.(pairs))
            for (i, q) in enumerate(checks)
                q["violating"] || continue
                p=allpairs[i]
                if q["key"] in existing
                    r["status"]="oracle_master_conflict"
                    break
                end
                push!(pairs, p)
                push!(existing, q["key"])
                push!(it["added_pairs"], Dict("event"=>p.event, "fault"=>p.fault))
            end
            r["status"]=="oracle_master_conflict" && break
            if isempty(it["added_pairs"])
                r["status"]=time()>=deadline ? "budget_exhausted" : "oracle_unresolved"
                break
            end
        catch err
            r["status"]="state_or_validation_error"
            r["error"]=sprint(showerror, err)
            break
        end
    end
    r["validation"]=validate_r7_linked_planning(c, s, r)
    r["candidate_accepted"]=r["validation"]["robust_model_pass"]
    r["conditional_cost_complete"]=r["validation"]["conditional_optimality_pass"]
    r["elapsed_sec"]=time()-started
    r
end
