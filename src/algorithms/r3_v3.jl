# 四个角色按原始阶段排序，平局保留最早阶段；同流量只尝试一次。
function r3_v3_candidates(c, stages)
    ids=Int[]
    for s in stages
        get(s, "stage", "")=="pressure_reconstruction" || continue
        i=get(s, "sensitivity_source_stage", 0)
        i>0 && !(i in ids) && push!(ids, i)
    end
    sort!(ids)
    isempty(ids) && return Dict{String,Any}[]
    cost=ids[argmin(stages[i]["operating_cost"] for i in ids)]
    score=ids[argmin(r3_physical_score(c, reconstruct_r3_pressure(c, stages[i])) for i in ids)]
    roles=[
        "minimum_violation"=>score,
        "minimum_cost"=>cost,
        "recent"=>last(ids),
        "first"=>first(ids),
    ]
    bank=Dict{String,Any}[]
    for (role, i) in roles
        hash=r2_flow_hash(r3_matrix(stages[i]["values"]["m_pipe"]))
        existing=findfirst(r->r["flow_sha256"]==hash, bank)
        if isnothing(existing)
            push!(bank, Dict("roles"=>[role], "stage"=>i, "flow_sha256"=>hash))
        else
            push!(bank[existing]["roles"], role)
        end
    end
    return bank
end

function r3_stationarity_gate(local_result, merit)
    return get(local_result, "status", "")=="local_checked" &&
           isempty(get(local_result, "switches", ["unknown"])) &&
           get(get(local_result, "kkt", Dict()), "trusted", false) &&
           !get(local_result, "trust_binding", true) &&
           get(local_result, "direction_norm", Inf)<=1e-4 &&
           abs(merit-get(local_result, "predicted_merit", Inf))<=1e-6
end

function r3_check_stationarity(c, m, i, l, evaluate, stages, optimizer; radius, operation, deadline)
    probes=[Dict{String,Any}("stage"=>i, "local"=>l)]
    for _ in 1:2
        r3_clock()<deadline ||
            return Dict("checked"=>false, "reason"=>"budget_exhausted", "probes"=>probes)
        j, mode, merit=evaluate(m; sensitivity = true)
        mode=="dispatch" ||
            return Dict("checked"=>false, "reason"=>"subproblem_recheck_failed", "probes"=>probes)
        lr=r3_local_solve(c, stages[j], optimizer; mode = :dispatch, radius, operation, deadline)
        push!(probes, Dict("stage"=>j, "local"=>lr))
        r3_stationarity_gate(lr, merit) ||
            return Dict("checked"=>false, "reason"=>"local_recheck_failed", "probes"=>probes)
    end
    costs=[stages[p["stage"]]["operating_cost"] for p in probes]
    spread=(maximum(costs)-minimum(costs))/max(1, maximum(abs, costs))
    return Dict(
        "checked"=>spread<=1e-6,
        "reason"=>spread<=1e-6 ? "local_stationarity_checked" : "objective_dispersion",
        "relative_dispersion"=>spread,
        "probes"=>probes,
        "scope"=>"smooth_relaxed_local_model",
    )
end

function r3_v3_finalize!(
    c,
    out,
    pushstage;
    optimizer,
    convex_optimizer,
    operation,
    start,
    deadline,
    options,
)
    stages=out["stages"]
    bank=r3_v3_candidates(c, stages)
    out["candidate_bank"]=bank
    final=out["final_stage"]
    best=final>0 ? stages[final]["operating_cost"] : Inf
    if final==0 && options.physical_recovery && !isempty(bank)
        i=bank[1]["stage"]
        center=reconstruct_r3_pressure(c, stages[i])
        stop=min(start+0.9out["budget_sec"], r3_clock()+0.2out["budget_sec"])
        recovery=r3_restore_physical(c, center, convex_optimizer; operation, deadline = stop)
        out["physical_restoration"]=Dict(
            "status"=>recovery.status,
            "source_stage"=>i,
            "trace"=>recovery.trace,
        )
        if validate_r3_solution(c, recovery.candidate).physical_pass
            j=pushstage("v3_restored_physical_candidate", recovery.candidate)
            out["final_stage"]=j
            best=stages[j]["operating_cost"]
            pushfirst!(
                bank,
                Dict(
                    "roles"=>["restored_physical"],
                    "stage"=>j,
                    "flow_sha256"=>r2_flow_hash(r3_matrix(stages[j]["values"]["m_pipe"])),
                ),
            )
        end
    end
    # 最终阶段至多占预算的10%；未用的恢复时间不扩成新的求解预算。
    final_deadline=min(deadline, r3_clock()+0.1out["budget_sec"])
    out["final_attempts"]=Int[]
    if !isnothing(optimizer)
        for (k, candidate) in enumerate(bank)
            remaining=final_deadline-r3_clock()
            remaining>0 || break
            i=candidate["stage"]
            flow=stages[i]["values"]["m_pipe"]
            r=r3_solve(
                c,
                ()->build_r3_subproblem(c, flow; operation, physical = true),
                optimizer;
                deadline = final_deadline,
                budget_sec = remaining/(length(bank)-k+1),
            )
            j=pushstage("v3_final_physical", r)
            push!(out["final_attempts"], j)
            if stages[j]["physics_pass"] && stages[j]["operating_cost"]<best
                best=stages[j]["operating_cost"]
                out["final_stage"]=j
            end
        end
    end
    final=out["final_stage"]
    out["status"]=final>0 ? "physical_feasible" : "no_verified_physical_solution"
    out["cost_optimization_complete"]=final>0 &&
                                      stages[final]["status"]=="solver_optimal" &&
                                      stages[final]["objective_kind"]=="operating_cost"
    out["elapsed_sec"]=r3_clock()-start
    return out
