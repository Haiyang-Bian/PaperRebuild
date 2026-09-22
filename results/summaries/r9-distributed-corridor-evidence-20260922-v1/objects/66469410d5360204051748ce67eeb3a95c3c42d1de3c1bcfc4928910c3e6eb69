"""
    reconstruct_r4_heat(case, parent; spec, optimizer, budget_sec=60, deadline=Inf)

在共享截止时间内核查固定热交付的质量流与温度。目标为常数零，求可行证据，
不重新优化运行费用。LP必要条件失败、详细相容性通过、求解未决分别保存。
仅改变新结果中的热状态；父结果与费用不改写。
"""
function reconstruct_r4_heat(
    c,
    parent;
    spec = R4HeatCompatibilitySpec(),
    optimizer,
    budget_sec = 60.0,
    deadline = Inf,
)
    isfinite(budget_sec) && budget_sec>0 || error("预算必须有限正数")
    started=time()
    limit=min(deadline, started+budget_sec)
    hashes=r4_science_hashes()
    r=Dict{String,Any}(
        "schema"=>"r4-heat-reconstruction-v1",
        "input_sha256"=>c.sha256,
        "parent_sha256"=>r4_heat_parent_hash(parent),
        "spec"=>r4_heat_spec(spec),
        "source_hashes_at_solve"=>hashes,
        "objective_type"=>"feasibility",
        "operating_cost"=>get(parent, "operating_cost", NaN),
        "status"=>"not_run",
        "budget_sec"=>budget_sec,
    )
    try
        b=build_r4_heat_reconstruction(c, parent; spec, optimizer)
        r["constraint_types"]=b.constraint_types
        r["solver"]=solver_name(b.model)
        r["julia_version"]=string(VERSION)
        remain=limit-time()
        if remain<=0
            r["status"]="budget_exhausted_before_solve"
        else
            set_silent(b.model)
            set_time_limit_sec(b.model, remain)
            optimize!(b.model)
            ts=termination_status(b.model)
            r["termination"]=string(ts)
            r["raw_status"]=raw_status(b.model)
            r["primal_status"]=string(primal_status(b.model))
            r["status"]=ts==MOI.INFEASIBLE ? "solver_infeasible" :
                        ts==MOI.TIME_LIMIT ? "time_limit" : "no_validated_candidate"
            # 某些锥求解器在不可行时仍暴露证书向量；证书不是候选调度。
            if has_values(b.model) &&
               primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                vals=Dict{String,Any}()
                for (k, a) in b.variables
                    A=value.(a)
                    startswith(k, "τ_") && (A=273.15 .+ 100 .* A)
                    vals[k]=[collect(A[i, :]) for i in axes(A, 1)]
                end
                r["values"]=vals
                r["solver_objective"]=objective_value(b.model)
                r["validation"]=validate_r4_heat_reconstruction(c, parent, r)
                r["status"]=r["validation"]["pass"] ? "compatible_candidate" :
                            "independent_check_failed"
            end
        end
    catch err
        r["status"]="solver_or_build_error"
        r["error"]=sprint(showerror, err)
    end
    r["elapsed_sec"]=time()-started
    hashes==r4_science_hashes() || error("核查期间科学源码改变")
    r
end
