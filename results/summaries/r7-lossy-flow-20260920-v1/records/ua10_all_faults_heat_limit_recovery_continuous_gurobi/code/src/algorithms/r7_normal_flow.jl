"""
    solve_r7_normal_flow(case, spec; optimizer, budget_sec=600, deadline=nothing, energy_balance=false)

预算包含构建与求解，记录连续流量、设备调度、状态、实际MIQCP界和独立回放。固定流量
特例可用开放MILP求解器；一般模型由调用者显式提供支持二次等式及所选散热指数的求解器。
不自动切换模型、注入旧最优解、申请商业许可或隐藏枚举；失败和限时分别保存。
可选energy_balance显式记录整网等价守恒表示；不改写旧结果或给默认调用新增约束。
有损版预留至多60秒（预算的10%）作原值核验，另记验证耗时和实际超预算量，不丢弃已有候选。
"""
function solve_r7_normal_flow(
    c,
    s;
    optimizer,
    budget_sec = 600.0,
    deadline = nothing,
    energy_balance = false,
)
    r7_normal_flow_check(c, s)
    isfinite(budget_sec)&&budget_sec>=0 || error("连续流量预算错误")
    deadline===nothing || isfinite(deadline) || error("连续流量截止时间错误")
    started=time()
    stop=deadline===nothing ? started+budget_sec : min(deadline, started+budget_sec)
    lossy=r7_is_lossy_flow(s)
    reserve=lossy ? min(60.0, 0.1max(0.0, stop-started)) : 0.0
    compute_stop=stop-reserve
    r=Dict{String,Any}(
        "schema"=>"r7-normal-flow-result-v1",
        "version"=>s["version"],
        "run_id"=>"r7-normal-flow-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "objective_kind"=>"expected_normal_cost_USD",
        "source_hashes_at_solve"=>r7_normal_flow_science_hashes(),
        "julia_version"=>string(VERSION),
        "budget_sec"=>Float64(budget_sec),
        "status"=>"budget_exhausted",
        "full_preplan_optimality_verified"=>false,
        "energy_balance"=>energy_balance,
    )
    if lossy
        r["validation_reserve_sec"]=reserve
        r["bound_scope"]="adopted_gauss_model_not_exact_PDE"
    end
    if time()<compute_stop
        try
            b=build_r7_normal_flow(c, s; optimizer, deadline = compute_stop, energy_balance)
            r["build_sec"]=time()-started
            r["model_class"]=b.model_class
            r["model_types"]=b.model_types
            r["flow_fixed"]=b.fixed_flow
            if time()<compute_stop
                set_silent(b.model)
                set_time_limit_sec(b.model, compute_stop-time())
                optimize!(b.model)
                ts=termination_status(b.model)
                pr=primal_status(b.model)
                r["termination_status"]=string(ts)
                r["primal_status"]=string(pr)
                r["raw_status"]=raw_status(b.model)
                r["solver_name"]=solver_name(b.model)
                r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                            ts==MOI.TIME_LIMIT ? "time_limit_no_solution" : string(ts)
                if has_values(b.model)&&pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["values"]=Dict(k=>r7_pack(value.(a)) for (k, a) in b.variables)
                    r["chp_values"]=Dict(
                        id=>Dict(k=>r7_pack(value.(a)) for (k, a) in block.variables) for
                        (id, block) in b.chp
                    )
                    r["flow_values"]=Dict(
                        k=>r7_pack(b.fixed_flow ? a : value.(a)) for (k, a) in b.flow
                    )
                    r["solver_objective_USD"]=objective_value(b.model)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
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
    r["validation"]=validate_r7_normal_flow(c, s, r)
    r["candidate_accepted"]=r["validation"]["model_pass"]
    r["domain_cost_complete"]=r["validation"]["optimality_pass"]
    r["elapsed_sec"]=time()-started
    if lossy
        r["validation_sec"]=time()-validation_start
        r["budget_overrun_sec"]=max(0.0, time()-stop)
        r["wall_budget_pass"]=r["budget_overrun_sec"]==0
    end
    r
end
