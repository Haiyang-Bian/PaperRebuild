"""区分许可/不支持与其它异常；JuMP在构造不支持的约束时也可能抛普通ErrorException。"""
function r9_distributed_error_status(err, fallback)
    message=sprint(showerror, err)
    occursin(r"(?i)licen[cs]e", message) && return "license_missing"
    unsupported=err isa MOI.UnsupportedConstraint ||
                err isa MOI.UnsupportedAttribute ||
                occursin(r"Constraints of type .* are not supported by the solver", message)
    unsupported ? "unsupported_solver" : fallback
end

"""R9-DC4：在共同单调时钟截止前求一个块；原始目标与增广目标/界分别保存。"""
function r9_distributed_solve_block!(b, deadline; objective_record = :reported)
    objective_record in (:reported, :separate) || error("未知目标记录语义")
    start=r3_clock()
    r=Dict{String,Any}(
        "actor"=>b.actor,
        "input_sha256"=>b.input_sha256,
        "status"=>"time_limit",
        "termination"=>"NOT_RUN",
        "primal_status"=>"NO_SOLUTION",
        "allocated_budget_sec"=>max(0.0, deadline-start),
        "convex_fixed_mode"=>b.convex_fixed_mode,
        "model_types"=>b.model_types,
    )
    if start<deadline
        try
            set_silent(b.model)
            set_time_limit_sec(b.model, max(0.001, deadline-r3_clock()))
            optimize!(b.model)
            term=termination_status(b.model)
            r["termination"]=string(term)
            r["primal_status"]=string(primal_status(b.model))
            r["solver"]=solver_name(b.model)
            if has_values(b.model) &&
               primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                r["values"]=Dict(k=>r2_extract(x) for (k, x) in b.variables)
                r["message"]=r2_extract(b.message)
                r["cost"]=value(b.cost)
                r["augmented_objective"]=objective_value(b.model)
                if objective_record==:separate
                    # 原报告值保留；数学目标另从当前变量求值，不改写求解器证书。
                    r["augmented_objective_at_primal"]=value(objective_function(b.model))
                    difference=r["augmented_objective"]-r["augmented_objective_at_primal"]
                    scale=max(
                        1.0,
                        abs(r["augmented_objective"]),
                        abs(r["augmented_objective_at_primal"]),
                    )
                    r["solver_objective_report_error"]=difference
                    r["solver_objective_report_pass"]=abs(difference)<=1e-9*scale
                end
                # 可选界读取失败不应删除已经保存的候选；界只属于当前增广子问题。
                bound=try
                    b.convex_fixed_mode && dual_status(b.model)==MOI.FEASIBLE_POINT ?
                    dual_objective_value(b.model) : objective_bound(b.model)
                catch
                    NaN
                end
                if isfinite(bound)
                    r["augmented_bound"]=bound
                    r["augmented_relative_gap"]=max(0.0, r["augmented_objective"]-bound)/max(
                        1.0,
                        abs(r["augmented_objective"]),
                    )
                    r["augmented_bound_excess"]=max(0.0, bound-r["augmented_objective"])/max(
                        1.0,
                        abs(r["augmented_objective"]),
                    )
                end
            end
            r["status"]=term==MOI.OPTIMAL && haskey(r, "values") ? "solved" :
                        term==MOI.INFEASIBLE ? "infeasible_certified" :
                        term==MOI.TIME_LIMIT ?
                        (haskey(r, "values") ? "time_limit_with_candidate" : "time_limit") :
                        term==MOI.INFEASIBLE_OR_UNBOUNDED ? "infeasible_or_unbounded" :
                        "solver_failure"
        catch err
            err isa InterruptException && rethrow()
            message=sprint(showerror, err)
            r["status"]=r9_distributed_error_status(err, "solver_error")
            r["error_type"]=string(typeof(err))
            r["error"]=replace(message, r"[A-Za-z]:[\\/][^\s\n]*"=>"[local path]")
        end
    end
    r["elapsed_sec"]=r3_clock()-start
    r
