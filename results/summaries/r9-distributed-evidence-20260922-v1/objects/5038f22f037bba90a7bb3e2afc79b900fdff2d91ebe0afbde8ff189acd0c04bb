const R5_COMMITMENT_SOLVE_FILE=@__FILE__

"""
    solve_r5_commitment(case; optimizer, budget_sec=60)

在一次共享建模/求解预算内优化共同日前承诺及全情景补救，保留候选、界和真实终止状态。
场景原始乘子另存；除以严格正的概率后核验固定承诺条件LP，不裁剪或另求乘子。
仅使用外生价格和声明概率；各情景硬舒适。无候选、缺许可或数值失败不返回零调度。
"""
function solve_r5_commitment(c::R5CommitmentCase; optimizer, budget_sec = 60.0)
    isfinite(budget_sec)&&budget_sec>0||error("共同承诺预算必须有限正数")
    r5_commitment_assert_case(c)
    start=time()
    r=Dict{String,Any}(
        "schema"=>"r5-commitment-result-v1",
        "version"=>"r5_shared_commitment_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-commitment-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "objective_type"=>"expected_IES_net_cost_fixed_prices",
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r5_commitment_science_hashes(),
    )
    try
        b=build_r5_commitment(c; optimizer)
        m=b.model
        r["model_type"], r["model_types"], r["solver"]=b.model_type, b.model_types, solver_name(m)
        try
            r["solver_version"]=MOI.get(backend(m), MOI.SolverVersion())
        catch err
            r["solver_version_unavailable"]=sprint(showerror, err)
        end
        set_silent(m)
        remaining=budget_sec-(time()-start)
        if remaining<=0
            r["status"]="budget_exhausted_before_solve"
        else
            set_time_limit_sec(m, remaining)
            optimize!(m)
            term, prim, dstat=termination_status(m), primal_status(m), dual_status(m)
            r["termination"], r["primal_status"], r["dual_status"], r["raw_status"]=string(term),
            string(prim),
            string(dstat),
            raw_status(m)
            point=prim in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
            r["status"]=term==MOI.OPTIMAL ? "solver_optimal" :
                        term==MOI.INFEASIBLE ? "solver_infeasible" :
                        term==MOI.TIME_LIMIT ?
                        (point ? "time_limit_with_incumbent" : "time_limit_no_incumbent") :
                        string(term)
            try
                bound=objective_bound(m)
                isfinite(bound)&&(
                    r["solver_objective_bound"] = bound;
                    r["bound_source"] = "MOI.ObjectiveBound"
                )
            catch err
                r["bound_unavailable"]=sprint(showerror, err)
            end
            if point
                r["solver_objective"]=objective_value(m)
                x=Dict(k=>value.(vars) for (k, vars) in b.first_stage)
                r["first_stage"]=x
                r["scenarios"]=Dict{String,Any}()
                r["weighted_raw_scenario_duals"]=Dict{String,Any}()
                if dstat==MOI.FEASIBLE_POINT
                    r["raw_first_stage_duals"]=Dict(k=>dual(v) for (k, v) in b.first_rows)
                    if !haskey(r, "solver_objective_bound")
                        try
                            bound=dual_objective_value(m)
                            isfinite(bound)&&(
                                r["solver_objective_bound"] = bound;
                                r["bound_source"] = "MOI.DualObjectiveValue"
                            )
                        catch err
                            r["dual_bound_unavailable"]=sprint(showerror, err)
                        end
                    end
                end
                for s in c.data["scenarios"]
                    id=s["id"]
                    view=r5_commitment_view(c, s, x)
                    sys=b.systems[id]
                    rr=Dict{String,Any}(
                        "schema"=>"r5-dispatch-result-v1",
                        "version"=>"r5_dispatch_checked_v1",
                        "case_sha256"=>view.sha256,
                        "run_id"=>r["run_id"]*"/"*id,
                        "status"=>"embedded_shared_commitment_candidate",
                        "parent_run_id"=>r["run_id"],
                        "values"=>Dict(
                            k=>[
                                [value(b.variables[id]["$k/$i/$t"]) for t in 1:view.data["T"]] for
                                i in 1:n
                            ] for (k, n) in sys.sizes
                        ),
                    )
                    rr["solver_objective"]=r5_commitment_day_cost(c, x)+sum(
                        sys.cost[k]*value(b.variables[id][k]) for k in keys(sys.cost)
                    )
                    if dstat==MOI.FEASIBLE_POINT
                        raw=Dict(k=>dual(ref) for (k, ref) in b.rows[id])
                        r["weighted_raw_scenario_duals"][id]=raw
                        # 联合LP目标中的p_s缩放：lambda_s/p_s才是条件LP乘子。
                        rr["raw_constraint_duals"]=Dict(
                            k=>raw[k]/s["probability"] for (k, z) in sys.rows if !z.bound
                        )
                        rr["raw_bound_duals"]=Dict(
                            k=>raw[k]/s["probability"] for (k, z) in sys.rows if z.bound
                        )
                        rr["dual_probability_divisor"]=s["probability"]
                    end
                    r["scenarios"][id]=rr
                end
            end
        end
    catch err
        message=sprint(showerror, err)
        r["status"]=occursin(r"(?i)license|licence|expired|not licensed", message) ?
                    "license_unavailable" :
                    err isa MOI.UnsupportedConstraint||err isa MOI.UnsupportedAttribute ?
                    "unsupported_solver" : "execution_error"
        r["error"]=message
    end
    r["validation"]=validate_r5_commitment(c, r)
    r["cost_optimization_complete"]=r["status"]=="solver_optimal"&&r["validation"]["optimality_pass"]
    r["elapsed_sec"]=time()-start
    r["source_hashes_at_solve"]==r5_commitment_science_hashes()||error("共同承诺求解期间源码变化")
    r
end
