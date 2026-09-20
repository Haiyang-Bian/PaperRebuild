"""
    solve_r7_transport_recovery(case, fault, spec; optimizer, fixed_z=nothing, budget_sec=600)

共享600秒以内预算构建并求解给定流量的详细热恢复；不以旧代理解固定设备或提供优化初值。
保存实际终止状态、有效条件下界和独立验证。不可行仅属于该流量、初态和子步定义。
"""
function solve_r7_transport_recovery(c, gamma, s; optimizer, fixed_z = nothing, budget_sec = 600.0)
    start=time()
    r7_transport_inputs(c, s)
    r7_check_fault(c, gamma)
    isfinite(budget_sec)&&0<=budget_sec<=600 || error("逐管调度预算须在0至600秒")
    stop=start+budget_sec
    r=Dict{String,Any}(
        "schema"=>"r7-transport-result-v1",
        "version"=>s["version"],
        "run_id"=>"r7-transport-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "fault"=>Int.(gamma),
        "objective_kind"=>"expected_unserved_energy_MWh",
        "status"=>"budget_exhausted",
        "termination_status"=>"NOT_RUN",
        "utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "requested_budget_sec"=>Float64(budget_sec),
        "optimizer_request"=>sprint(show, optimizer),
        "source_hashes_at_solve"=>r7_transport_science_hashes(),
    )
    fixed_z===nothing || (r["fixed_z"]=Int.(fixed_z))
    if time()<stop
        try
            b=build_r7_transport_recovery(c, gamma, s; optimizer, fixed_z, deadline = stop)
            r["model_class"]=b.model_class
            r["formula_ids"]=sort(collect(keys(b.constraints)))
            r["replaced_formulas"]=b.replaced_formulas
            set_silent(b.model)
            if time()<stop
                set_time_limit_sec(b.model, stop-time())
                optimize!(b.model)
                t=termination_status(b.model)
                r["termination_status"]=string(t)
                r["raw_status"]=raw_status(b.model)
                r["primal_status"]=string(primal_status(b.model))
                r["solver"]=solver_name(b.model)
                r["status"]=t==MOI.OPTIMAL ? "solver_optimal" :
                            t==MOI.INFEASIBLE ? "infeasible_certified" :
                            t==MOI.TIME_LIMIT ?
                            (
                    has_values(b.model) ? "time_limit_with_incumbent" : "time_limit_no_solution"
                ) : "solver_"*lowercase(string(t))
                if has_values(b.model)&&primal_status(b.model) in
                                        (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["values"]=Dict(k=>r7_pack(value.(v)) for (k, v) in b.variables)
                    r["thermal_values"]=Dict(
                        k=>r7_pack(value.(v)) for (k, v) in b.thermal_variables
                    )
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
    r["validation"]=validate_r7_transport_recovery(c, s, r)
    r["elapsed_sec"]=time()-start
    r
end
