"""
    R3BaselineSpec(; geometry=:physical_euclidean, initial_displacement=0.1)

论文结构基线r3_paper_structure_v1的项目数值规则。两种几何分别在kg/s和归一化
流量坐标中投影；initial_displacement为未投影方向最大无量纲位移。
固定Armijo系数1e-4、折半12次；三个费用ε仅审计，不提前终止轨迹。
这些数值不是作者公开参数，不启用任何局部恢复或全变量直接修正。
"""
struct R3BaselineSpec
    geometry::Symbol
    initial_displacement::Float64
    function R3BaselineSpec(; geometry = :physical_euclidean, initial_displacement = 0.1)
        geometry in (:physical_euclidean, :normalized_euclidean) ||
            throw(ArgumentError("未知基线投影几何"))
        isfinite(initial_displacement) && 0<initial_displacement<=1 ||
            throw(ArgumentError("初始无量纲位移须在(0,1]"))
        new(geometry, Float64(initial_displacement))
    end
end

r3_baseline_spec(s) = Dict(
    "geometry"=>string(s.geometry),
    "initial_displacement"=>s.initial_displacement,
    "armijo"=>1e-4,
    "backtracks"=>12,
    "epsilon_cost"=>[1e-6, 1e-4, 1e-2],
)

function r3_baseline_direction(g, width, spec)
    # 原坐标下降为-g；归一化坐标下降映回kg/s后为-D²g。固定分量为零。
    d=spec.geometry==:physical_euclidean ? -copy(g) : -width .^ 2 .* g
    d[width .== 0].=0
    rate=maximum(abs.(d ./ ifelse.(width .> 0, width, 1.0)); init = 0.0)
    return d, rate>0 ? spec.initial_displacement/rate : 0.0
end

function r3_baseline_evidence(c, result)
    rows=Dict{String,Any}[]
    previous=nothing
    # 只纳入初始点和接受更新。末轮接受点也保留；重解、拒绝试探不形成相邻费用。
    sequence=Tuple{Any,Int,String}[]
    for (k, it) in enumerate(result["iterations"])
        k==1 && push!(sequence, (it, it["stage"], it["mode"]))
        for trial in it["trials"]
            trial["accepted"] || continue
            nextrow=k<length(result["iterations"]) ? result["iterations"][k+1] :
                    Dict("small_accepted_before"=>0)
            push!(sequence, (nextrow, trial["stage"], trial["mode"]))
        end
    end
    for (position, (it, stage, mode)) in enumerate(sequence)
        s=result["stages"][stage]
        row=Dict{String,Any}(
            "iteration"=>position-1,
            "stage"=>stage,
            "mode"=>mode,
            "model_pass"=>get(s, "model_pass", false),
            "physical_pass"=>get(s, "physics_pass", false),
            "original_outer_status"=>result["outer_status"],
            "trusted_sensitivity"=>get(it, "trusted_sensitivity", false),
            "smooth"=>get(it, "smooth", false),
            "small_accepted_before"=>it["small_accepted_before"],
            "project_stop"=>get(it, "project_stop", false),
        )
        if mode=="dispatch"
            row["cost"]=s["operating_cost"]
            if !isnothing(previous)
                delta=abs(row["cost"]-previous)
                row["absolute_change"]=delta
                row["relative_change"]=delta/max(1, abs(previous))
                for e in (1e-6, 1e-4, 1e-2)
                    row["paper_form_epsilon_"*string(e)]=delta<=e
                end
            end
            previous=row["cost"]
        else
            previous=nothing
        end
        haskey(it, "projected_gradient_norm") &&
            (row["projected_gradient_norm"]=it["projected_gradient_norm"])
        push!(rows, row)
    end
    return rows
end

