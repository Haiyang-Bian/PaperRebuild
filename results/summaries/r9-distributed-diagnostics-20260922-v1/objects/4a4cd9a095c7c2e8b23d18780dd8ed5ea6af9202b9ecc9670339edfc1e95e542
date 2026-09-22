function r3_baseline_kkt_witness(c, stage, operation)
    s=get(stage, "sensitivity", Dict())
    get(s, "trusted", false) || return false
    haskey(stage, "sensitivity_primal_order") || return false
    m=r3_matrix(stage["values"]["m_pipe"])
    mode=stage["objective_kind"]=="normalized_slack" ? :diagnostic : :dispatch
    # 重建方程但不求解，用已保存原变量与乘子检验每条KKT关系。
    b=build_r3_subproblem(c, m; operation, mode)
    values=stage["sensitivity_primal_order"]
    length(values)==num_variables(b.model) || return false
    x=Dict(zip(all_variables(b.model), values))
    for (key, vars) in b.variables
        saved=ndims(vars)==1 ? stage["values"][key] : r3_matrix(stage["values"][key])
        size(vars)==size(saved) || return false
        all(abs(x[vars[i]]-saved[i])<=1e-10*max(1, abs(saved[i])) for i in eachindex(vars)) ||
            return false
    end
    return r3_local_kkt_witness(b.model, values, s["kkt"])
end

function r3_validate_baseline_iteration(c, row; stages = nothing)
    errors=String[]
    operation=haskey(row, "operation") ? r3_operation_from_dict(row["operation"]) : nothing
    _, _, width=r3_flow_box(c, operation)
    divisor=ifelse.(width .> 0, width, 1.0)
    m=r2_flow_matrix(c, row["flow"])
    sd=row["baseline_spec"]
    spec=R3BaselineSpec(
        geometry = Symbol(sd["geometry"]),
        initial_displacement = sd["initial_displacement"],
    )
    sd==r3_baseline_spec(spec) || push!(errors, "baseline_spec")
    direction=nothing
    if !isnothing(stages) && row["mode"]!="unresolved"
        s=stages[row["stage"]]
        expected=s["solver_objective"]/(row["mode"]=="dispatch" ? r3_cost_scale(c) : 1.0)
        isapprox(expected, row["merit"]; rtol = 1e-10, atol = 1e-12) || push!(errors, "merit_link")
        maximum(abs, r3_matrix(s["values"]["m_pipe"])-m)<=1e-6 || push!(errors, "flow_link")
        if haskey(row, "gradient")
            r3_baseline_kkt_witness(c, s, operation) || push!(errors, "independent_kkt")
            g=r3_matrix(s["sensitivity"]["gradient"])/(
                row["mode"]=="dispatch" ? r3_cost_scale(c) : 1.0
            )
            maximum(abs, g-r3_matrix(row["gradient"]))<=1e-10 || push!(errors, "gradient_link")
        end
    end
    if haskey(row, "gradient")
        direction, gamma=r3_baseline_direction(r3_matrix(row["gradient"]), width, spec)
        isapprox(gamma, row["initial_gamma"]; rtol = 1e-10, atol = 1e-12) ||
            push!(errors, "initial_gamma")
    end
    function check_projection(p)
        p["status"]=="projected" || return
        r3_projection_witness(c, p["values"]; operation) || push!(errors, "projection_witness")
        flow=r2_flow_matrix(c, p["flow"])
        maximum(abs, flow-r3_matrix(p["values"]["m_pipe"]))<=1e-10 ||
            push!(errors, "projection_flow")
        scale=p["geometry"]=="physical_euclidean" ? ones(size(width)) : divisor
        distance=sum(
            ((flow[i]-r3_matrix(p["target"])[i])/scale[i])^2 for i in eachindex(flow) if width[i]>0;
            init = 0.0,
        )
        isapprox(distance, p["distance"]; rtol = 1e-7, atol = 1e-9) ||
            push!(errors, "projection_distance")
    end
    if haskey(row, "mapping_projection")
        p=row["mapping_projection"]
        check_projection(p)
        if p["status"]=="projected"
            p["geometry"]=="normalized_euclidean" || push!(errors, "mapping_geometry")
            maximum(abs, r3_matrix(p["target"])-(m-width .^ 2 .* r3_matrix(row["gradient"])))<=1e-10 ||
                push!(errors, "mapping_target")
            v=maximum(abs, (r3_matrix(p["flow"])-m) ./ divisor; init = 0.0)
            isapprox(v, row["projected_gradient_norm"]; atol = 1e-10) ||
                push!(errors, "mapping_norm")
        end
    end
    accepted_count=0
    for (q, trial) in enumerate(row["trials"])
        trial["backtrack"]==q-1 || push!(errors, "backtrack_order")
        p=trial["projection"]
        check_projection(p)
        isapprox(trial["gamma"], row["initial_gamma"]*0.5^(q-1); rtol = 1e-10) ||
            push!(errors, "step_halving")
        maximum(abs, r3_matrix(p["target"])-(m+trial["gamma"]*direction))<=1e-10 ||
            push!(errors, "projection_target")
        p["status"]=="projected" || continue
        p["geometry"]==string(spec.geometry) || push!(errors, "projection_geometry")
        flow=r3_matrix(p["flow"])
        slope=sum(r3_matrix(row["gradient"]) .* (flow-m))
        isapprox(slope, trial["slope"]; atol = 1e-12, rtol = 1e-9) || push!(errors, "slope")
        if haskey(trial, "stage")
            rhs=row["merit"]+1e-4*slope
            isapprox(rhs, trial["armijo_rhs"]; rtol = 1e-10, atol = 1e-12) ||
                push!(errors, "armijo_rhs")
            good=slope<0 && (
                row["mode"]=="diagnostic" && trial["mode"]=="dispatch" ||
                trial["mode"]==row["mode"] && trial["merit"]<=rhs
            )
            good==trial["accepted"] || push!(errors, "acceptance")
            if !isnothing(stages) && trial["mode"]!="unresolved"
                s=stages[trial["stage"]]
                f=s["solver_objective"]/(trial["mode"]=="dispatch" ? r3_cost_scale(c) : 1.0)
                isapprox(f, trial["merit"]; atol = 1e-12, rtol = 1e-10) ||
                    push!(errors, "trial_merit")
                maximum(abs, r3_matrix(s["values"]["m_pipe"])-flow)<=1e-6 ||
                    push!(errors, "trial_flow")
            end
        end
        if trial["accepted"]
            accepted_count+=1
            maximum(abs, flow-r3_matrix(row["accepted_flow"]))<=1e-10 ||
                push!(errors, "accepted_flow")
        end
    end
    accepted_count==Int(row["accepted"]) || push!(errors, "accepted_count")
    return (; pass = isempty(errors), errors)
