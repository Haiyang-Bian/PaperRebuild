function r3_local_solve(c, center, optimizer; mode, radius, operation, deadline)
    out=Dict{String,Any}("status"=>"not_run_solver", "radius"=>radius, "mode"=>string(mode))
    isnothing(optimizer) && return out
    r3_clock()<deadline || return merge(out, Dict("status"=>"budget_exhausted"))
    b=build_r3_local_step(c, center; mode, radius, operation)
    out["switches"]=b.partials.switches
    # 切换点不选择任意一段的Taylor系数；先由真实邻段试探离开边界。
    isempty(b.partials.switches) || return merge(out, Dict("status"=>"nonsmooth_requires_neighbor"))
    try
        set_optimizer(b.model, optimizer)
        set_silent(b.model)
        if occursin("Clarabel", solver_name(b.model))
            for key in ("tol_gap_abs", "tol_gap_rel", "tol_feas")
                set_optimizer_attribute(b.model, key, 1e-9)
            end
        end
        remaining=min(60.0, deadline-r3_clock())
        remaining>0 || return merge(out, Dict("status"=>"budget_exhausted"))
        set_time_limit_sec(b.model, remaining)
        optimize!(b.model)
        out["termination"]=string(termination_status(b.model))
        out["status"]="local_unresolved"
        if termination_status(b.model)==MOI.OPTIMAL && has_values(b.model)
            if isempty(primal_feasibility_report(b.model; atol = 1e-6))
                out["status"]="local_checked"
                out["flow"]=r2_extract(value.(b.variables["m_pipe"]))
                out["values"]=value.(all_variables(b.model))
                out["predicted_merit"]=value(b.merit_expression)
                out["objective"]=objective_value(b.model)
                out["direction_norm"]=maximum(abs, value.(b.steps); init = 0.0)
                out["trust_binding"]=out["direction_norm"]>=radius*(1-1e-4)
                out["switches"]=b.partials.switches
                out["kkt"]=r3_kkt(b.model)
            end
        end
    catch err
        reason=occursin("license", lowercase(sprint(showerror, err))) ? "not_run_license" :
               err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute} ?
               "unsupported_solver" : nothing
        isnothing(reason) && rethrow()
        out["status"]=reason
    end
    return out
end

