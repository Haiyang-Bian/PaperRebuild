function r8_snapshot(b, c, flow, s, id)
    sample(a) = r7_pack(map(x->x isa Real ? Float64(x) : value(x), a))
    n=Dict{String,Any}(
        "schema"=>"r7-normal-flow-result-v1",
        "version"=>flow["normal_flow"]["version"],
        "run_id"=>id*"-normal",
        "case_sha256"=>c.normal.sha256,
        "spec_sha256"=>r7_digest(flow["normal_flow"]),
        "objective_kind"=>"expected_normal_cost_USD",
        "full_preplan_optimality_verified"=>false,
        "energy_balance"=>true,
        "status"=>"candidate",
        "values"=>Dict(k=>sample(a) for (k, a) in b.normal_variables),
        "chp_values"=>Dict(
            id=>Dict(k=>sample(a) for (k, a) in block) for (id, block) in b.chp_variables
        ),
        "flow_values"=>Dict(k=>sample(a) for (k, a) in b.normal_flow),
        "solver_objective_USD"=>value(b.normal_cost),
    )
    witnesses=[
        Dict(
            "event"=>w.pair.event,
            "fault"=>w.pair.fault,
            "objective_kind"=>"recovery_feasibility_witness",
            "witness_loss_MWh"=>value(w.loss),
            "values"=>Dict(k=>sample(a) for (k, a) in w.variables),
            "thermal_values"=>Dict(k=>sample(a) for (k, a) in w.thermal_variables),
            "boundary_values"=>Dict(k=>sample(a) for (k, a) in w.boundary_parameters),
        ) for w in b.recovery
    ]
    (; normal = n, witnesses, eta = Float64[value(x) for x in b.eta])
end

function r8_solve_stage(c, flow, s; optimizer, deadline, normal_result = nothing)
    start=time()
    evaluation=normal_result!==nothing
    id="r8-stage-"*string(uuid4())
    r=Dict{String,Any}(
        "run_id"=>id,
        "status"=>"budget_exhausted",
        "objective_kind"=>r8_objective_kind(s; evaluation),
        "evaluation"=>evaluation,
    )
    evaluation && (r["fixed_normal_sha256"]=r7_digest(normal_result))
    if time()<deadline
        try
            b=build_r8_model(c, flow, s; optimizer, deadline, normal_result)
            r["build_sec"]=time()-start
            r["model_class"], r["model_types"]=b.model_class, b.model_types
            if time()<deadline
                set_silent(b.model)
                set_time_limit_sec(b.model, deadline-time())
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
                if has_values(b.model) && pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    x=r8_snapshot(b, c, flow, s, id)
                    r["normal"], r["witnesses"], r["eta_MWh"]=x.normal, x.witnesses, x.eta
                    r["solver_objective"]=objective_value(b.model)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                end
                try
                    bound=objective_bound(b.model)
                    isfinite(bound) ? (r["objective_lower_bound"]=bound) :
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
    r["validation"]=r8_validate_stage(c, flow, s, r; normal_result)
    r["elapsed_sec"]=time()-start
    r
end

"""
    solve_r8_case(case, flow, spec; optimizer, budget_sec=600)

共用墙钟预算求经济/门槛/罚项调度，再固定原正常计划独立最小化逐事件最坏恢复失供。
主阶段最多占80%，末尾预留10%（至多60秒）验证；所有构建、求解和回放计时。
恢复评估不回写或改善正常计划，缺失界、硬不可行和超时均保留。主目标界与恢复MWh界分开，
最终报告同时包含模型可行、门槛可行、费用认证和固定计划风险认证，不能相互替代。
"""
function solve_r8_case(c::R7PlanningCase, flow, s; optimizer, budget_sec = 600.0)
    r8_check(c, flow, s)
    isfinite(budget_sec)&&budget_sec>=0 || error("R8预算错误")
    started=time()
    stop=started+budget_sec
    reserve=min(60.0, 0.1budget_sec)
    r=Dict{String,Any}(
        "schema"=>"r8-tradeoff-result-v1",
        "version"=>s["version"],
        "run_id"=>"r8-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "flow_sha256"=>r7_digest(flow),
        "spec_sha256"=>r7_digest(s),
        "source_hashes_at_solve"=>r8_science_hashes(),
        "budget_sec"=>Float64(budget_sec),
        "julia_version"=>string(VERSION),
        "full_thesis_domain_verified"=>false,
    )
    primary=r8_solve_stage(c, flow, s; optimizer, deadline = started+0.8budget_sec)
    r["primary"]=primary
    if primary["validation"]["model_pass"]
        r["evaluation"]=r8_solve_stage(
            c,
            flow,
            s;
            optimizer,
            deadline = stop-reserve,
            normal_result = primary["normal"],
        )
    end
    r["validation"]=validate_r8_solution(c, flow, s, r)
    r["elapsed_sec"]=time()-started
    r["budget_overrun_sec"]=max(0.0, time()-stop)
    r["wall_budget_pass"]=r["budget_overrun_sec"]==0
    r
end