end

function r3_validate_baseline(c, r)
    bank=r3_baseline_candidates(c, r)
    bank==r["candidate_bank"] || throw(ArgumentError("基线候选池证据不一致"))
    small=0
    previous=""
    for row in r["iterations"]
        row["baseline_spec"]==r["baseline_spec"] || throw(ArgumentError("迭代基线规则改变"))
        s=r["stages"][row["stage"]]
        sensitivity=get(s, "sensitivity", Dict())
        row["trusted_sensitivity"]==get(sensitivity, "trusted", false) ||
            throw(ArgumentError("灵敏度可信标志不一致"))
        row["smooth"]==get(sensitivity, "smooth", false) || throw(ArgumentError("光滑性标志不一致"))
        active=get(get(sensitivity, "kkt", Dict()), "active_signature", "")
        !isempty(previous) && active!=previous && (small=0)
        previous=active
        small==row["small_accepted_before"] || throw(ArgumentError("小变化计数不一致"))
        expected=row["mode"]=="dispatch" &&
                 small>=3 &&
                 row["trusted_sensitivity"] &&
                 row["smooth"] &&
                 get(row, "projected_gradient_norm", Inf)<=1e-4
        row["project_stop"]==expected || throw(ArgumentError("停止判据不一致"))
        for trial in row["trials"]
            trial["accepted"] || continue
            if row["mode"]==trial["mode"]=="dispatch"
                a, b=s["operating_cost"], r["stages"][trial["stage"]]["operating_cost"]
                small=abs(b-a)/max(1, abs(a))<=1e-6 ? small+1 : 0
            else
                small=0
            end
        end
    end
    any(row["project_stop"] for row in r["iterations"])==r["outer_converged"] ||
        throw(ArgumentError("外层收敛标志不一致"))
    for stage in r["stages"]
        v=validate_r3_solution(c, stage)
        (v.model_pass==stage["model_pass"] && v.physical_pass==stage["physics_pass"]) ||
            throw(ArgumentError("阶段检查标志不一致"))
    end
    length(bank)==length(r["strict_checks"]) || throw(ArgumentError("独立原等式检查缺项"))
    for (candidate, check) in zip(bank, r["strict_checks"])
        candidate["stage"]==check["source_stage"] &&
        candidate["flow_sha256"]==check["flow_sha256"] ||
            throw(ArgumentError("原等式检查来源不一致"))
        s=r["stages"][check["stage"]]
        s["stage"]=="baseline_strict_check" || throw(ArgumentError("原等式检查类型错误"))
        haskey(s, "values") &&
            r2_flow_hash(r3_matrix(s["flow_schedule"]))!=candidate["flow_sha256"] &&
            throw(ArgumentError("原等式检查修改了流量"))
    end
    strict=[r["stages"][x["stage"]] for x in r["strict_checks"]]
    r["strict_redispatch_success"]==any(s["physics_pass"] for s in strict) ||
        throw(ArgumentError("原等式成功标志不一致"))
    r["strict_cost_optimal"]==any(
        s["physics_pass"] && s["status"]=="solver_optimal" for s in strict
    ) || throw(ArgumentError("原等式费用状态不一致"))
    final=r["final_stage"]
    complete=final>0 &&
             r["stages"][final]["stage"]=="baseline_strict_check" &&
             r["stages"][final]["status"]=="solver_optimal"
    r["cost_optimization_complete"]==complete || throw(ArgumentError("费用完成状态不一致"))
    return true
end
