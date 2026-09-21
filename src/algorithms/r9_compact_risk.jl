const R9_COMPACT_SOLVE_FILE=@__FILE__

"""在共享截止时间内保留优化器日志；状态及界的定义沿用R5，不修改模型或替换未返回的候选。"""
function r9_logged_risk_optimize!(m, deadline)
    unset_silent(m)
    remaining=deadline-time()
    remaining>0 ||
        return Dict{String,Any}("status"=>"budget_exhausted_before_solve", "has_candidate"=>false)
    set_time_limit_sec(m, remaining)
    optimize!(m)
    term, prim=termination_status(m), primal_status(m)
    point=prim in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
    out=Dict{String,Any}(
        "termination"=>string(term),
        "primal_status"=>string(prim),
        "raw_status"=>raw_status(m),
        "has_candidate"=>point,
        "solver"=>solver_name(m),
        "status"=>r5_risk_termination(term, point),
        "solver_logging_requested"=>true,
    )
    try
        out["solver_version"]=MOI.get(backend(m), MOI.SolverVersion())
    catch err
        out["solver_version_unavailable"]=sprint(showerror, err)
    end
    point && (out["solver_objective"]=objective_value(m))
    try
        bound=objective_bound(m)
        if isfinite(bound)
            out["solver_objective_bound"]=bound
            out["bound_source"]="MOI.ObjectiveBound"
        end
    catch err
        out["bound_unavailable"]=sprint(showerror, err)
    end
    if !haskey(out, "solver_objective_bound") && dual_status(m)==MOI.FEASIBLE_POINT
        try
            bound=dual_objective_value(m)
            if isfinite(bound)
                out["solver_objective_bound"]=bound
                out["bound_source"]="MOI.DualObjectiveValue"
            end
        catch err
            out["dual_bound_unavailable"]=sprint(showerror, err)
        end
    end
    out
end
