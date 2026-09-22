function r7_solve_planning_master(c, pairs, optimizer, stop, id)
    started=time()
    r=Dict{String,Any}(
        "status"=>"budget_exhausted",
        "included"=>[Dict("event"=>p.event, "fault"=>p.fault) for p in pairs],
        "witnesses"=>Any[],
    )
    r7_currency_record!(r, c.normal.data)
    if started<stop
        try
            b=build_r7_planning(c; optimizer, included = pairs)
            r["model_class"]=b.model_class
            r["build_sec"]=time()-started
            if time()<stop
                set_silent(b.model)
                set_time_limit_sec(b.model, stop-time())
                optimize!(b.model)
                ts=termination_status(b.model)
                pr=primal_status(b.model)
                r["termination_status"]=string(ts)
                r["primal_status"]=string(pr)
                r["solver_name"]=solver_name(b.model)
                r["raw_status"]=raw_status(b.model)
                r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                            ts==MOI.TIME_LIMIT ? "time_limit_no_solution" :
                            "solver_"*lowercase(string(ts))
                if has_values(b.model)&&pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                    r["normal"]=Dict{String,Any}(
                        "schema"=>r7_money_schema(c.normal.data, "r7-normal-result-v1"),
                        "version"=>"r7_normal_prescribed_v1",
                        "run_id"=>id,
                        "case_sha256"=>c.normal.sha256,
                        "objective_kind"=>r7_normal_objective_kind(c.normal.data),
                        "thermal_model"=>c.normal.data["thermal_model"],
                        "full_preplan_optimality_verified"=>false,
                        "status"=>"candidate",
                        "values"=>Dict(k=>r7_pack(value.(a)) for (k, a) in b.normal_variables),
                        "chp_values"=>Dict(
                            g=>Dict(k=>r7_pack(value.(a)) for (k, a) in block) for
                            (g, block) in b.chp_variables
                        ),
                        r7_money_key(c.normal.data, "solver_objective_USD")=>objective_value(
                            b.model,
                        ),
                    )
                    r7_currency_record!(r["normal"], c.normal.data)
                    r["witnesses"]=[
                        Dict(
                            "event"=>w.pair.event,
                            "fault"=>w.pair.fault,
                            "witness_loss_MWh"=>value(w.loss),
                            "objective_kind"=>"recovery_feasibility_witness",
                            "values"=>Dict(k=>r7_pack(value.(a)) for (k, a) in w.variables),
                        ) for w in b.recovery
                    ]
                end
                try
                    lb=objective_bound(b.model)
                    isfinite(lb) ? (r[r7_money_key(c.normal.data, "lower_bound_USD")]=lb) :
                    (r["bound_unavailable"]="nonfinite")
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            r["error"]=sprint(showerror, err)
            r["status"]=occursin("licen", lowercase(r["error"])) ? "license_unavailable" :
                        "solver_or_build_error"
        end
    end
    r["elapsed_sec"]=time()-started
    r
end

