function r9_detailed_preplan_snapshot(b, c, s, id)
    result = r9_preplan_snapshot(b, c, s["base_spec"], id)
    for (w, block) in zip(result.master["witnesses"], b.recovery)
        w["thermal_values"] = Dict(k => r7_pack(value.(v)) for (k, v) in block.thermal_variables)
        w["normal_inlets"] = Dict("$a/$side/$j" => value.(v) for ((a, side, j), v) in block.prefix)
    end
    result
end

"""
    solve_r9_detailed_preplan(case, spec; optimizer, budget_sec=600, deadline=nothing)

R9-DP2/DP3：在共享截止时间内优化详细恢复关联的灾前费用/罚费或门槛问题。
建模和独立验算计入同一预算；预留15%且至多60秒用于验算。见证与独立恢复结果分开。
保存无候选、超时、缺许可及不可行状态；不回退到聚合模型，不改变温区或注入旧候选。
"""
function solve_r9_detailed_preplan(
    c::R7PlanningCase,
    s;
    optimizer,
    budget_sec = 600.0,
    deadline = nothing,
)
    start = time()
    isfinite(budget_sec) && 0 <= budget_sec <= 600 || error("预算须在0至600秒")
    deadline === nothing || isfinite(deadline) || error("截止时间必须有限")
    stop = deadline === nothing ? start + budget_sec : min(start + budget_sec, deadline)
    carrier = r9_detailed_preplan_check(c, s)
    r = Dict{String,Any}(
        "schema" => "r9-detailed-preplan-result-v1",
        "version" => s["version"],
        "run_id" => "r9-detailed-preplan-" * string(uuid4()),
        "case_sha256" => c.sha256,
        "normal_sha256" => c.normal.sha256,
        "spec_sha256" => r7_digest(s),
        "carrier_sha256" => carrier.sha256,
        "currency" => s["base_spec"]["currency"],
        "objective_kind" => r9_preplan_objective(s["base_spec"]),
        "source_hashes_at_solve" => r9_detailed_preplan_science_hashes(),
        "julia_version" => string(VERSION),
        "status" => "budget_exhausted",
        "budget_sec" => Float64(budget_sec),
        "independent_recovery_performed" => false,
        "full_thesis_domain_verified" => false,
    )
    solve_stop = stop - min(60.0, max(0.0, stop - start) * 0.15)
    if time() < solve_stop
        try
            b = build_r9_detailed_preplan(c, s; optimizer, deadline = solve_stop)
            r["model_class"], r["model_types"] = b.model_class, b.model_types
            r["build_sec"] = time() - start
            if time() < solve_stop
                set_silent(b.model)
                set_time_limit_sec(b.model, solve_stop - time())
                optimize!(b.model)
                ts, pr = termination_status(b.model), primal_status(b.model)
                r["termination_status"], r["primal_status"] = string(ts), string(pr)
                r["raw_status"], r["solver_name"] = raw_status(b.model), solver_name(b.model)
                try
                    r["solver_version"] = MOI.get(backend(b.model), MOI.SolverVersion())
                catch err
                    r["solver_version_unavailable"] = sprint(showerror, err)
                end
                r["status"] =
                    ts == MOI.INFEASIBLE ? "infeasible_certified" :
                    ts == MOI.TIME_LIMIT ? "time_limit_no_solution" :
                    "solver_" * lowercase(string(ts))
                if has_values(b.model) && pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    x = r9_detailed_preplan_snapshot(b, c, s, r["run_id"])
                    r["master"], r["epigraph_MWh"] = x.master, x.epigraph_MWh
                    r["solver_objective"] = objective_value(b.model)
                    r["status"] = ts == MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                    r["master"]["status"] = r["status"]
                end
                try
                    lb = objective_bound(b.model)
                    isfinite(lb) ? (r["objective_lower_bound"] = lb) :
                    (r["bound_unavailable"] = "nonfinite")
                catch err
                    r["bound_unavailable"] = sprint(showerror, err)
                end
            end
        catch err
            r["error"] = sprint(showerror, err)
            r["status"] =
                occursin("deadline", r["error"]) ? "budget_exhausted" :
                occursin("licen", lowercase(r["error"])) ? "license_unavailable" :
                "solver_or_build_error"
        end
    end
    r["validation"] = validate_r9_detailed_preplan(c, s, r)
    r["candidate_accepted"] = r["validation"]["model_pass"]
    r["conditional_objective_complete"] = r["validation"]["objective_optimality_pass"]
    r["elapsed_sec"] = time() - start
    r["deadline_overrun_sec"] = max(0.0, time() - stop)
    r
end
