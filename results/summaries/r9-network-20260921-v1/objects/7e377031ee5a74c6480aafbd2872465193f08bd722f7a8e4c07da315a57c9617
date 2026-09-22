function r4_distributed_solve!(b, deadline)
    result=Dict{String,Any}("status"=>"not_run", "actor"=>b.actor)
    time()>=deadline && (result["status"] = "time_limit"; return result)
    try
        set_silent(b.model)
        set_time_limit_sec(b.model, max(0.001, deadline-time()))
        optimize!(b.model)
        result["termination"]=string(termination_status(b.model))
        result["solver"]=solver_name(b.model)
        result["model_types"]=string.(list_of_constraint_types(b.model))
        if has_values(b.model) &&
           primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
            result["values"]=Dict(k=>r2_extract(x) for (k, x) in b.variables)
            result["message"]=r2_extract(b.message)
            result["peer"]=r2_extract(b.peer)
            result["cost"]=value(b.cost)
            result["augmented_objective"]=objective_value(b.model)
            # 内层界属于增广块目标，不是原系统费用界。
            if dual_status(b.model)==MOI.FEASIBLE_POINT
                bound=try
                    dual_objective_value(b.model)
                catch
                    NaN
                end
                if isfinite(bound)
                    result["augmented_bound"]=bound
                    result["augmented_relative_gap"]=abs(result["augmented_objective"]-bound)/max(
                        1,
                        abs(result["augmented_objective"]),
                    )
                end
            end
        end
        result["status"]=termination_status(b.model)==MOI.OPTIMAL && haskey(result, "values") ?
                         "solved" :
                         termination_status(b.model)==MOI.INFEASIBLE ? "infeasible_certified" :
                         termination_status(b.model)==MOI.TIME_LIMIT ? "time_limit" :
                         "solver_failure"
    catch err
        err isa InterruptException && rethrow()
        message=sprint(showerror, err)
        result["status"]=occursin(r"(?i)license|licence", message) ? "license_missing" :
                         "solver_error"
        result["error"]=replace(message, r"[A-Za-z]:[\\/][^\s\n]*"=>"[local path]")
    end
    return result
end

function r4_normalized_message(r, scales)
    x=r4_matrix(r["message"])
    return [x[k, t]/scales["boundary"][mod1(k, 4)] for k in axes(x, 1), t in axes(x, 2)]
end

function r4_distributed_candidate(c, agents, operator, purpose)
    T=c.data["T"]
    s=deepcopy(purpose==:swm ? operator["values"] : agents[1]["values"])
    keys_local=(
        "P_CHP",
        "P_PV",
        "P_HP",
        "P_EB",
        "P_ch",
        "P_dis",
        "P_D",
        "H_D",
        "H_src",
        "w_P",
        "w_H",
        "E",
    )
    for j in 1:2
        i=j+1
        for key in keys_local
            s[key][i]=copy(agents[j]["values"][key][i])
        end
        c.data["actors"][i]["BS_power_max"]>0 && (s["z"]=copy(agents[j]["values"]["z"]))
    end
    if purpose==:agnb
        for (k, carrier) in enumerate(("P", "H"))
            for side in ("buy", "sell")
                s[carrier*"_"*side]=[
                    zeros(T),
                    copy(agents[1]["values"][carrier*"_"*side]),
                    copy(agents[2]["values"][carrier*"_"*side]),
                ]
            end
            s[carrier*"_peer"]=copy(agents[1]["peer"][k])
            s[carrier*"_peer_abs"]=abs.(s[carrier*"_peer"])
        end
    end
    r=Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "spec"=>r4_spec(R4Spec(), c),
        "stage"=>purpose==:swm ? "central" : "trading",
        "values"=>s,
        "status"=>"distributed_candidate",
        "cost_optimization_complete"=>false,
    )
    r["solver_objective"]=sum(x["cost"] for x in agents)+(purpose==:swm ? operator["cost"] : 0.0)
    r["validation"]=purpose==:swm ? validate_r4_solution(c, r) : validate_r4_trading(c, r)
    r["operating_cost"]=purpose==:swm ? r4_ledger(c, s)["operating_cost"] :
                        r4_trading_ledger(c, s)["aggregator_cost"]
    return r