function r3_baseline_candidates(c, result)
    roles=Pair{String,Int}[]
    eligible=findall(
        s->get(s, "model_pass", false) &&
           get(s, "objective_kind", "")=="operating_cost" &&
           get(s, "stage", "")=="baseline_dispatch",
        result["stages"],
    )
    isempty(eligible) && return Dict{String,Any}[]
    push!(roles, "first_model_feasible"=>first(eligible))
    for e in (1e-6, 1e-4, 1e-2)
        hit=findfirst(
            row->get(row, "paper_form_epsilon_"*string(e), false),
            r3_baseline_evidence(c, result),
        )
        isnothing(hit) ||
            push!(roles, "epsilon_"*string(e)=>r3_baseline_evidence(c, result)[hit]["stage"])
    end
    push!(
        roles,
        "lowest_model_cost"=>eligible[argmin(
            result["stages"][i]["operating_cost"] for i in eligible
        )],
    )
    bank=Dict{String,Any}[]
    for (role, i) in roles
        s=result["stages"][i]
        hash=r2_flow_hash(r3_matrix(s["values"]["m_pipe"]))
        j=findfirst(x->x["flow_sha256"]==hash, bank)
        if isnothing(j)
            push!(bank, Dict("stage"=>i, "flow_sha256"=>hash, "roles"=>[role]))
        else
            push!(bank[j]["roles"], role)
        end
    end
    return bank
end