function r3_pg_v2(
    c;
    optimizer,
    convex_optimizer,
    initial_flow,
    initial_run,
    budget_sec,
    max_iterations,
    local_halfspace,
    operation,
    v3_options = nothing,
)
    isfinite(budget_sec) && 0<budget_sec<=600 || throw(ArgumentError("预算须在(0,600]秒"))
    1<=max_iterations<=200 || throw(ArgumentError("轮数须在1至200之间"))
    isnothing(initial_flow)||isnothing(initial_run) || throw(ArgumentError("初值入口互斥"))
    start=r3_clock()
    deadline=start+budget_sec
    outer=deadline-min(60.0, 0.1budget_sec)
    isnothing(v3_options) || (outer=start+0.7budget_sec)
    lo, hi, width=r3_flow_box(c, operation)
    divisor=ifelse.(width .> 0, width, 1.0)
    stages=Dict{String,Any}[]
    trace=Dict{String,Any}[]
    out=Dict{String,Any}(
        "schema"=>"r3-run-v1",
        "algorithm"=>"r3_pg_checked_v2",
        "trace_schema"=>"r3-pg-trace-v2",
        "input_sha256"=>c.sha256,
        "origin"=>"synthetic",
        "budget_sec"=>budget_sec,
        "max_iterations"=>max_iterations,
        "stages"=>stages,
        "iterations"=>trace,
        "source_hashes_at_solve"=>r2_science_hashes(),
        "final_stage"=>0,
        "best_subproblem_stage"=>0,
        "cost_optimization_complete"=>false,
        "outer_converged"=>false,
        "cost_scale"=>r3_cost_scale(c),
        "local_halfspace"=>local_halfspace,
    )
    if !isnothing(v3_options)
        out["algorithm"]="r3_pg_checked_v3"
        out["trace_schema"]="r3-pg-trace-v3"
        out["candidate_policy"]="all_dispatch_v1"
        out["local_stationarity_checked"]=false
        out["physical_recovery_enabled"]=v3_options.physical_recovery
        out["stationarity_check_enabled"]=v3_options.stationarity_check
    end
    if !isnothing(operation)
        out["operation"]=r3_operation_dict(operation)
        out["operation_sha256"]=r3_operation_hash(out["operation"])
    end
    bestcost=Inf
    bestphysical=Inf
    function pushstage(name, r)
        # 子阶段引用根运行的同一源码快照，避免重复数千份哈希表。
        pop!(r, "source_hashes_at_solve", nothing)
        r["source_snapshot"]="parent_run"
        r["stage"]=name
        isnothing(v3_options) || (r["v3_physical_review"]=true)
        valid=validate_r3_solution(c, r)
        r["model_pass"], r["physics_pass"]=valid.model_pass, valid.physical_pass
        push!(stages, r)
        return length(stages)
    end
    function remember(i)
        r=stages[i]
        if r["model_pass"] && get(r, "objective_kind", "")=="operating_cost"
            if r["operating_cost"]<bestcost
                bestcost=r["operating_cost"]
                out["best_subproblem_stage"]=i
            end
            rr=reconstruct_r3_pressure(c, r)
            # 重构后的κ不再对应原KKT点；原始乘子只保留在来源阶段。
            pop!(rr, "sensitivity", nothing)
            rr["sensitivity_source_stage"]=i
            rr["elapsed_sec"]=0.0
            j=pushstage("pressure_reconstruction", rr)
            if rr["physics_pass"] && rr["operating_cost"]<bestphysical
                bestphysical=rr["operating_cost"]
                out["final_stage"]=j
            end
        end
    end
    function evaluate(m; sensitivity = false, rescale_cones = false)
        local i, j
        i=pushstage(
            rescale_cones ? "v2_scaled_dispatch" : "v2_dispatch",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, m; operation, rescale_cones),
                convex_optimizer;
                deadline = outer,
                sensitivity,
            ),
        )
        if stages[i]["model_pass"]
            return i, "dispatch", stages[i]["operating_cost"]/out["cost_scale"]
        elseif stages[i]["status"]!="infeasible_certified"
            return i, "unresolved", Inf
        end
        j=pushstage(
            "v2_diagnostic",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, m; mode = :diagnostic, operation, rescale_cones),
                convex_optimizer;
                deadline = outer,
                sensitivity,
            ),
        )
        return j,
        stages[j]["model_pass"] ? "diagnostic" : "unresolved",
        get(stages[j], "solver_objective", Inf)
    end
    function finish(reason)
        local i
        out["outer_status"]=reason
        if !isnothing(v3_options)
            return r3_v3_finalize!(
                c,
                out,
                pushstage;
                optimizer,
                convex_optimizer,
                operation,
                start,
                deadline,
                options = v3_options,
            )
        end
        i=out["best_subproblem_stage"]
        if i>0 && deadline>r3_clock() && !isnothing(optimizer)
            candidate=stages[i]
            if !validate_r3_solution(c, reconstruct_r3_pressure(c, candidate)).physical_pass
                m=r2_flow_matrix(c, candidate["values"]["m_pipe"])
                j=pushstage(
                    "v2_final_physical",
                    r3_solve(
                        c,
                        ()->build_r3_subproblem(c, m; physical = true, operation),
                        optimizer;
                        deadline,
                        budget_sec = max(0, deadline-r3_clock()),
                    ),
                )
                if stages[j]["physics_pass"] && stages[j]["operating_cost"]<bestphysical
                    out["final_stage"]=j
                    bestphysical=stages[j]["operating_cost"]
                end
            end
        end
        final=out["final_stage"]
        out["status"]=final>0 ? "physical_feasible" : "no_verified_physical_solution"
        out["cost_optimization_complete"]=final>0 && stages[final]["status"]=="solver_optimal"
        out["elapsed_sec"]=r3_clock()-start
        return out
    end
    if !isnothing(initial_run)
        imported=read_r2_run(initial_run)
        imported.case.data==c.data && imported.case.sha256==c.sha256 ||
            throw(ArgumentError("初值输入不同"))
        imported.result["spec"]["formulation"]=="schpd_mc_v1" ||
            throw(ArgumentError("初值须为SCHPD"))
        isnothing(operation) ||
            throw(ArgumentError("四模式初始化必须包含同一operation；请显式提供流量"))
        initial_flow=imported.result["values"]["m_pipe"]
        out["parent_run_id"]=imported.metadata["run_id"]
    elseif r3_is_cf(operation) && isnothing(initial_flow)
        initial_flow=r2_flow_matrix(c)
    elseif isnothing(initial_flow)
        function initialize()
            b=build_r2_model(c; spec = R2Spec(; formulation = :schpd_mc_v1), operation)
            return merge(
                b,
                (;
                    variant = "schpd_mc_v1",
                    objective_kind = "operating_cost",
                    elastic_rows = NamedTuple[],
                    flow_schedule = r2_flow_matrix(c),
                ),
            )
        end
        init=r3_solve(c, initialize, optimizer; deadline = outer)
        delete!(init, "variant")
        i=pushstage("v2_initialization", init)
        stages[i]["model_pass"] || return finish("initialization_failed")
        initial_flow=stages[i]["values"]["m_pipe"]
    end
    m=r2_flow_matrix(c, initial_flow)
    all(lo .- 1e-6 .<= m .<= hi .+ 1e-6) || throw(ArgumentError("初值违反模式固定流量"))
    out["initial_flow"]=r2_extract(m)
    out["initial_flow_sha256"]=r2_flow_hash(m)
    if r3_is_cf(operation)
        i, mode, _=evaluate(m)
        remember(i)
        return finish(mode=="dispatch" ? "fixed_flow_dispatch" : "fixed_flow_"*mode)
    end
    radius=0.1
    small=0
    for k in 1:max_iterations
        r3_clock()<outer || return finish("budget_exhausted")
        i, mode, merit=evaluate(m; sensitivity = true)
        remember(i)
        row=Dict{String,Any}(
            "algorithm"=>out["algorithm"],
            "iteration"=>k,
            "stage"=>i,
            "mode"=>mode,
            "flow"=>r2_extract(m),
            "merit"=>merit,
            "trials"=>Dict{String,Any}[],
            "accepted"=>false,
            "elapsed_sec"=>r3_clock()-start,
        )
        !isnothing(operation) && (row["operation"]=r3_operation_dict(operation))
        push!(trace, row)
        mode=="unresolved" && return finish(
            stages[i]["status"]=="infeasible_certified" ? "hard_constraints_infeasible" :
            "subproblem_unresolved",
        )
        s=get(stages[i], "sensitivity", Dict("trusted"=>false))
        if !get(s, "trusted", false)
            j, newmode, f=evaluate(m; sensitivity = true, rescale_cones = true)
            row["scaled_retry_stage"]=j
            if newmode==mode && get(get(stages[j], "sensitivity", Dict()), "trusted", false)
                i, merit, s=j, f, stages[j]["sensitivity"]
                row["stage"]=j
                row["merit"]=f
                remember(j)
            end
        end
        function accept!(trial, j, mn, f, trialmode)
            trial["accepted"]=true
            row["accepted"]=true
            row["accepted_flow"]=r2_extract(mn)
            if mode=="dispatch" && trialmode=="dispatch"
                change=abs(stages[j]["operating_cost"]-stages[i]["operating_cost"])/max(
                    1,
                    abs(stages[i]["operating_cost"]),
                )
                small=change<=1e-6 ? small+1 : 0
            else
                small=0
            end
            remember(j)
        end
        trusted=get(s, "trusted", false)
        row["trusted_sensitivity"]=trusted
        fallback=nothing
        if trusted && get(s, "smooth", false)
            row["smooth"]=true
            g=r3_matrix(s["gradient"]) .* width/(mode=="dispatch" ? out["cost_scale"] : 1)
            row["gradient"]=r2_extract(g)
            p=r3_project(c, m-width .* g, convex_optimizer; deadline = outer, operation)
            if p["status"]=="projected"
                direction=(r3_matrix(p["flow"])-m) ./ divisor
                row["projected_gradient_norm"]=maximum(abs, direction; init = 0.0)
                if mode=="dispatch" && small>=3 && row["projected_gradient_norm"]<=1e-4
                    out["outer_converged"]=true
                    return finish("smooth_numeric_stop")
                end
                candidates=[("projected_gradient", p)]
                if mode=="diagnostic" && local_halfspace
                    half=r3_project(
                        c,
                        m-width .* g,
                        convex_optimizer;
                        deadline = outer,
                        operation,
                        center = m,
                        gradient = g,
                        violation = merit,
                        radius = 0.1,
                    )
                    half["status"]=="projected" && pushfirst!(candidates, ("local_halfspace", half))
                end
                for (kind, projected) in candidates
                    dir=(r3_matrix(projected["flow"])-m) ./ divisor
                    slope=sum(g .* dir)
                    slope<0 || continue
                    for bt in 0:11
                        r3_clock()<outer || break
                        step=0.5^bt
                        mn=m+step*width .* dir
                        j, tm, f=evaluate(mn)
                        good=(tm==mode && f<=merit+1e-4*step*slope) ||
                             (mode=="diagnostic" && tm=="dispatch")
                        trial=Dict{String,Any}(
                            "kind"=>kind,
                            "step"=>step,
                            "slope"=>slope,
                            "projection"=>projected,
                            "stage"=>j,
                            "mode"=>tm,
                            "merit"=>f,
                            "flow"=>r2_extract(mn),
                            "accepted"=>false,
                        )
                        push!(row["trials"], trial)
                        if good
                            if bt>=8 && row["projected_gradient_norm"]>1e-4
                                trial["reason"]="boundary_tiny_step_deferred"
                                fallback=(trial, j, mn, f, tm)
                                break
                            end
                            accept!(trial, j, mn, f, tm)
                            break
                        end
                    end
                    (row["accepted"] || !isnothing(fallback)) && break
                end
            end
        end
        if !row["accepted"]
            # 无可信对偶也可构造原始变量局部模型；不会产生冒名的值函数梯度。
            for attempt in 1:12
                r3_clock()<outer && radius>=1e-6 || break
                localresult=r3_local_solve(
                    c,
                    stages[i],
                    convex_optimizer;
                    mode = Symbol(mode),
                    radius,
                    operation,
                    deadline = outer,
                )
                trial=Dict{String,Any}(
                    "kind"=>"primal_local_model",
                    "local"=>localresult,
                    "accepted"=>false,
                )
                push!(row["trials"], trial)
                row["switches"]=get(localresult, "switches", String[])
                localresult["status"]=="nonsmooth_requires_neighbor" && break
                if localresult["status"]!="local_checked"
                    radius/=2
                    continue
                end
                prediction=merit-localresult["predicted_merit"]
                row["local_direction_norm"]=localresult["direction_norm"]
                row["local_trust_binding"]=localresult["trust_binding"]
                row["switches"]=localresult["switches"]
                if !isnothing(v3_options) &&
                   v3_options.stationarity_check &&
                   mode=="dispatch" &&
                   r3_stationarity_gate(localresult, merit)
                    check=r3_check_stationarity(
                        c,
                        m,
                        i,
                        localresult,
                        evaluate,
                        stages,
                        convex_optimizer;
                        radius,
                        operation,
                        deadline = outer,
                    )
                    out["stationarity_check"]=check
                    if check["checked"]
                        out["local_stationarity_checked"]=true
                        return finish("local_stationarity_checked")
                    end
                end
                if mode=="dispatch" &&
                   isempty(localresult["switches"]) &&
                   !localresult["trust_binding"] &&
                   get(localresult["kkt"], "trusted", false) &&
                   localresult["direction_norm"]<=1e-4 &&
                   small>=3
                    out["outer_converged"]=true
                    return finish("smooth_local_numeric_stop")
                end
                if prediction<=1e-12
                    trial["reason"]="no_predicted_descent"
                    radius/=2
                    continue
                end
                mn=r2_flow_matrix(c, localresult["flow"])
                j, tm, f=evaluate(mn)
                # 从诊断进入可行分支时诊断值为0，不能用归一化费用算改善比。
                actual=merit-(mode=="diagnostic" && tm=="dispatch" ? 0.0 : f)
                ratio=tm==mode || mode=="diagnostic" && tm=="dispatch" ? actual/prediction : -Inf
                merge!(
                    trial,
                    Dict(
                        "stage"=>j,
                        "mode"=>tm,
                        "merit"=>f,
                        "flow"=>r2_extract(mn),
                        "prediction"=>prediction,
                        "ratio"=>ratio,
                    ),
                )
                if ratio>=0.1 && actual>0
                    accept!(trial, j, mn, f, tm)
                    ratio>=0.75 && (radius=min(0.2, 2radius))
                    break
                end
                trial["reason"]="actual_subproblem_rejected"
                radius/=2
            end
        end
        # 切换点以守恒域投影后的邻段真实最优值探测，不沿用边界导数。
        if !row["accepted"] && !isempty(get(row, "switches", get(s, "switches", String[])))
            for epsilon in (1e-4, 1e-5, 1e-6), sign in (1, -1)
                r3_clock()<outer || break
                p=r3_project(c, m+sign*epsilon*width, convex_optimizer; deadline = outer, operation)
                p["status"]=="projected" || continue
                mn=r2_flow_matrix(c, p["flow"])
                j, tm, f=evaluate(mn)
                trial=Dict{String,Any}(
                    "kind"=>"switch_probe",
                    "epsilon"=>epsilon,
                    "projection"=>p,
                    "stage"=>j,
                    "mode"=>tm,
                    "merit"=>f,
                    "flow"=>r2_extract(mn),
                    "accepted"=>false,
                )
                push!(row["trials"], trial)
                if tm==mode && f<merit-1e-12 || mode=="diagnostic" && tm=="dispatch"
                    accept!(trial, j, mn, f, tm)
                    break
                end
            end
        end
        if !row["accepted"] && !isnothing(fallback)
            accept!(fallback...)
        end
        if row["accepted"]
            m=r2_flow_matrix(c, row["accepted_flow"])
        else
            return finish(
                r3_clock()>=outer ? "budget_exhausted" :
                !isempty(get(row, "switches", String[])) ? "nonsmooth_stalled" :
                !trusted ? "untrusted_dual_local_stalled" : "local_direction_stalled",
            )
        end
    end
    return finish("iteration_limit")
