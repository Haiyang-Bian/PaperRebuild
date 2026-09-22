"""
    solve_r7_thermal_reconstruction(case, recovery, spec; optimizer, budget_sec=600)

共享截止时间内求解固定控制的热重构，记录原始温度、条件热失供目标和有效下界。
原恢复记录不变；不可行只针对所声明初态、控制与子步模型，不等于整套设备无法恢复。
"""
function solve_r7_thermal_reconstruction(
    c::R7RecoveryCase,
    parent,
    spec;
    optimizer,
    budget_sec = 600.0,
)
    r7_thermal_inputs(c, parent, spec)
    isfinite(budget_sec)&&0<=budget_sec<=600 || error("热重构预算须在0至600秒")
    start=time()
    deadline=start+budget_sec
    r=Dict{String,Any}(
        "schema"=>"r7-thermal-result-v1",
        "run_id"=>"r7-thermal-"*string(uuid4()),
        "spec_sha256"=>r7_digest(spec),
        "parent_result_sha256"=>r7_digest(parent),
        "objective_kind"=>"conditional_heat_unserved_MWh",
        "status"=>"budget_exhausted",
        "termination_status"=>"NOT_RUN",
        "utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "requested_budget_sec"=>Float64(budget_sec),
        "optimizer_request"=>sprint(show, optimizer),
        "source_hashes_at_solve"=>r7_thermal_science_hashes(),
    )
    if time()<deadline
        try
            b=build_r7_thermal_reconstruction(c, parent, spec; optimizer, deadline)
            r["model_class"]=b.model_class
            r["formula_ids"]=sort(collect(keys(b.constraints)))
            set_silent(b.model)
            if time()<deadline
                set_time_limit_sec(b.model, deadline-time())
                optimize!(b.model)
                s=termination_status(b.model)
                r["termination_status"]=string(s)
                r["raw_status"]=raw_status(b.model)
                r["solver"]=solver_name(b.model)
                r["primal_status"]=string(primal_status(b.model))
                r["status"]=s==MOI.OPTIMAL ? "solver_optimal" :
                            s==MOI.INFEASIBLE ? "infeasible_certified" :
                            s==MOI.TIME_LIMIT ?
                            (
                    has_values(b.model) ? "time_limit_with_incumbent" : "time_limit_no_solution"
                ) : "solver_"*lowercase(string(s))
                if has_values(b.model)&&primal_status(b.model) in
                                        (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["values"]=Dict(k=>r7_pack(value.(v)) for (k, v) in b.variables)
                    r["solver_objective_MWh"]=objective_value(b.model)
                end
                try
                    lb=objective_bound(b.model)
                    isfinite(lb)&&(r["lower_bound_MWh"]=lb)
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            r["error"]=sprint(showerror, err)
            r["status"]=occursin("thermal_build_deadline", r["error"]) ? "budget_exhausted" :
                        occursin("licen", lowercase(r["error"])) ? "license_unavailable" :
                        "solver_or_build_error"
        end
    end
    r["elapsed_sec"]=time()-start
    r["validation"]=validate_r7_thermal_reconstruction(c, parent, spec, r)
    r
end