end

"""
    solve_r9_distributed(case; optimizer, modes=nothing, spec=R9DistributedSpec(), budget_sec=600, deadline=nothing, on_raw_result=nothing, objective_record=:reported)

R9-DC4/DC5：从零消息执行各聚合商→运营商→缩放乘子更新，串行模拟多主体协调。
共享最多600秒，包括建模、全部块求解与逐轮独立合并检查；不调用集中参考或物理修正。
每块仅构建一次。fixed版为固定模式连续SOCP，mip版为明确标注的整数启发式。
保留每轮原变量和消息；A4通过后仍要求合并采用模型A1。原电网等式另报，
保存最好模型与最好原电网候选，不把增广块界相加为系统界，不认证完整热水力。
on_raw_result可在最终独立核验前接收原始结果的深副本，用于保存诊断证据；默认不写文件。
回调不能修改原结果，耗时计入预算。核验异常仍抛出，不能因保存了原值而视为记录通过。
objective_record=:reported保持v1旧核对；显式:separate使用v2记录，分别保留求解器报告目标、
原变量数学目标与同一1e-9门槛的报告一致性。报告不一致仍标为失败，不冒充子问题精确最优性。
它不改变更新式、子块状态要求、A1/A4或控制量；记录可重算、报告一致与调度可行分别评价。
可选deadline为本机r3_clock的绝对截止时间，用于让装载/JIT/建模共用外部预算；不传时旧行为保持。
loop_budget_sec记录调用时真正剩余的外层时间，最终核验/保存仍由调用者的完整墙钟预算单独检查。
"""
function solve_r9_distributed(
    c::R9TradingCase;
    optimizer,
    modes = nothing,
    spec = R9DistributedSpec(),
    budget_sec = 600.0,
    deadline = nothing,
    on_raw_result = nothing,
    objective_record = :reported,
)
    objective_record in (:reported, :separate) || error("未知目标记录语义")
    isfinite(budget_sec) && 0<budget_sec<=600 || error("完整分布运行预算须在(0,600]秒")
    deadline===nothing || (deadline isa Real && isfinite(deadline)) || error("截止时间须有限")
    selected=r9_distributed_modes(c, modes, spec)
    start=r3_clock()
    shared_deadline=deadline!==nothing
    deadline=shared_deadline ? min(start+budget_sec, Float64(deadline)) : start+budget_sec
    hashes=r9_trading_science_hashes()
    box=r9_boundary_contract(c)
    C=r9_distributed_cost_scale(c)
    r=Dict{String,Any}(
        "schema"=>objective_record==:reported ? "r9-distributed-run-v1" : "r9-distributed-run-v2",
        "algorithm"=>string(spec.algorithm),
        "input_sha256"=>c.sha256,
        "model_version"=>r9_trading_version(c),
        "origin"=>c.data["origin"],
        "rho"=>spec.rho,
        "max_iterations"=>spec.max_iterations,
        "consensus_tolerance"=>1e-4,
        "initialization"=>"zero_messages_and_scaled_duals",
        "cost_scale"=>C,
        "boundary_scale"=>box.scale,
        "budget_sec"=>Float64(budget_sec),
        "status"=>"iteration_limit",
        "trace"=>Dict{String,Any}[],
        "source_hashes_at_solve"=>hashes,
        "best_model_iteration"=>0,
        "best_physical_iteration"=>0,
        "cost_optimization_complete"=>false,
        "central_solution_injected"=>false,
        "full_thermal_physics_certified"=>false,
    )
    if objective_record==:separate
        r["objective_record"]="separate"
        r["subproblem_accuracy_certified"]=false
    end
    shared_deadline && (r["loop_budget_sec"]=max(0.0, deadline-start))
    selected===nothing || (r["fixed_modes"]=Dict(k=>r2_extract(v) for (k, v) in selected))
    z=zeros(size(box.lower))
    u=zeros(size(z))
    best_model=Inf
    best_physical=Inf
    blocks=Any[]
    try
        for i in eachindex(c.data["actors"])
            r3_clock()>=deadline && (r["status"] = "time_limit"; break)
            b=build_r9_distributed_block(c; actor = i, modes = selected, optimizer)
            spec.algorithm==:r9_boundary_admm_fixed_v1 &&
                !b.convex_fixed_mode &&
                error("固定模式版本仍包含整数")
            push!(blocks, b)
        end
        r["built_block_count"]=length(blocks)
        if length(blocks)==length(c.data["actors"])
            for k in 1:spec.max_iterations
                r3_clock()>=deadline && (r["status"] = "time_limit"; break)
                agents=Dict{String,Any}[]
                for b in blocks[2:end]
                    r9_distributed_objective!(b, z[b.rows, :], u[b.rows, :], C, spec.rho)
                    block=r9_distributed_solve_block!(b, deadline; objective_record)
                    push!(agents, block)
                    block["status"]=="solved" || break
                end
                if length(agents)!=length(blocks)-1 || any(a->a["status"]!="solved", agents)
                    r["status"]=last(agents)["status"]
                    r["last_attempt"]=Dict("iteration"=>k, "agents"=>agents)
                    break
                end
                x=vcat(
                    (
                        r4_matrix(a["message"]) ./
                        reshape(box.scale[blocks[a["actor"]].rows], :, 1) for a in agents
                    )...,
                )
                old=copy(z)
                r9_distributed_objective!(blocks[1], x, u, C, spec.rho)
                operator=r9_distributed_solve_block!(blocks[1], deadline; objective_record)
                if operator["status"]!="solved"
                    r["status"]=operator["status"]
                    r["last_attempt"]=Dict("iteration"=>k, "agents"=>agents, "operator"=>operator)
                    break
                end
                z=r4_matrix(operator["message"]) ./ reshape(box.scale, :, 1)
                primal=maximum(abs, x-z)
                dual=spec.rho*maximum(abs, z-old)
                u+=x-z
                candidate=r9_distributed_candidate(c, agents, operator)
                v=candidate["validation"]
                cost=candidate["operating_cost_CNY"]
                push!(
                    r["trace"],
                    Dict(
                        "iteration"=>k,
                        "x"=>r2_extract(x),
                        "z"=>r2_extract(z),
                        "u"=>r2_extract(u),
                        "primal"=>primal,
                        "dual"=>dual,
                        "agents"=>agents,
                        "operator"=>operator,
                        "candidate_validation"=>r9_trading_summary(v),
                        "operating_cost_CNY"=>cost,
                        "elapsed_sec"=>r3_clock()-start,
                    ),
                )
                if v["model_pass"] && cost<best_model
                    best_model=cost
                    r["best_model_iteration"]=k
                end
                if v["model_pass"] && v["electric_original_pass"] && cost<best_physical
                    best_physical=cost
                    r["best_physical_iteration"]=k
                end
                if primal<=1e-4 && dual<=1e-4 && v["model_pass"]
                    r["status"]="consensus_converged"
                    break
                end
            end
        end
    catch err
        err isa InterruptException && rethrow()
        msg=sprint(showerror, err)
        r["status"]=r9_distributed_error_status(err, "algorithm_error")
        r["error_type"]=string(typeof(err))
        r["error"]=replace(msg, r"[A-Za-z]:[\\/][^\s\n]*"=>"[local path]")
    end
    r["source_unchanged"]=hashes==r9_trading_science_hashes()
    r["elapsed_sec"]=r3_clock()-start
    r["budget_overrun"]=r["elapsed_sec"]>budget_sec
    on_raw_result===nothing || on_raw_result(deepcopy(r))
    r["elapsed_sec"]=r3_clock()-start
    r["budget_overrun"]=r["elapsed_sec"]>budget_sec
    r["validation"]=validate_r9_distributed(c, r)
    r["elapsed_sec"]=r3_clock()-start
    r["budget_overrun"]=r["elapsed_sec"]>budget_sec
    r
end