"""
    solve_r7_planning(case; optimizer, method=:finite_fault_ccg, budget_sec=600)

给定正常管流/电拓扑的有限故障经济安全规划。extensive一次纳入全部恢复见证；
finite_fault_ccg以认证反例逐轮添加同一正常决策下的恢复约束，内层逐故障MILP穷举。
nested_indicator_ccg使用实际LP对偶和原生指示约束的内层拓扑生成；每事件发现认证反例可提前返回。
每轮重新检查全部事件，不继承旧计划安全标志；无可信反例时保留未决，绝不靠失败候选生成割。
建模、验证、事件提取和嵌套求解共享截止时间。此有限故障基准不是作者完整内层对偶/Big-M算法。
"""
function solve_r7_planning(
    c::R7PlanningCase;
    optimizer,
    method = :finite_fault_ccg,
    budget_sec = 600.0,
)
    r7_planning_assert(c)
    method in (:extensive, :finite_fault_ccg, :nested_indicator_ccg) || error("未实现的规划方法")
    method==:nested_indicator_ccg &&
        r7_exclusive_battery(c.normal.data) &&
        error("当前嵌套LP对偶未覆盖互斥电池；显式选择extensive或finite_fault_ccg")
    isfinite(budget_sec)&&budget_sec>=0 || error("规划预算错误")
    started=time()
    stop=started+budget_sec
    r=Dict{String,Any}(
        "schema"=>r7_money_schema(c.normal.data, "r7-planning-result-v1"),
        "case_sha256"=>c.sha256,
        "run_id"=>"r7-planning-"*string(uuid4()),
        "method"=>string(method),
        "normal_domain"=>c.specification["normal_domain"],
        "objective_kind"=>r7_normal_objective_kind(c.normal.data),
        "full_preplan_optimality_verified"=>false,
        "author_nested_algorithm_verified"=>false,
        "source_hashes_at_solve"=>r7_planning_science_hashes(),
        "julia_version"=>string(VERSION),
        "budget_sec"=>Float64(budget_sec),
        "status"=>"budget_exhausted",
        "iterations"=>Any[],
    )
    r7_currency_record!(r, c.normal.data)
    allpairs=r7_planning_pairs(c)
    pairs=method==:extensive ? allpairs : eltype(allpairs)[]
    for k in 1:(length(allpairs)+1)
        time()<stop || break
        m=r7_solve_planning_master(c, pairs, optimizer, stop, r["run_id"]*"_normal_$k")
        it=Dict{String,Any}("master"=>m, "audits"=>Any[], "added_pairs"=>Any[])
        push!(r["iterations"], it)
        if !haskey(m, "normal")
            r["status"]=m["status"]
            break
        end
        q=try
            r7_planning_master_check(c, m)
        catch err
            r["error"]=sprint(showerror, err)
            r["status"]="state_handoff_failed"
            break
        end
        if !(q["normal_pass"]&&q["included_pass"])
            r["status"]=haskey(q, "handoff_error") ? "state_handoff_failed" :
                        "master_validation_failed"
            break
        end
        if method==:extensive
            r["status"]="robust_candidate"
            break
        end
        # R7-M3：新正常轨迹有新的ID/哈希，逐事件从零生成审计证据。
        for s in eachindex(c.specification["events"])
            time()<stop || break
            event=r7_planning_event(c, m["normal"], s)
            oracle=method==:nested_indicator_ccg ?
                   solve_r7_adversary(
                event.case;
                optimizer,
                budget_sec = max(0, stop-time()),
                deadline = stop,
                stop_on_violation = true,
            ) :
                   audit_r7_faults(
                event.case;
                optimizer,
                budget_sec = max(0, stop-time()),
                deadline = stop,
            )
            push!(it["audits"], Dict("event_evidence"=>event.evidence, "oracle"=>oracle))
        end
        checks=[r7_planning_audit_check(c, m["normal"], s, a) for (s, a) in enumerate(it["audits"])]
        if length(checks)==length(c.specification["events"])&&all(
            a["status"]=="safe_adopted_model" for a in checks
        )
            r["status"]="robust_candidate"
            break
        end
        existing=Set(r7_planning_pair_key(p) for p in pairs)
        for a in checks, p in a["violating_pairs"]
            pair=(event = p["event"], fault = p["fault"])
            if r7_planning_pair_key(pair) in existing
                r["status"]="oracle_master_conflict"
            else
                push!(pairs, pair)
                push!(existing, r7_planning_pair_key(pair))
                push!(it["added_pairs"], p)
            end
        end
        r["status"]=="oracle_master_conflict" && break
        if isempty(it["added_pairs"])
            r["status"]=time()>=stop ? "budget_exhausted" : "oracle_unresolved"
            break
        end
    end
    r["validation"]=validate_r7_planning(c, r)
    r["candidate_accepted"]=r["validation"]["robust_model_pass"]
    r["conditional_cost_complete"]=r["validation"]["conditional_optimality_pass"]
    r["elapsed_sec"]=time()-started
    r
end