"""
    solve_r3_baseline(case; spec=R3BaselineSpec(), initial_flow, operation=nothing,
        convex_optimizer=nothing, optimizer=nothing, budget_sec=600, max_iterations=200)

独立论文结构基线：冻结流量初值→固定流量SP/诊断→可信灵敏度→欧氏投影与真实回溯。
温度K、流量kg/s、费用按输入货币；规范化位移无量纲。复用式3-60/61/63/65/66的
核查解释，不调用v2/v3局部方向、物理恢复、直接修正或参考初值。未公开数值规则见spec。
最多前540秒外层、最后60秒按流量去重均分原等式检查；初值生成的历史耗时不混入本次。
保存模型候选与物理候选、停止证据和全部拒绝步；不保证全局最优或作者同输入数值复现。
"""
function solve_r3_baseline(
    c::R2Case;
    spec = R3BaselineSpec(),
    initial_flow,
    operation = nothing,
    convex_optimizer = nothing,
    optimizer = nothing,
    budget_sec = 600.0,
    max_iterations = 200,
)
    isfinite(budget_sec) && 0<budget_sec<=600 || throw(ArgumentError("预算须在(0,600]秒"))
    1<=max_iterations<=200 || throw(ArgumentError("轮数须在1至200"))
    start=r3_clock()
    deadline=start+budget_sec
    outer=deadline-min(60.0, 0.1budget_sec)
    m=r2_flow_matrix(c, initial_flow)
    lo, hi, width=r3_flow_box(c, operation)
    all(lo .- 1e-6 .<= m .<= hi .+ 1e-6) || throw(ArgumentError("初值违反模式流量边界"))
    divisor=ifelse.(width .> 0, width, 1.0)
    stages=Dict{String,Any}[]
    trace=Dict{String,Any}[]
    out=Dict{String,Any}(
        "schema"=>"r3-run-v1",
        "algorithm"=>"r3_paper_structure_v1",
        "trace_schema"=>"r3-baseline-trace-v1",
        "baseline_spec"=>r3_baseline_spec(spec),
        "input_sha256"=>c.sha256,
        "source_hashes_at_solve"=>r2_science_hashes(),
        "origin"=>"synthetic",
        "stages"=>stages,
        "iterations"=>trace,
        "budget_sec"=>budget_sec,
        "max_iterations"=>max_iterations,
        "initial_flow"=>r2_extract(m),
        "initial_flow_sha256"=>r2_flow_hash(m),
        "cost_scale"=>r3_cost_scale(c),
        "final_stage"=>0,
        "best_subproblem_stage"=>0,
        "outer_converged"=>false,
        "cost_optimization_complete"=>false,
        "strict_redispatch_success"=>false,
        "strict_cost_optimal"=>false,
        "outer_status"=>"running",
        "initialization_source"=>"frozen_external",
    )
    if !isnothing(operation)
        out["operation"]=r3_operation_dict(operation)
        out["operation_sha256"]=r3_operation_hash(out["operation"])
    end
    function pushstage(name, s)
        pop!(s, "source_hashes_at_solve", nothing)
        s["source_snapshot"]="parent_run"
        s["stage"]=name
        s["v3_physical_review"]=true
        v=validate_r3_solution(c, s)
        s["model_pass"], s["physics_pass"]=v.model_pass, v.physical_pass
        push!(stages, s)
        return length(stages)
    end
    function remember(i)
        s=stages[i]
        s["model_pass"] && get(s, "objective_kind", "")=="operating_cost" || return
        old=out["best_subproblem_stage"]
        (old==0 || s["operating_cost"]<stages[old]["operating_cost"]) &&
            (out["best_subproblem_stage"]=i)
        # κ重构只形成独立检查副本，原乘子与外层解不变。
        rr=reconstruct_r3_pressure(c, s)
        pop!(rr, "sensitivity", nothing)
        pop!(rr, "sensitivity_primal_order", nothing)
        rr["elapsed_sec"]=0.0
        rr["source_stage"]=i
        j=pushstage("baseline_pressure_check", rr)
        f=out["final_stage"]
        rr["physics_pass"] &&
            (f==0 || rr["operating_cost"]<stages[f]["operating_cost"]) &&
            (out["final_stage"]=j)
    end
    function evaluate(flow; sensitivity = false)
        i=pushstage(
            "baseline_dispatch",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, flow; operation),
                convex_optimizer;
                deadline = outer,
                sensitivity,
                sensitivity_witness = sensitivity,
            ),
        )
        remember(i)
        stages[i]["model_pass"] &&
            return i, "dispatch", stages[i]["operating_cost"]/out["cost_scale"]
        stages[i]["status"]=="infeasible_certified" || return i, "unresolved", Inf
        j=pushstage(
            "baseline_diagnostic",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, flow; mode = :diagnostic, operation),
                convex_optimizer;
                deadline = outer,
                sensitivity,
                sensitivity_witness = sensitivity,
            ),
        )
        return j,
        stages[j]["model_pass"] ? "diagnostic" : "unresolved",
        get(stages[j], "solver_objective", Inf)
    end
    small=0
    previous_active=""
    reason="iteration_limit"
    for k in 1:max_iterations
        if r3_clock()>=outer
            reason="budget_exhausted"
            break
        end
        i, mode, J=evaluate(m; sensitivity = true)
        s=get(stages[i], "sensitivity", Dict{String,Any}())
        active=get(get(s, "kkt", Dict()), "active_signature", "")
        !isempty(previous_active) && active!=previous_active && (small=0)
        previous_active=active
        row=Dict{String,Any}(
            "algorithm"=>out["algorithm"],
            "iteration"=>k,
            "stage"=>i,
            "mode"=>mode,
            "flow"=>r2_extract(m),
            "merit"=>J,
            "trials"=>Dict{String,Any}[],
            "accepted"=>false,
            "small_accepted_before"=>small,
            "trusted_sensitivity"=>get(s, "trusted", false),
            "smooth"=>get(s, "smooth", false),
            "switches"=>get(s, "switches", String[]),
            "elapsed_sec"=>r3_clock()-start,
            "baseline_spec"=>out["baseline_spec"],
            "project_stop"=>false,
        )
        isnothing(operation) || (row["operation"]=out["operation"])
        push!(trace, row)
        if mode=="unresolved"
            reason=stages[i]["status"]=="infeasible_certified" ? "hard_constraints_infeasible" :
                   "subproblem_unresolved"
            break
        elseif !get(s, "trusted", false)
            reason="untrusted_sensitivity"
            break
        elseif !s["smooth"]
            reason="nonsmooth_unresolved"
            break
        end
        g=r3_matrix(s["gradient"])/(mode=="dispatch" ? out["cost_scale"] : 1.0)
        row["gradient"]=r2_extract(g)
        direction, gamma=r3_baseline_direction(g, width, spec)
        row["initial_gamma"]=gamma
        if gamma==0
            reason="zero_direction"
            break
        end
        # 旧项目方向门槛使用单位归一化梯度映射；不同几何另保存其自身的位移指标。
        measure=r3_project(c, m-width .^ 2 .* g, convex_optimizer; deadline = outer, operation)
        row["mapping_projection"]=measure
        if measure["status"]!="projected"
            reason="projection_unresolved"
            break
        end
        mapping=maximum(abs, (r3_matrix(measure["flow"])-m) ./ divisor; init = 0.0)
        row["projected_gradient_norm"]=mapping
        if mode=="dispatch" && small>=3 && mapping<=1e-4
            row["project_stop"]=true
            out["outer_converged"]=true
            reason="smooth_numeric_stop"
            break
        end
        for bt in 0:11
            r3_clock()<outer || break
            step=gamma*0.5^bt
            p=r3_project(
                c,
                m+step*direction,
                convex_optimizer;
                deadline = outer,
                operation,
                geometry = spec.geometry,
            )
            trial=Dict{String,Any}(
                "kind"=>"baseline_projection",
                "gamma"=>step,
                "backtrack"=>bt,
                "projection"=>p,
                "accepted"=>false,
            )
            push!(row["trials"], trial)
            if p["status"]!="projected"
                trial["reason"]=p["status"]
                continue
            end
            mn=r3_matrix(p["flow"])
            displacement=maximum(abs, (mn-m) ./ divisor; init = 0.0)
            trial["direction_norm"]=displacement
            slope=sum(g .* (mn-m))
            trial["slope"]=slope
            if slope>=0 || displacement<=1e-12
                trial["reason"]="no_descent_direction"
                continue
            end
            j, nextmode, f=evaluate(mn)
            rhs=J+1e-4*slope
            accepted=mode=="diagnostic" && nextmode=="dispatch" || nextmode==mode && f<=rhs
            merge!(
                trial,
                Dict(
                    "stage"=>j,
                    "mode"=>nextmode,
                    "merit"=>f,
                    "flow"=>r2_extract(mn),
                    "armijo_rhs"=>rhs,
                    "accepted"=>accepted,
                    "reason"=>accepted ? "actual_improvement" :
                              nextmode=="unresolved" ? "solver_unresolved" :
                              "insufficient_decrease",
                ),
            )
            if accepted
                if mode=="dispatch" && nextmode=="dispatch"
                    change=abs(stages[j]["operating_cost"]-stages[i]["operating_cost"]) /
                           max(1, abs(stages[i]["operating_cost"]))
                    small=change<=1e-6 ? small+1 : 0
                else
                    small=0
                end
                row["accepted"]=true
                row["accepted_flow"]=r2_extract(mn)
                m=mn
                break
            end
        end
        if !row["accepted"]
            reason=r3_clock()>=outer ? "budget_exhausted" : "line_search_stalled"
            break
        end
    end
    out["outer_status"]=reason
    out["outer_elapsed_sec"]=r3_clock()-start
    out["candidate_bank"]=r3_baseline_candidates(c, out)
    checks=Dict{String,Any}[]
    check_deadline=min(deadline, r3_clock()+min(60.0, 0.1budget_sec))
    bank=out["candidate_bank"]
    for (q, entry) in enumerate(bank)
        remaining=max(0.0, check_deadline-r3_clock())/(length(bank)-q+1)
        source=stages[entry["stage"]]
        flow=r3_matrix(source["values"]["m_pipe"])
        j=pushstage(
            "baseline_strict_check",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, flow; operation, physical = true),
                optimizer;
                budget_sec = remaining,
                deadline = check_deadline,
            ),
        )
        push!(
            checks,
            Dict(
                "source_stage"=>entry["stage"],
                "stage"=>j,
                "roles"=>entry["roles"],
                "flow_sha256"=>entry["flow_sha256"],
                "allocated_sec"=>remaining,
            ),
        )
        if stages[j]["physics_pass"]
            out["strict_redispatch_success"]=true
            stages[j]["status"]=="solver_optimal" && (out["strict_cost_optimal"]=true)
            f=out["final_stage"]
            (f==0 || stages[j]["operating_cost"]<stages[f]["operating_cost"]) &&
                (out["final_stage"]=j)
        end
    end
    out["strict_checks"]=checks
    f=out["final_stage"]
    out["status"]=f>0 ? "physical_feasible" : "no_verified_physical_solution"
    out["cost_optimization_complete"]=f>0 &&
                                      stages[f]["stage"]=="baseline_strict_check" &&
                                      stages[f]["status"]=="solver_optimal"
    out["elapsed_sec"]=r3_clock()-start
    return out
end
