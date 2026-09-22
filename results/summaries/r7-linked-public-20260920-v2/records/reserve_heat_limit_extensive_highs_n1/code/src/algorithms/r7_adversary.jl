const R7_ADVERSARY_SOLVE_FILE = @__FILE__

function r7_solve_adversary_master(c, zs, optimizer, stop)
    started=time()
    r=Dict{String,Any}(
        "status"=>"budget_exhausted",
        "topologies"=>deepcopy(zs),
        "objective_kind"=>"capped_restricted_worst_loss_MWh",
    )
    if started<stop
        try
            b=build_r7_adversary(c, zs; optimizer)
            r["model_class"]=b.model_class
            r["automatic_bridges"]=b.automatic_bridges
            r["build_sec"]=time()-started
            if time()<stop
                set_silent(b.model)
                set_time_limit_sec(b.model, stop-time())
                optimize!(b.model)
                s=termination_status(b.model)
                r["termination_status"]=string(s)
                r["primal_status"]=string(primal_status(b.model))
                r["raw_status"]=raw_status(b.model)
                r["solver"]=solver_name(b.model)
                r["status"]="solver_"*lowercase(string(s))
                if has_values(b.model) &&
                   primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    raw=value.(b.gamma)
                    if all(x->isfinite(x)&&abs(x-round(x))<=1e-6, raw)
                        r["values"]=Dict(
                            "fault"=>round.(Int, raw),
                            "fault_raw"=>raw,
                            "theta_MWh"=>value(b.theta),
                            "blocks"=>[
                                Dict(
                                    "matrix_sha256"=>block.lp.sha256,
                                    "lambda"=>value.(block.lambda),
                                    "products"=>[
                                        Dict(
                                            "row"=>p["row"],
                                            "fault_column"=>p["fault_column"],
                                            "value"=>value(p["variable"]),
                                        ) for p in block.products
                                    ],
                                ) for block in b.blocks
                            ],
                        )
                    else
                        r["status"]="noninteger_fault_candidate"
                    end
                end
                if s in (
                    MOI.OPTIMAL,
                    MOI.TIME_LIMIT,
                    MOI.NODE_LIMIT,
                    MOI.ITERATION_LIMIT,
                    MOI.SOLUTION_LIMIT,
                )
                    try
                        bound=objective_bound(b.model)
                        isfinite(bound) && (r["solver_upper_bound_MWh"]=Float64(bound))
                    catch
                        r["bound_unavailable"]=true
                    end
                end
            end
        catch err
            # 不保存许可号、路径等求解器环境详情。
            message=lowercase(sprint(showerror, err))
            r["status"]=occursin("licen", message) ? "license_unavailable" : "solver_or_build_error"
            r["error_type"]=string(typeof(err))
            r["unsupported_native_constraint"]=err isa MOI.UnsupportedConstraint
        end
    end
    if haskey(r, "values")
        r["validation"]=r7_validate_adversary_values(c, zs, r["values"])
    end
    r["elapsed_sec"]=time()-started
    r
end

"""
    solve_r7_adversary(case; optimizer, recovery_optimizer=optimizer, budget_sec=600,
                       max_iterations=200, stop_on_violation=false, deadline=nothing)

固定灾前状态的内层拓扑生成：解原生指示对偶主问题，选故障，解完整恢复MILP，加入恢复拓扑。
仅完整恢复的有效最小化下界提高最坏损失下界；受限对手的最大化上界低于预定截断值时才提供上界。
若完整恢复认证不可行，保留无限损失反例；不调用有限故障穷举或隐式Big-M作为后备。
建模、独立数值回代和所有嵌套求解共享预算。本采用版不是原文符号错误版本的等价实现。
"""
function solve_r7_adversary(
    c::R7RecoveryCase;
    optimizer,
    recovery_optimizer = optimizer,
    budget_sec = 600.0,
    max_iterations = 200,
    stop_on_violation = false,
    deadline = nothing,
)
    r7_recovery_assert(c)
    r7_exclusive_battery(c.data) && error("互斥电池须用完整MILP故障审计，不能套用旧LP对偶算法")
    isfinite(budget_sec)&&budget_sec>=0 || error("故障对手预算错误")
    deadline===nothing || isfinite(deadline) || error("截止时间错误")
    max_iterations isa Integer && max_iterations>0 || error("内层轮数错误")
    start=time()
    stop=deadline===nothing ? start+budget_sec : min(deadline, start+budget_sec)
    r=Dict{String,Any}(
        "schema"=>"r7-adversary-result-v1",
        "version"=>"r7_inner_indicator_v1",
        "run_id"=>"r7-adversary-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "preplan_id"=>c.data["preplan_id"],
        "objective_kind"=>"worst_expected_unserved_energy_MWh",
        "preplan_optimality_verified"=>false,
        "author_literal_algorithm"=>false,
        "iterations"=>Any[],
        "status"=>"budget_exhausted",
        "budget_sec"=>Float64(budget_sec),
        "max_iterations"=>max_iterations,
        "stop_on_violation"=>stop_on_violation,
        "julia_version"=>string(VERSION),
        "utc"=>string(now(UTC)),
        "source_hashes_at_solve"=>r7_adversary_science_hashes(),
    )
    zs=Vector{Int}[]
    for k in 1:max_iterations
        time()<stop || break
        master=r7_solve_adversary_master(c, zs, optimizer, stop)
        it=Dict{String,Any}("master"=>master)
        push!(r["iterations"], it)
        if !haskey(master, "validation") || !master["validation"]["model_pass"]
            r["status"]=haskey(master, "values") ? "adversary_validation_failed" : master["status"]
            break
        end
        if time()>=stop
            r["status"]="budget_exhausted"
            break
        end
        gamma=master["values"]["fault"]
        rec=solve_r7_recovery(
            c,
            gamma;
            optimizer = recovery_optimizer,
            budget_sec = max(0, stop-time()),
            deadline = stop,
        )
        it["recovery"]=rec
        if rec["candidate_accepted"]
            z=round.(Int, vec(r7_unpack(rec["values"], "z")))
            if !(z in zs)
                it["added_topology"]=z
                push!(zs, z)
            end
        end
        checked=validate_r7_adversary(c, r)
        if checked["infeasible_recovery_certified"]
            r["status"]="infeasible_recovery_certified"
            break
        elseif checked["gap_certified"]
            r["status"]="worst_loss_certified"
            break
        elseif stop_on_violation && checked["threshold_status"]=="violation_certified"
            r["status"]="threshold_counterexample_certified"
            break
        elseif !rec["candidate_accepted"]
            r["status"]="recovery_"*rec["status"]
            break
        elseif !haskey(it, "added_topology")
            r["status"]="duplicate_topology_gap_unresolved"
            break
        elseif k==max_iterations
            r["status"]="iteration_limit"
        end
    end
    r["validation"]=validate_r7_adversary(c, r)
    r["elapsed_sec"]=time()-start
    r
end
