"""
    solve_r7_normal(case; optimizer, fixed_commitments=nothing, budget_sec=60, deadline=nothing)

求解给定流量正常经济调度，建模和优化共享墙钟预算。记录原目标、有效下界、状态、
源码身份与独立残差；整数启停或显式固定启停分别报告。许可/限时/不可行不混同。
该结果只在给定流量与固定电拓扑域内评价，不认证完整灾前规划或所有灾害下可恢复。
"""
function solve_r7_normal(
    c::R7NormalCase;
    optimizer,
    fixed_commitments = nothing,
    budget_sec = 60.0,
    deadline = nothing,
)
    r7_normal_assert(c)
    isfinite(budget_sec)&&budget_sec>=0 || error("正常调度预算错误")
    deadline===nothing || isfinite(deadline) || error("正常调度截止时间错误")
    started=time()
    stop=deadline===nothing ? started+budget_sec : min(deadline, started+budget_sec)
    r=Dict{String,Any}(
        "schema"=>"r7-normal-result-v1",
        "version"=>"r7_normal_prescribed_v1",
        "run_id"=>string(uuid4()),
        "case_sha256"=>c.sha256,
        "objective_kind"=>"expected_normal_cost_USD",
        "thermal_model"=>c.data["thermal_model"],
        "source_hashes_at_solve"=>r7_normal_science_hashes(),
        "julia_version"=>string(VERSION),
        "budget_sec"=>Float64(budget_sec),
        "status"=>"budget_exhausted",
        "full_preplan_optimality_verified"=>false,
    )
    fixed_commitments===nothing || (r["fixed_commitments"]=deepcopy(fixed_commitments))
    if time()<stop
        try
            b=build_r7_normal(c; optimizer, fixed_commitments)
            r["build_sec"]=time()-started
            r["model_class"]=b.model_class
            r["model_types"]=b.model_types
            if time()<stop
                set_silent(b.model)
                set_time_limit_sec(b.model, stop-time())
                optimize!(b.model)
                ts=termination_status(b.model)
                pr=primal_status(b.model)
                r["termination_status"]=string(ts)
                r["primal_status"]=string(pr)
                r["raw_status"]=raw_status(b.model)
                r["solver_name"]=solver_name(b.model)
                r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                            ts==MOI.TIME_LIMIT ? "time_limit_no_solution" : string(ts)
                if has_values(b.model) && pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["values"]=Dict(k=>r7_pack(value.(a)) for (k, a) in b.variables)
                    r["chp_values"]=Dict(
                        id=>Dict(k=>r7_pack(value.(a)) for (k, a) in block.variables) for
                        (id, block) in b.chp
                    )
                    r["solver_objective_USD"]=objective_value(b.model)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                end
                try
                    lower=objective_bound(b.model)
                    isfinite(lower) ? (r["lower_bound_USD"]=lower) :
                    (r["bound_unavailable"]="nonfinite")
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            msg=sprint(showerror, err)
            r["status"]=occursin("license", lowercase(msg)) ? "license_unavailable" : "solver_error"
            r["error"]=msg
        end
    end
    r["elapsed_sec"]=time()-started
    r["validation"]=validate_r7_normal(c, r)
    r["candidate_accepted"]=r["validation"]["model_pass"]
    r["conditional_cost_complete"]=r["validation"]["optimality_pass"]
    r
end