end

function r4_peer_inner!(blocks, scales, spec, deadline, z, u, qz, qu; outer, kstart)
    trace=Dict{String,Any}[]
    agents=Dict{String,Any}[]
    for k in 1:(outer ? spec.inner_iterations : spec.max_iterations)
        time()>=deadline && return (; status = "time_limit", agents, trace, qz, qu)
        agents=Dict{String,Any}[]
        for j in 1:2
            rows=(4(j-1)+1):(4j)
            r4_set_distributed_objective!(
                blocks[j],
                scales,
                spec;
                target = outer ? z[rows, :] : nothing,
                dual = outer ? u[rows, :] : nothing,
                peer_target = qz[j],
                peer_dual = qu[j],
            )
            r=r4_distributed_solve!(blocks[j], deadline)
            push!(agents, r)
            r["status"]=="solved" || return (; status = r["status"], agents, trace, qz, qu)
        end
        q=[r4_matrix(r["peer"]) ./ reshape(scales["peer"], 2, 1) for r in agents]
        old=deepcopy(qz)
        qz=collect(r4_peer_consensus(q[1], q[2], qu[1], qu[2]))
        primal=maximum(maximum(abs, q[j]-qz[j]) for j in 1:2)
        dual=spec.peer_rho*maximum(maximum(abs, qz[j]-old[j]) for j in 1:2)
        qu=[qu[j]+q[j]-qz[j] for j in 1:2]
        push!(
            trace,
            Dict(
                "outer"=>kstart,
                "iteration"=>k,
                "primal"=>primal,
                "dual"=>dual,
                "q"=>[r2_extract(x) for x in q],
                "z"=>[r2_extract(x) for x in qz],
                "u"=>[r2_extract(x) for x in qu],
                "augmented_objectives"=>[r["augmented_objective"] for r in agents],
                "block_gaps"=>[get(r, "augmented_relative_gap", NaN) for r in agents],
            ),
        )
        primal<=1e-7 && dual<=1e-7 && return (; status = "inner_converged", agents, trace, qz, qu)
    end
    return (; status = "inner_iteration_limit", agents, trace, qz, qu)
end

