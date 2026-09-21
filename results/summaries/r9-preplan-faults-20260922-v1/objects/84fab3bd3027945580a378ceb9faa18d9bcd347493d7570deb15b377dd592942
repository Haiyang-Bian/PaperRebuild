function r9_preplan_snapshot(b, c, s, id)
    sample(a) = r7_pack(value.(a))
    n=Dict{String,Any}(
        "schema"=>r7_money_schema(c.normal.data, "r7-normal-result-v1"),
        "version"=>"r7_normal_prescribed_v1",
        "run_id"=>id*"-normal",
        "case_sha256"=>c.normal.sha256,
        "objective_kind"=>r7_normal_objective_kind(c.normal.data),
        "thermal_model"=>c.normal.data["thermal_model"],
        "full_preplan_optimality_verified"=>false,
        "status"=>"candidate",
        "values"=>Dict(k=>sample(a) for (k, a) in b.normal_variables),
        "chp_values"=>Dict(g=>Dict(k=>sample(a) for (k, a) in v) for (g, v) in b.chp_variables),
        r7_money_key(c.normal.data, "solver_objective_USD")=>value(b.normal_cost),
    )
    r7_currency_record!(n, c.normal.data)
    m=Dict{String,Any}(
        "status"=>"candidate",
        "normal"=>n,
        "included"=>[Dict("event"=>p.event, "fault"=>p.fault) for p in b.included],
        "witnesses"=>[
            Dict(
                "event"=>w.pair.event,
                "fault"=>w.pair.fault,
                "objective_kind"=>"recovery_feasibility_witness",
                "witness_loss_MWh"=>value(w.loss),
                "values"=>Dict(k=>sample(a) for (k, a) in w.variables),
            ) for w in b.recovery
        ],
    )
    r7_currency_record!(m, c.normal.data)
    (; master = m, epigraph_MWh = value.(b.ζ))
end

"""
    solve_r9_preplan(case, spec; optimizer, budget_sec=600, deadline=nothing)

在显式共享截止时间内求解三目标灾前主阶段，保留费用、罚费、所选故障见证和原模型下界。
此入口不执行独立灾后恢复；见证不是各故障最小失供证书。完整实验由脚本将主阶段、
独立聚合/详细恢复、回放和存档计入同一600秒；未执行或超时阶段不得当作通过。
"""
function solve_r9_preplan(c::R7PlanningCase, s; optimizer, budget_sec = 600.0, deadline = nothing)
    r9_preplan_check(c, s)
    isfinite(budget_sec) && 0<=budget_sec<=600 || error("灾前预算须在0至600秒")
    deadline===nothing || isfinite(deadline) || error("截止时间必须有限")
    start=time()
    stop=deadline===nothing ? start+budget_sec : min(start+budget_sec, deadline)
    r=Dict{String,Any}(
        "schema"=>"r9-preplan-result-v1",
        "version"=>s["version"],
        "run_id"=>"r9-preplan-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "normal_sha256"=>c.normal.sha256,
        "spec_sha256"=>r7_digest(s),
        "carrier_sha256"=>r9_preplan_carrier(c, s).sha256,
        "currency"=>r7_currency(c.normal.data),
        "objective_kind"=>r9_preplan_objective(s),
        "source_hashes_at_solve"=>r9_preplan_science_hashes(),
        "julia_version"=>string(VERSION),
        "status"=>"budget_exhausted",
        "budget_sec"=>Float64(budget_sec),
        "independent_recovery_performed"=>false,
        "full_thesis_domain_verified"=>false,
    )
    if time()<stop
        try
            b=build_r9_preplan(c, s; optimizer)
            r["model_class"], r["model_types"]=b.model_class, b.model_types
            r["build_sec"]=time()-start
            if time()<stop
                set_silent(b.model)
                set_time_limit_sec(b.model, stop-time())
                optimize!(b.model)
                ts, pr=termination_status(b.model), primal_status(b.model)
                r["termination_status"], r["primal_status"]=string(ts), string(pr)
                r["raw_status"], r["solver_name"]=raw_status(b.model), solver_name(b.model)
                r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                            ts==MOI.TIME_LIMIT ? "time_limit_no_solution" :
                            "solver_"*lowercase(string(ts))
                if has_values(b.model) && pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    x=r9_preplan_snapshot(b, c, s, r["run_id"])
                    r["master"], r["epigraph_MWh"]=x.master, x.epigraph_MWh
                    r["solver_objective"]=objective_value(b.model)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                    r["master"]["status"]=r["status"]
                end
                try
                    lb=objective_bound(b.model)
                    isfinite(lb) ? (r["objective_lower_bound"]=lb) :
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
    r["validation"]=validate_r9_preplan(c, s, r)
    r["candidate_accepted"]=r["validation"]["model_pass"]
    r["conditional_objective_complete"]=r["validation"]["objective_optimality_pass"]
    r["elapsed_sec"]=time()-start
    r["deadline_overrun_sec"]=max(0.0, time()-stop)
    r
end
