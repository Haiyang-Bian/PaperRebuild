const R5_DISPATCH_SOLVE_FILE = @__FILE__

"""
    solve_r5_dispatch(case; optimizer, budget_sec=60)

在共享建模/求解截止时间内求确定性补救LP，保存真实终止状态、候选、有效界及原始对偶。
费用为给定市场成交下的净支出；缺失界不冒充最优认证，原始对偶未在本批用于Benders割。
不可行或无候选不生成零调度；独立验算与求解结果分别记录。
"""
function solve_r5_dispatch(c::R5DispatchCase; optimizer, budget_sec = 60.0)
    isfinite(budget_sec) && budget_sec>0 || error("补救预算必须有限正数")
    r5_dispatch_assert_case(c)
    start=time()
    r=Dict{String,Any}(
        "schema"=>"r5-dispatch-result-v1",
        "version"=>"r5_dispatch_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-dispatch-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "objective_type"=>"fixed_award_IES_net_cost",
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r5_dispatch_science_hashes(),
    )
    try
        b=build_r5_dispatch(c; optimizer)
        m=b.model
        r["model_type"], r["model_types"]=b.model_type, b.model_types
        r["solver"]=solver_name(m)
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
            term, primal, dstat=termination_status(m), primal_status(m), dual_status(m)
            r["termination"], r["primal_status"], r["dual_status"]=string(term),
            string(primal),
            string(dstat)
            r["raw_status"]=raw_status(m)
            haspoint=primal in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
            r["status"]=term==MOI.OPTIMAL ? "solver_optimal" :
                        term==MOI.INFEASIBLE ? "solver_infeasible" :
                        term==MOI.TIME_LIMIT ?
                        (haspoint ? "time_limit_with_incumbent" : "time_limit_no_incumbent") :
                        string(term)
            try
                bound=objective_bound(m)
                isfinite(bound) &&
                    (r["solver_objective_bound"] = bound; r["bound_source"] = "MOI.ObjectiveBound")
            catch err
                r["bound_unavailable"]=sprint(showerror, err)
            end
            if haspoint
                r["solver_objective"]=objective_value(m)
                r["values"]=Dict(
                    string(k)=>r5_market_rows(value.(v)) for (k, v) in pairs(b.variables)
                )
                if dstat==MOI.FEASIBLE_POINT
                    r["raw_constraint_duals"]=Dict(k=>dual(ref) for (k, ref) in b.rows)
                    r["raw_bound_duals"]=Dict{String,Any}()
                    for (key, vars) in pairs(b.variables), idx in CartesianIndices(vars)
                        ref=vars[idx]
                        for (kind, present, ctor) in (
                            ("lower", has_lower_bound(ref), LowerBoundRef),
                            ("upper", has_upper_bound(ref), UpperBoundRef),
                        )
                            present || continue
                            r["raw_bound_duals"]["$key/$(idx[1])/$(idx[2])/$kind"]=dual(ctor(ref))
                        end
                    end
                    if !haskey(r, "solver_objective_bound")
                        try
                            bound=dual_objective_value(m)
                            isfinite(bound) && (
                                r["solver_objective_bound"] = bound;
                                r["bound_source"] = "MOI.DualObjectiveValue"
                            )
                        catch err
                            r["dual_bound_unavailable"]=sprint(showerror, err)
                        end
                    end
                end
            end
        end
    catch err
        message=sprint(showerror, err)
        r["status"]=occursin(r"(?i)license|licence|expired|not licensed", message) ?
                    "license_unavailable" :
                    err isa MOI.UnsupportedConstraint || err isa MOI.UnsupportedAttribute ?
                    "unsupported_solver" : "execution_error"
        r["error"]=message
    end
    r["validation"]=validate_r5_dispatch(c, r)
    r["cost_optimization_complete"]=r["status"]=="solver_optimal" &&
                                    r["validation"]["optimality_pass"]
    r["elapsed_sec"]=time()-start
    r["source_hashes_at_solve"]==r5_dispatch_science_hashes() || error("求解期间IES源码变化")
    r
end