"""
    solve_r4_distributed(case; optimizer, modes, purpose=:swm,
                         spec=R4DistributedSpec(), budget_sec=600)

执行一致增广拉格朗日的目标协调与双边合同ADMM。固定电池模式、零初始通信，
不接收集中参考解或物理修正初值；purpose=:agnb仅运行非零合同交易内循环。
外层AG→运营商→u更新；共享墙钟预算覆盖建模与全部内外层求解。串行调度独立块，
不是网络部署或加密隐私实现。保存真实通信、乘子、费用与阶段状态；不收敛时保留负结果。
A4判据外还要求合并候选通过A1采用模型；原电网等式单列，不能由共识收敛推出。
"""
function solve_r4_distributed(
    c::R4Case;
    optimizer,
    modes,
    purpose = :swm,
    spec = R4DistributedSpec(),
    budget_sec = 600.0,
)
    isfinite(budget_sec)&&budget_sec>0 || error("预算错误")
    purpose in (:swm, :agnb) || error("目标错误")
    modes!==nothing && length(modes)==c.data["T"] && all(x->x in (0, 1), modes) ||
        error("须显式固定电池模式")
    start=time()
    deadline=start+budget_sec
    hashes=r4_science_hashes()
    scales=r4_distributed_scales(c)
    T=c.data["T"]
    result=Dict{String,Any}(
        "schema"=>"r4-distributed-run-v1",
        "algorithm"=>"r4_atc_admm_checked_v1",
        "input_sha256"=>c.sha256,
        "spec"=>r4_spec(R4Spec(), c),
        "purpose"=>String(purpose),
        "options"=>r4_distributed_options(spec),
        "modes"=>Int.(modes),
        "scales"=>scales,
        "budget_sec"=>Float64(budget_sec),
        "trace"=>Dict{String,Any}[],
        "inner_trace"=>Dict{String,Any}[],
        "status"=>"not_run",
        "cost_optimization_complete"=>false,
        "source_hashes_at_solve"=>hashes,
    )
    z=zeros(8, T)
    u=zeros(8, T)
    qz=[zeros(2, T), zeros(2, T)]
    qu=[zeros(2, T), zeros(2, T)]
    try
        blocks=[build_r4_distributed_block(c; actor = i, modes, optimizer, purpose) for i in 2:3]
        operator=purpose==:swm ? build_r4_distributed_block(c; actor = 1, modes, optimizer) :
                 nothing
        for k in 1:spec.max_iterations
            time()>=deadline && (result["status"] = "time_limit"; break)
            inner=r4_peer_inner!(
                blocks,
                scales,
                spec,
                deadline,
                z,
                u,
                qz,
                qu;
                outer = purpose==:swm,
                kstart = k,
            )
            qz, qu=inner.qz, inner.qu
            append!(result["inner_trace"], inner.trace)
            if inner.status!="inner_converged"
                result["last_attempt_agents"]=inner.agents
                result["status"]=inner.status
                if purpose==:agnb &&
                   length(inner.agents)==2 &&
                   all(a["status"]=="solved" for a in inner.agents)
                    candidate=r4_distributed_candidate(c, inner.agents, nothing, purpose)
                    result["agents"]=inner.agents
                    result["candidate"]=candidate
                end
                break
            end
            agents=inner.agents
            if purpose==:agnb
                candidate=r4_distributed_candidate(c, agents, nothing, purpose)
                result["candidate"]=candidate
                result["agents"]=agents
                result["status"]=candidate["validation"]["model_pass"] ? "consensus_converged" :
                                 "candidate_A1_failed"
                break
            end
            x=vcat((r4_normalized_message(r, scales) for r in agents)...)
            old=copy(z)
            r4_set_distributed_objective!(operator, scales, spec; target = x, dual = u)
            r=r4_distributed_solve!(operator, deadline)
            r["status"]=="solved" ||
                (result["status"] = r["status"]; result["last_attempt_operator"] = r; break)
            z=r4_normalized_message(r, scales)
            primal=maximum(abs, x-z)
            dual=spec.rho*maximum(abs, z-old)
            u+=x-z
            candidate=r4_distributed_candidate(c, agents, r, purpose)
            result["candidate"]=candidate
            result["agents"]=agents
            result["operator"]=r
            push!(
                result["trace"],
                Dict(
                    "iteration"=>k,
                    "primal"=>primal,
                    "dual"=>dual,
                    "x"=>r2_extract(x),
                    "z"=>r2_extract(z),
                    "u"=>r2_extract(u),
                    "candidate_cost"=>candidate["operating_cost"],
                    "model_pass"=>candidate["validation"]["model_pass"],
                    "electric_original_pass"=>candidate["validation"]["electric_original_pass"],
                    "operator_augmented_objective"=>r["augmented_objective"],
                    "operator_block_gap"=>get(r, "augmented_relative_gap", NaN),
                    "elapsed_sec"=>time()-start,
                ),
            )
            # 小A4共识误差不等于A1。继续同一算法，禁止暗中集中重调来制造可行。
            if primal<=1e-4 && dual<=1e-4 && candidate["validation"]["model_pass"]
                result["status"]="consensus_converged"
                break
            end
            result["status"]="iteration_limit"
        end
    catch err
        err isa InterruptException && rethrow()
        message=sprint(showerror, err)
        result["status"]=occursin(r"(?i)license|licence", message) ? "license_missing" :
                         "implementation_error"
        result["error"]=replace(message, r"[A-Za-z]:[\\/][^\s\n]*"=>"[local path]")
    end
    result["elapsed_sec"]=time()-start
    hashes==r4_science_hashes() || error("求解期间科学源码改变")
    result["validation"]=validate_r4_distributed(c, result)
    return result
end
