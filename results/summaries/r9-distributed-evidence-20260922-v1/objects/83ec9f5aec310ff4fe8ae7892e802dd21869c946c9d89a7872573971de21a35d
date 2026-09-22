function r3_baseline_row(loaded)
    c, r=loaded.case, loaded.result
    model=get(r, "best_subproblem_stage", 0)
    f=r["final_stage"]
    best=model>0 ? r["stages"][model] : nothing
    final=f>0 ? r["stages"][f] : nothing
    core=get(get(c.data, "r3_mechanism", Dict()), "core_periods", c.data["T"])
    function cost_part(stage, a, b)
        isnothing(stage) && return NaN
        v=stage["values"]
        return c.data["dt_h"]*(
            sum(c.data["grid_price"][a:b] .* v["P_grid"][a:b]) + sum(
                g["cost_per_MWh"]*sum(v["P_device"][i][a:b]) for
                (i, g) in enumerate(c.data["devices"])
            )
        )
    end
    initial=findfirst(s->s["stage"] in ("baseline_dispatch", "baseline_diagnostic"), r["stages"])
    diagnostic=findfirst(s->s["stage"]=="baseline_diagnostic", r["stages"])
    init=isnothing(initial) ? nothing : r["stages"][initial]
    evidence=get(r, "algorithm", "")=="r3_paper_structure_v1" ? r3_baseline_evidence(c, r) : Any[]
    firstfeasible=findfirst(x->x["mode"]=="dispatch", evidence)
    return (
        run_id = loaded.metadata["run_id"],
        input_sha256 = c.sha256,
        core_sha256 = r3_core_signature(c, core),
        algorithm = r["algorithm"],
        geometry = get(get(r, "baseline_spec", Dict()), "geometry", "reference"),
        initial_displacement = get(get(r, "baseline_spec", Dict()), "initial_displacement", NaN),
        initial_flow_sha256 = get(r, "initial_flow_sha256", "not_applicable"),
        outer_status = r["outer_status"],
        outer_converged = get(r, "outer_converged", false),
        iterations = length(get(r, "iterations", Any[])),
        initial_model_pass = !isnothing(init) && init["model_pass"],
        initial_diagnostic = isnothing(diagnostic) || diagnostic>3 ? NaN :
                             get(r["stages"][diagnostic], "solver_objective", NaN),
        first_feasible_iteration = isnothing(firstfeasible) ? -1 :
                                   evidence[firstfeasible]["iteration"],
        model_cost = isnothing(best) ? NaN : best["operating_cost"],
        physical_pass = loaded.validation.physical_pass,
        physical_cost = isnothing(final) ? NaN : final["operating_cost"],
        strict_redispatch_success = get(
            r,
            "strict_redispatch_success",
            r["algorithm"]=="r3_cost_reference_v1" && loaded.validation.physical_pass,
        ),
        cost_optimization_complete = r["cost_optimization_complete"],
        core_cost = cost_part(final, 1, core),
        tail_cost = cost_part(final, core+1, c.data["T"]),
        periods = c.data["T"],
        core_periods = core,
        terminal_required = core<c.data["T"],
        elapsed_sec = r["elapsed_sec"],
    )
end

"""
    compare_r3_baselines(runs; factor=:geometry)

对read_r3_run返回的配对基线运行比较投影几何、初值、步幅或边界。
先核对只有声明因素不同：边界组必须具有相同核心时段、历史、设备和核心初始流量；
其他组要求同输入与运行约定。不求解，不将跨模型费用差称作间隙，不对core_only作周期排名。
返回逐项状态与模型费用、物理费用、核心/尾段费用；NaN表示无合格候选，不能解释为零。
"""
function compare_r3_baselines(runs; factor = :geometry)
    factor in (:geometry, :initialization, :step, :boundary) || throw(ArgumentError("未知配对因素"))
    length(runs)>=2 || throw(ArgumentError("至少需要两项配对运行"))
    first_run=first(runs)
    c0, r0=first_run.case, first_run.result
    for loaded in runs
        c, r=loaded.case, loaded.result
        r["algorithm"]==r0["algorithm"]=="r3_paper_structure_v1" ||
            throw(ArgumentError("仅比较同一基线"))
        validate_r3_solution(c, r)
        (r["budget_sec"], r["max_iterations"])==(r0["budget_sec"], r0["max_iterations"]) ||
            throw(ArgumentError("配对预算不同"))
        a, b=deepcopy(r["baseline_spec"]), deepcopy(r0["baseline_spec"])
        factor==:geometry && (delete!(a, "geometry"); delete!(b, "geometry"))
        factor==:step && (delete!(a, "initial_displacement"); delete!(b, "initial_displacement"))
        a==b || throw(ArgumentError("配对算法设置存在额外差异"))
        if factor==:boundary
            core=c0.data["r3_mechanism"]["core_periods"]
            r3_core_signature(c, core)==r3_core_signature(c0, core) ||
                throw(ArgumentError("共同核心数据不同"))
            r3_matrix(r["initial_flow"])[:, 1:core]==r3_matrix(r0["initial_flow"])[:, 1:core] ||
                throw(ArgumentError("核心初值不同"))
            oa, ob=deepcopy(r["operation"]), deepcopy(r0["operation"])
            pop!(oa, "tail_return_rule", nothing)
            pop!(ob, "tail_return_rule", nothing)
            oa==ob || throw(ArgumentError("边界比较改变了其他运行模式规则"))
        else
            c.data==c0.data && c.sha256==c0.sha256 || throw(ArgumentError("配对输入不同"))
            get(r, "operation", nothing)==get(r0, "operation", nothing) ||
                throw(ArgumentError("配对模式不同"))
            factor==:initialization ||
                r["initial_flow_sha256"]==r0["initial_flow_sha256"] ||
                throw(ArgumentError("配对初值不同"))
        end
    end
    return [r3_baseline_row(x) for x in runs]
end
