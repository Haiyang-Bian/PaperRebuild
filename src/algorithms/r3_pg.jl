r3_matrix(x::AbstractMatrix) = Float64.(x)
r3_matrix(x) = reduce(vcat, permutedims.(x))

function r3_cost_scale(c)
    d=c.data
    return max(
        1.0,
        d["dt_h"]*(
            sum(abs, d["grid_price"])*d["electric"]["grid_max_MW"] +
            d["T"]*sum(abs(g["cost_per_MWh"])*g["P_max"] for g in d["devices"])
        ),
    )
end

"""
    solve_r3_projected_gradient(case; optimizer=nothing, convex_optimizer=optimizer,
        initial_flow=nothing, initial_run=nothing, budget_sec=600, max_iterations=200, local_halfspace=true)

第3.3节核查版外层r3_pg_checked_v1。初始化可来自显式kg/s计划或同输入SCHPD保存运行。
成本/弹性诊断使用不同梯度和目标尺度；归一化投影、局部试探半空间及Armijo回溯均保存证据。
最多200轮，共享600秒截止时间，预留至多60秒固定流量物理调度。不调用直接流量修正。
最终物理可行、费用优化完成与外层数值停止分别记录；不保证非凸全局最优。

默认algorithm=:r3_pg_checked_v1；显式v2增加原始变量局部方向，v3增加所有已求解可行
调度的候选池、局部物理恢复及三次驻点核验。physical_recovery/stationarity_check只控制v3消融。
v3的600秒预算分为外层420秒、恢复最多120秒、最终候选调度最多60秒，费用界不用于恢复目标。
"""
function solve_r3_projected_gradient(
    c::R2Case;
    optimizer = nothing,
    convex_optimizer = optimizer,
    initial_flow = nothing,
    initial_run = nothing,
    budget_sec = 600.0,
    max_iterations = 200,
    local_halfspace = true,
    algorithm = :r3_pg_checked_v1,
    operation = nothing,
    physical_recovery = true,
    stationarity_check = true,
)
    if Symbol(algorithm) in (:r3_pg_checked_v2, :r3_pg_checked_v3)
        return r3_pg_v2(
            c;
            optimizer,
            convex_optimizer,
            initial_flow,
            initial_run,
            budget_sec,
            max_iterations,
            local_halfspace,
            operation,
            v3_options = Symbol(algorithm)==:r3_pg_checked_v3 ?
                         (; physical_recovery, stationarity_check) : nothing,
        )
    end
    Symbol(algorithm)==:r3_pg_checked_v1 || throw(ArgumentError("未知R3外层算法"))
    isnothing(operation) || throw(ArgumentError("四模式须显式选r3_pg_checked_v2，v1历史定义不变"))
    isfinite(budget_sec) && 0<budget_sec<=600 || throw(ArgumentError("预算须在(0,600]秒"))
    1<=max_iterations<=200 || throw(ArgumentError("轮数须在1至200之间"))
    isnothing(initial_flow) || isnothing(initial_run) || throw(ArgumentError("初值入口互斥"))
    start=r3_clock()
    deadline=start+budget_sec
    outer_deadline=deadline-min(60.0, 0.1budget_sec)
    lo, hi, width=r3_flow_box(c)
    stages=Dict{String,Any}[]
    trace=Dict{String,Any}[]
    out=Dict{String,Any}(
        "schema"=>"r3-run-v1",
        "algorithm"=>"r3_pg_checked_v1",
        "trace_schema"=>"r3-pg-trace-v1",
        "input_sha256"=>c.sha256,
        "origin"=>"synthetic",
        "budget_sec"=>budget_sec,
        "stages"=>stages,
        "iterations"=>trace,
        "source_hashes_at_solve"=>r2_science_hashes(),
        "final_stage"=>0,
        "best_subproblem_stage"=>0,
        "cost_optimization_complete"=>false,
        "outer_converged"=>false,
        "cost_scale"=>r3_cost_scale(c),
        "local_halfspace"=>local_halfspace,
        "max_iterations"=>max_iterations,
    )
    bestcost=Inf
    bestphysical=Inf
    function pushstage(name, r)
        r["stage"]=name
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
            rr["elapsed_sec"]=0.0
            j=pushstage("pressure_reconstruction", rr)
            if rr["physics_pass"] && rr["operating_cost"]<bestphysical
                bestphysical=rr["operating_cost"]
                out["final_stage"]=j
            end
        end
    end
    function evaluate(m; sensitivity = false)
        i=pushstage(
            "pg_dispatch",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, m),
                convex_optimizer;
                deadline = outer_deadline,
                sensitivity,
            ),
        )
        sp=stages[i]
        if sp["model_pass"]
            return i, "dispatch", sp["operating_cost"]/out["cost_scale"]
        elseif sp["status"]!="infeasible_certified"
            return i, "unresolved", Inf
        end
        j=pushstage(
            "pg_diagnostic",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, m; mode = :diagnostic),
                convex_optimizer;
                deadline = outer_deadline,
                sensitivity,
            ),
        )
        return j,
        stages[j]["model_pass"] ? "diagnostic" : "unresolved",
        get(stages[j], "solver_objective", Inf)
    end
    function finish(reason)
        out["outer_status"]=reason
        i=out["best_subproblem_stage"]
        # 费用最低的SOCP候选若仍未物理通过，仅在其固定流量下补做原等式调度。
        if i>0 && deadline>r3_clock() && !isnothing(optimizer)
            candidate=stages[i]
            reconstructed=reconstruct_r3_pressure(c, candidate)
            if !validate_r3_solution(c, reconstructed).physical_pass
                m=r2_flow_matrix(c, candidate["values"]["m_pipe"])
                j=pushstage(
                    "pg_final_physical",
                    r3_solve(
                        c,
                        ()->build_r3_subproblem(c, m; physical = true),
                        optimizer;
                        budget_sec = max(0.0, deadline-r3_clock()),
                        deadline,
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
            throw(ArgumentError("初值输入不一致"))
        imported.result["spec"]["formulation"]=="schpd_mc_v1" ||
            throw(ArgumentError("初值须为SCHPD"))
        init=deepcopy(imported.result)
        i=pushstage("pg_initialization_imported", init)
        stages[i]["model_pass"] || return finish("initialization_failed")
        initial_flow=init["values"]["m_pipe"]
        out["parent_run_id"]=imported.metadata["run_id"]
    elseif isnothing(initial_flow)
        isnothing(optimizer) && return finish("initialization_not_run_solver")
        remaining=min(60.0, outer_deadline-r3_clock())
        remaining>0 || return finish("budget_exhausted")
        init=try
            solve_r2_case(
                c;
                optimizer,
                spec = R2Spec(; formulation = :schpd_mc_v1),
                budget_sec = remaining,
            )
        catch err
            reason=occursin("license", lowercase(sprint(showerror, err))) ? "not_run_license" :
                   err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute} ?
                   "unsupported_solver" : nothing
            isnothing(reason) && rethrow()
            Dict{String,Any}(
                "status"=>reason,
                "elapsed_sec"=>r3_clock()-start,
                "input_sha256"=>c.sha256,
                "spec"=>r2_spec_dict(R2Spec(; formulation = :schpd_mc_v1)),
            )
        end
        i=pushstage("pg_initialization", init)
        stages[i]["model_pass"] || return finish("initialization_failed")
        initial_flow=init["values"]["m_pipe"]
    end
    m=r2_flow_matrix(c, initial_flow)
    out["initial_flow"], out["initial_flow_sha256"]=r2_extract(m), r2_flow_hash(m)
    small_changes=0
    previous_active=""
    for k in 1:max_iterations
        outer_deadline>r3_clock() || return finish("budget_exhausted")
        i, mode, merit=evaluate(m; sensitivity = true)
        remember(i)
        record=Dict{String,Any}(
            "iteration"=>k,
            "stage"=>i,
            "mode"=>mode,
            "flow"=>r2_extract(m),
            "merit"=>merit,
            "trials"=>Dict{String,Any}[],
            "accepted"=>false,
            "elapsed_sec"=>r3_clock()-start,
        )
        push!(trace, record)
        mode=="unresolved" && return finish(
            stages[i]["status"]=="infeasible_certified" ? "hard_constraints_infeasible" :
            "subproblem_unresolved",
        )
        s=get(stages[i], "sensitivity", Dict("trusted"=>false))
        get(s, "trusted", false) || return finish("untrusted_sensitivity")
        current_active=s["kkt"]["active_signature"]
        record["active_set_changed"]=!isempty(previous_active) && current_active!=previous_active
        record["active_set_changed"] && (small_changes=0)
        previous_active=current_active
        g=r3_matrix(s["gradient"]) .* width/(mode=="dispatch" ? out["cost_scale"] : 1)
        record["gradient"]=r2_extract(g)
        record["smooth"]=s["smooth"]
        record["switches"]=s["switches"]
        accepted=false
        # 切换点不使用普通导数：在凸域中做相邻侧探测，以真实最优值检验方向。
        if !s["smooth"]
            probes=[ones(size(m)), -ones(size(m))]
            for q in eachindex(m), sign in (1, -1)
                width[q]>0 || continue
                probe=zeros(size(m))
                probe[q]=sign
                push!(probes, probe)
            end
            for probe in probes
                length(record["trials"])>=12 && break
                outer_deadline>r3_clock() || break
                target=m+1e-5*width .* probe
                projection=r3_project(c, target, convex_optimizer; deadline = outer_deadline)
                trial=Dict{String,Any}(
                    "kind"=>"one_sided",
                    "projection"=>projection,
                    "accepted"=>false,
                )
                push!(record["trials"], trial)
                projection["status"]=="projected" || continue
                mn=r2_flow_matrix(c, projection["flow"])
                maximum(abs, (mn-m) ./ ifelse.(width .> 0, width, 1.0))>=5e-6 || continue
                j, trialmode, f=evaluate(mn)
                trial["stage"], trial["mode"], trial["merit"]=j, trialmode, f
                good=(mode=="dispatch" && trialmode=="dispatch" && f<merit-1e-12) || (
                    mode=="diagnostic" &&
                    (trialmode=="dispatch" || trialmode=="diagnostic" && f<merit-1e-12)
                )
                if good
                    trial["accepted"]=true
                    record["accepted"]=true
                    record["accepted_flow"]=r2_extract(mn)
                    m=mn
                    remember(j)
                    accepted=true
                    break
                end
            end
            accepted || return finish("nonsmooth_stalled")
            small_changes=0
            continue
        end
        base=r3_project(c, m-width .* g, convex_optimizer; deadline = outer_deadline)
        record["base_projection"]=base
        base["status"]=="projected" || return finish("projection_unresolved")
        direction=(r3_matrix(base["flow"])-m) ./ ifelse.(width .> 0, width, 1.0)
        mapping=maximum(abs, direction; init = 0.0)
        record["projected_gradient_norm"]=mapping
        if mode=="dispatch" && small_changes>=3 && mapping<=1e-4
            out["outer_converged"]=true
            return finish("smooth_numeric_stop")
        end
        # 每轮局部半空间只尝试一次；失败后用无割投影方向，不污染后续轮次。
        candidates=Tuple{String,Dict{String,Any}}[]
        if mode=="diagnostic" && local_halfspace
            localp=r3_project(
                c,
                m-width .* g,
                convex_optimizer;
                deadline = outer_deadline,
                center = m,
                gradient = g,
                violation = merit,
                radius = 0.1,
            )
            record["local_projection"]=localp
            localp["status"]=="projected" && push!(candidates, ("local_halfspace", localp))
        end
        push!(candidates, ("projected_gradient", base))
        for (kind, projection) in candidates
            dir=(r3_matrix(projection["flow"])-m) ./ ifelse.(width .> 0, width, 1.0)
            slope=sum(g .* dir)
            slope<0 || continue
            for backtrack in 0:11
                outer_deadline>r3_clock() || break
                step=0.5^backtrack
                mn=m+step*width .* dir
                j, trialmode, f=evaluate(mn)
                rhs=merit+1e-4*step*slope
                good=trialmode==mode && f<=rhs || mode=="diagnostic" && trialmode=="dispatch"
                trial=Dict{String,Any}(
                    "kind"=>kind,
                    "step"=>step,
                    "slope"=>slope,
                    "armijo_rhs"=>rhs,
                    "stage"=>j,
                    "mode"=>trialmode,
                    "merit"=>f,
                    "flow"=>r2_extract(mn),
                    "accepted"=>good,
                    "projection"=>projection,
                    "reason"=>good ? "actual_improvement" :
                              trialmode=="unresolved" ? "solver_unresolved" :
                              "insufficient_decrease",
                )
                push!(record["trials"], trial)
                if good
                    if mode=="dispatch" && trialmode=="dispatch"
                        difference=abs(stages[j]["operating_cost"]-stages[i]["operating_cost"])/max(
                            1,
                            abs(stages[i]["operating_cost"]),
                        )
                        small_changes=difference<=1e-6 ? small_changes+1 : 0
                    else
                        small_changes=0
                    end
                    record["accepted"], record["accepted_flow"]=true, r2_extract(mn)
                    record["step"]=step
                    m=mn
                    remember(j)
                    accepted=true
                    break
                end
            end
            accepted && break
        end
        accepted ||
            return finish(outer_deadline<=r3_clock() ? "budget_exhausted" : "line_search_stalled")
    end
    return finish("iteration_limit")
end

"""
    validate_r3_iteration(case, record)

从保存迭代记录重算流量合法性、投影距离、局部半空间及Armijo接受条件，不重新优化。
返回pass/errors；一步接受不代表物理可行，最终调度仍交给validate_r3_solution。
"""
function validate_r3_iteration(c::R2Case, record; stages = nothing)
    get(record, "algorithm", "") in ("r3_pg_checked_v2", "r3_pg_checked_v3") &&
        return r3_validate_v2_iteration(c, record; stages)
    errors=String[]
    lo, hi, width=r3_flow_box(c)
    m=r2_flow_matrix(c, record["flow"])
    if !isnothing(stages)
        stage=stages[record["stage"]]
        if haskey(stage, "values") && record["mode"]!="unresolved"
            expected=stage["solver_objective"]/(record["mode"]=="dispatch" ? r3_cost_scale(c) : 1)
            abs(expected-record["merit"])<=1e-10*max(1, abs(expected)) ||
                push!(errors, "merit_stage_link")
            maximum(abs, r3_matrix(stage["values"]["m_pipe"])-m)<=1e-6 ||
                push!(errors, "flow_stage_link")
            if haskey(record, "gradient")
                expectedg=r3_matrix(stage["sensitivity"]["gradient"]) .* width/(
                    record["mode"]=="dispatch" ? r3_cost_scale(c) : 1
                )
                maximum(abs, expectedg-r3_matrix(record["gradient"]))<=1e-10 ||
                    push!(errors, "gradient_stage_link")
            end
        end
    end
    count=0
    for trial in record["trials"]
        p=trial["projection"]
        if p["status"]=="projected"
            r3_projection_witness(c, p["values"]) || push!(errors, "projection_witness")
            pm=r2_flow_matrix(c, p["flow"])
            target=r3_matrix(p["target"])
            distance=sum(
                ((pm[i]-target[i])/width[i])^2 for i in eachindex(pm) if width[i]>0;
                init = 0.0,
            )
            abs(distance-p["distance"])<=1e-6*max(1, distance) ||
                push!(errors, "projection_distance")
            if get(p, "local_halfspace", false)
                z=(pm-r3_matrix(p["center"])) ./ ifelse.(width .> 0, width, 1.0)
                maximum(abs, z)<=p["radius"]+1e-6 || push!(errors, "local_radius")
                p["violation"]+sum(r3_matrix(p["gradient"]) .* z)<=1e-6 ||
                    push!(errors, "local_halfspace")
            end
        end
        get(trial, "accepted", false) || continue
        count+=1
        if !isnothing(stages)
            stage=stages[trial["stage"]]
            expected=stage["solver_objective"]/(trial["mode"]=="dispatch" ? r3_cost_scale(c) : 1)
            abs(expected-trial["merit"])<=1e-10*max(1, abs(expected)) ||
                push!(errors, "trial_merit_link")
            maximum(abs, r3_matrix(stage["values"]["m_pipe"])-r3_matrix(record["accepted_flow"]))<=1e-6 ||
                push!(errors, "accepted_flow_link")
        end
        if trial["kind"]=="one_sided"
            good=record["mode"]=="diagnostic" && trial["mode"]=="dispatch" ||
                 trial["mode"]==record["mode"] && trial["merit"]<record["merit"]-1e-12
            good || push!(errors, "one_sided_acceptance")
        else
            n=r2_flow_matrix(c, trial["flow"])
            slope=sum(
                r3_matrix(record["gradient"]) .* (r3_matrix(p["flow"])-m) ./
                ifelse.(width .> 0, width, 1.0),
            )
            rhs=record["merit"]+1e-4*trial["step"]*slope
            maximum(abs, n-(m+trial["step"]*(r3_matrix(p["flow"])-m)))<=1e-6 ||
                push!(errors, "trial_interpolation")
            good=record["mode"]=="diagnostic" && trial["mode"]=="dispatch" ||
                 trial["mode"]==record["mode"] && trial["merit"]<=rhs+1e-12
            good && slope<0 || push!(errors, "armijo_acceptance")
        end
    end
    count==Int(record["accepted"]) || push!(errors, "accepted_count")
    return (; pass = isempty(errors), errors)
end