end

# 重读时核查恢复接受条件与局部见证；中间点不会进入正式成功阶段。
function r3_validate_v3(c, result)
    stages=result["stages"]
    operation=haskey(result, "operation") ? r3_operation_from_dict(result["operation"]) : nothing
    expected=r3_v3_candidates(c, stages)
    actual=[x for x in result["candidate_bank"] if !("restored_physical" in x["roles"])]
    actual==expected || throw(ArgumentError("v3候选角色/排序不一致"))
    sr=get(result, "stationarity_check", nothing)
    if get(result, "local_stationarity_checked", false)
        !isnothing(sr) && sr["checked"] && length(sr["probes"])==3 ||
            throw(ArgumentError("驻点复核次数不足"))
        costs=Float64[]
        flows=Any[]
        for p in sr["probes"]
            s=stages[p["stage"]]
            l=p["local"]
            validate_r3_solution(c, s).model_pass &&
            r3_stationarity_gate(l, s["operating_cost"]/r3_cost_scale(c)) ||
                throw(ArgumentError("驻点证据不满足门槛"))
            b=build_r3_local_step(c, s; radius = l["radius"], operation)
            r3_local_kkt_witness(b.model, l["values"], l["kkt"]) ||
                throw(ArgumentError("驻点乘子独立重算失败"))
            vals=Dict(zip(all_variables(b.model), l["values"]))
            isempty(primal_feasibility_report(b.model, vals; atol = 1e-6)) ||
                throw(ArgumentError("驻点原始变量见证失败"))
            push!(costs, s["operating_cost"])
            push!(flows, r3_matrix(s["values"]["m_pipe"]))
        end
        (maximum(costs)-minimum(costs))/max(1, maximum(abs, costs))<=1e-6 ||
            throw(ArgumentError("驻点目标不稳定"))
        all(maximum(abs, m-flows[1])<=1e-6 for m in flows) ||
            throw(ArgumentError("驻点复核改变流量"))
    end
    restoration=get(result, "physical_restoration", nothing)
    previous=isnothing(restoration) ? nothing :
             reconstruct_r3_pressure(c, stages[restoration["source_stage"]])
    for row in get(get(result, "physical_restoration", Dict()), "trace", Any[])
        row["center"]["values"]==previous["values"] || throw(ArgumentError("恢复状态链断裂"))
        haskey(row, "candidate") || continue
        before=r3_physical_merit(c, row["center"]["values"]).value
        after=r3_physical_merit(c, row["candidate"]["values"]).value
        abs(before-row["before"])<=1e-10 && abs(after-row["after"])<=1e-10 ||
            throw(ArgumentError("恢复残差证据不同"))
        if row["kind"]=="physical_local"
            b=build_r3_physical_step(c, row["center"]; radius = row["radius"], operation)
            vals=Dict(zip(all_variables(b.model), row["linear_values"]))
            isempty(primal_feasibility_report(b.model, vals; atol = 1e-6)) ||
                throw(ArgumentError("恢复局部见证失败"))
            for (key, variables) in b.variables
                startswith(key, "alpha_") ||
                    startswith(key, "beta_") ||
                    startswith(key, "kappa_") ||
                    begin
                        expected=r2_extract(map(x->vals[x], variables))
                        expected==row["candidate"]["values"][key] ||
                            throw(ArgumentError("恢复候选与局部变量见证不同"))
                    end
            end
            prediction=value(v->vals[v], b.merit_expression)
            abs(prediction-row["predicted"])<=1e-8 || throw(ArgumentError("恢复预测证据不同"))
            if row["accepted"]
                before>prediction && (before-after)/(before-prediction)>=0.1 && after<before ||
                    throw(ArgumentError("错误接受恢复试探"))
            end
        elseif row["accepted"]
            after<before-1e-12 || throw(ArgumentError("邻段没有实际改善"))
        end
        if row["accepted"]
            previous=row["candidate"]
        end
    end
    return true
end
