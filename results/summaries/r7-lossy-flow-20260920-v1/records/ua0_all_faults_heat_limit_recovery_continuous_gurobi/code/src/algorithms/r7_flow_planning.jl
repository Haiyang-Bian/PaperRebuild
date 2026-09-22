"""
    solve_r7_flow_planning(case, spec; optimizer, budget_sec=600, deadline=nothing)

R7-J2/J4共用预算的全量故障联合求解。保存同一正常决策与逐故障恢复存在性见证，独立回放后才接受。
全部流量固定可用开放MILP求解器；自由流量需支持非凸二次关系，有损版另须支持指数。
不注入旧最优解，不改变流量界以制造可行，也不将限时/缺许可改成不可行证明。
有损版预留预算的10%（最多60秒）作独立核验，原样记录验证耗时及超预算量。
"""
function solve_r7_flow_planning(c, s; optimizer, budget_sec = 600.0, deadline = nothing)
    r7_flow_planning_check(c, s)
    isfinite(budget_sec)&&budget_sec>=0 || error("联合流量预算错误")
    deadline===nothing || isfinite(deadline) || error("联合流量截止时间错误")
    started=time()
    stop=deadline===nothing ? started+budget_sec : min(deadline, started+budget_sec)
    lossy=r7_is_lossy_flow(s["normal_flow"])
    reserve=lossy ? min(60.0, 0.1max(0.0, stop-started)) : 0.0
    compute_stop=stop-reserve
    r=Dict{String,Any}(
        "schema"=>"r7-flow-planning-result-v1",
        "version"=>s["version"],
        "run_id"=>"r7-flow-planning-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "method"=>"extensive",
        "objective_kind"=>"expected_normal_cost_USD",
        "status"=>"budget_exhausted",
        "full_thesis_domain_verified"=>false,
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r7_flow_planning_science_hashes(),
        "julia_version"=>string(VERSION),
    )
    if lossy
        r["validation_reserve_sec"]=reserve
        r["bound_scope"]="adopted_gauss_model_not_exact_PDE"
    end
    if time()<compute_stop
        try
            b=build_r7_flow_planning(c, s; optimizer, deadline = compute_stop)
            r["build_sec"]=time()-started
            r["model_class"], r["model_types"]=b.model_class, b.model_types
            if time()<compute_stop
                set_silent(b.model)
                set_time_limit_sec(b.model, compute_stop-time())
                optimize!(b.model)
                ts, pr=termination_status(b.model), primal_status(b.model)
                r["termination_status"], r["primal_status"]=string(ts), string(pr)
                r["raw_status"], r["solver_name"]=raw_status(b.model), solver_name(b.model)
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
                    sample(a) = r7_pack(map(x->x isa Real ? Float64(x) : value(x), a))
                    r["normal"]=Dict{String,Any}(
                        "schema"=>"r7-normal-flow-result-v1",
                        "version"=>s["normal_flow"]["version"],
                        "run_id"=>r["run_id"]*"-normal",
                        "case_sha256"=>c.normal.sha256,
                        "spec_sha256"=>r7_digest(s["normal_flow"]),
                        "objective_kind"=>"expected_normal_cost_USD",
                        "full_preplan_optimality_verified"=>false,
                        "energy_balance"=>true,
                        "status"=>"candidate",
                        "values"=>Dict(k=>sample(a) for (k, a) in b.normal_variables),
                        "chp_values"=>Dict(
                            id=>Dict(k=>sample(a) for (k, a) in block) for
                            (id, block) in b.chp_variables
                        ),
                        "flow_values"=>Dict(k=>sample(a) for (k, a) in b.normal_flow),
                        "solver_objective_USD"=>objective_value(b.model),
                    )
                    r["witnesses"]=[
                        Dict(
                            "event"=>w.pair.event,
                            "fault"=>w.pair.fault,
                            "objective_kind"=>"recovery_feasibility_witness",
                            "witness_loss_MWh"=>value(w.loss),
                            "values"=>Dict(k=>sample(a) for (k, a) in w.variables),
                            "thermal_values"=>Dict(k=>sample(a) for (k, a) in w.thermal_variables),
                            "boundary_values"=>Dict(
                                k=>sample(a) for (k, a) in w.boundary_parameters
                            ),
                        ) for w in b.recovery
                    ]
                end
                try
                    bound=objective_bound(b.model)
                    isfinite(bound) ? (r["lower_bound_USD"]=bound) :
                    (r["bound_unavailable"]="nonfinite")
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            msg=sprint(showerror, err)
            r["status"]=occursin("license", lowercase(msg)) ? "license_unavailable" :
                        occursin("build_deadline", msg) ? "budget_exhausted" : "solver_error"
            r["error"]=msg
        end
    end
    validation_start=time()
    r["validation"]=validate_r7_flow_planning(c, s, r)
    r["candidate_accepted"]=r["validation"]["robust_model_pass"]
    r["domain_cost_complete"]=r["validation"]["domain_optimality_pass"]
    r["elapsed_sec"]=time()-started
    if lossy
        r["validation_sec"]=time()-validation_start
        r["budget_overrun_sec"]=max(0.0, time()-stop)
        r["wall_budget_pass"]=r["budget_overrun_sec"]==0
    end
    r
end