end

function r3_validate_v2_iteration(c, row; stages = nothing)
    errors=String[]
    m=r2_flow_matrix(c, row["flow"])
    operation=haskey(row, "operation") ? r3_operation_from_dict(row["operation"]) : nothing
    lo, hi, width=r3_flow_box(c, operation)
    all(lo .- 1e-6 .<= m .<= hi .+ 1e-6) || push!(errors, "operation_flow")
    if !isnothing(stages) && row["mode"]!="unresolved"
        center=stages[row["stage"]]
        expected=center["solver_objective"]/(row["mode"]=="dispatch" ? r3_cost_scale(c) : 1)
        abs(row["merit"]-expected)<=1e-10*max(1, abs(expected)) || push!(errors, "merit_stage_link")
        maximum(abs, r3_matrix(center["values"]["m_pipe"])-m)<=1e-6 ||
            push!(errors, "flow_stage_link")
    end
    accepted=0
    for trial in row["trials"]
        get(trial, "accepted", false) || continue
        accepted+=1
        n=r2_flow_matrix(c, trial["flow"])
        all(lo .- 1e-6 .<= n .<= hi .+ 1e-6) || push!(errors, "trial_operation_flow")
        maximum(abs, n-r3_matrix(row["accepted_flow"]))<=1e-6 || push!(errors, "accepted_flow")
        tm=trial["mode"]
        same=tm==row["mode"]
        recovery=row["mode"]=="diagnostic" && tm=="dispatch"
        same||recovery || push!(errors, "mode_transition")
        if !isnothing(stages)
            r=stages[trial["stage"]]
            expected=r["solver_objective"]/(tm=="dispatch" ? r3_cost_scale(c) : 1)
            abs(trial["merit"]-expected)<=1e-10*max(1, abs(expected)) ||
                push!(errors, "trial_merit")
            validate_r3_solution(c, r).model_pass || push!(errors, "trial_model")
            maximum(abs, r3_matrix(r["values"]["m_pipe"])-n)<=1e-6 ||
                push!(errors, "trial_flow_stage")
        end
        if trial["kind"]=="primal_local_model"
            l=trial["local"]
            prediction=row["merit"]-l["predicted_merit"]
            ratio=(row["merit"]-(recovery ? 0.0 : trial["merit"]))/prediction
            prediction>0 && ratio>=0.1 || push!(errors, "local_acceptance")
            abs(ratio-trial["ratio"])<=1e-8*max(1, abs(ratio)) || push!(errors, "local_ratio")
            if !isnothing(stages)
                b=build_r3_local_step(
                    c,
                    stages[row["stage"]];
                    mode = Symbol(row["mode"]),
                    radius = l["radius"],
                    operation,
                )
                vars=all_variables(b.model)
                length(vars)==length(l["values"]) ||
                    throw(ArgumentError("局部模型变量见证长度不同"))
                vals=Dict(zip(vars, l["values"]))
                isempty(primal_feasibility_report(b.model, vals; atol = 1e-6)) ||
                    push!(errors, "local_primal_witness")
                abs(value(v->vals[v], b.merit_expression)-l["predicted_merit"])<=1e-8 ||
                    push!(errors, "local_prediction")
            end
        elseif trial["kind"] in ("projected_gradient", "local_halfspace")
            p=trial["projection"]
            r3_projection_witness(c, p["values"]; operation) || push!(errors, "projection_witness")
            g=r3_matrix(row["gradient"])
            dir=(r3_matrix(p["flow"])-m) ./ ifelse.(width .> 0, width, 1.0)
            abs(sum(g .* dir)-trial["slope"])<=1e-10 || push!(errors, "slope_mismatch")
            maximum(abs, n-(m+trial["step"]*width .* dir))<=1e-6 ||
                push!(errors, "trial_interpolation")
            if !isnothing(stages)
                sensitivity=stages[row["stage"]]["sensitivity"]
                get(sensitivity, "trusted", false) || push!(errors, "untrusted_gradient")
                expectedg=r3_matrix(sensitivity["gradient"]) .* width/(
                    row["mode"]=="dispatch" ? r3_cost_scale(c) : 1
                )
                maximum(abs, g-expectedg)<=1e-10 || push!(errors, "gradient_stage_link")
            end
            recovery ||
                trial["merit"]<=row["merit"]+1e-4*trial["step"]*trial["slope"]+1e-12 ||
                push!(errors, "armijo")
        else
            recovery||trial["merit"]<row["merit"] || push!(errors, "switch_improvement")
        end
    end
    accepted==Int(row["accepted"]) || push!(errors, "accepted_count")
    return (; pass = isempty(errors), errors)
end
