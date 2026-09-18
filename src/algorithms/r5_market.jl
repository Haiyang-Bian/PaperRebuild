const R5_MARKET_SOLVE_FILE = @__FILE__

"""
    solve_r5_market(case; optimizer, budget_sec=60)

共享建模/求解预算执行固定报价连续LP；保留真实状态、原始MOI对偶及统一拉格朗日乘子。
独立验证不把不可行证书当候选，也不将缺对偶的运行标为最优性通过。
"""
function solve_r5_market(c::R5MarketCase; optimizer, budget_sec = 60.0)
    isfinite(budget_sec)&&budget_sec>0 || error("市场预算必须有限正数")
    r5_market_assert_case(c)
    start=time()
    r=Dict{String,Any}(
        "schema"=>"r5-market-result-v1",
        "case_sha256"=>c.sha256,
        "version"=>"r5_market_clearing_checked_v1",
        "budget_sec"=>Float64(budget_sec),
        "objective_type"=>"fixed_bid_clearing_cost_not_system_resource_cost",
        "fixed_load_utility_constant_omitted"=>true,
        "run_id"=>"r5-market-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "source_hashes_at_solve"=>r5_market_science_hashes(),
    )
    try
        built=build_r5_market(c; optimizer)
        m=built.model
        r["model_type"]=built.model_type
        r["model_types"]=built.model_types
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
            r["termination"]=string(term)
            r["primal_status"]=string(primal)
            r["dual_status"]=string(dstat)
            try
                r["raw_status"]=raw_status(m)
            catch err
                r["raw_status_unavailable"]=sprint(showerror, err)
            end
            r["status"]=term==MOI.OPTIMAL ? "solver_optimal" :
                        term==MOI.INFEASIBLE ? "solver_infeasible" :
                        term==MOI.TIME_LIMIT ?
                        (
                primal in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT) ?
                "time_limit_with_incumbent" : "time_limit_no_incumbent"
            ) : string(term)
            try
                bound=objective_bound(m)
                isfinite(bound) && (r["solver_objective_bound"]=bound)
            catch err
                r["bound_unavailable"]=sprint(showerror, err)
            end
            if primal in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                r["solver_objective"]=objective_value(m)
                r["values"]=Dict(
                    string(k)=>r5_market_rows(value.(v)) for (k, v) in pairs(built.variables)
                )
                if dstat==MOI.FEASIBLE_POINT
                    raw=Dict{String,Any}()
                    converted=Dict{String,Any}()
                    for (k, refs) in built.rows
                        v=dual.(refs)
                        sign=k in (:g_cap_down, :i_cap_up) ? 1.0 : -1.0
                        raw[string(k)]=ndims(v)==1 ? collect(v) : r5_market_rows(v)
                        converted[string(k)]=ndims(v)==1 ? collect(sign*v) : r5_market_rows(sign*v)
                    end
                    r["raw_duals"]=raw
                    r["multipliers"]=converted
                    r["lower_bound_duals"]=Dict(
                        string(k)=>r5_market_rows(dual.(LowerBoundRef.(v))) for
                        (k, v) in pairs(built.variables)
                    )
                end
            end
        end
    catch e
        message=sprint(showerror, e)
        r["status"]=occursin(r"(?i)license|licence|expired|not licensed", message) ?
                    "license_unavailable" :
                    e isa MOI.UnsupportedConstraint || e isa MOI.UnsupportedAttribute ?
                    "unsupported_solver" : "execution_error"
        r["error"]=message
    end
    r["validation"]=validate_r5_market(c, r)
    r["cost_optimization_complete"]=r["status"]=="solver_optimal"&&r["validation"]["optimality_pass"]
    r["elapsed_sec"]=time()-start
    r["source_hashes_at_solve"]==r5_market_science_hashes() ||
        error("求解期间市场源码变化，不可保存为正式运行")
    r
end
