using PaperRebuild, TOML, Dates, UUIDs
isempty(ARGS) && error("操作：run CASE [ROUTE] [NEW_DIRECTORY]；verify RUN；compare RUN REFERENCE")
action = first(ARGS)
if action == "run"
    2 <= length(ARGS) <= 4 || error("run CASE [ROUTE] [NEW_DIRECTORY]")
    include("r5_strategic_setup.jl")
    c = load_r5_strategic_case(ARGS[2])
    route = length(ARGS) >= 3 ? Symbol(ARGS[3]) : :critical
    dir =
        length(ARGS) >= 4 ? ARGS[4] :
        joinpath(
            "results",
            "runs",
            "r5-strategic-benders-"*Dates.format(now(UTC), "yyyymmdd-HHMMSS")*"-"*string(uuid4()),
        )
    ispath(dir) && error("运行目标已存在")
    # 可选Gurobi在当前进程延迟加载；跨过Julia 1.12的全局绑定world-age边界。
    r = Base.invokelatest(
        solve_r5_strategic_benders,
        c;
        optimizer = r5_strategic_optimizer(:gurobi),
        subproblem_optimizer = r5_risk_optimizer(:highs),
        oracle_optimizer = r5_risk_optimizer(:highs),
        spec = R5BendersSpec(
            feasibility = route,
            cut_arithmetic = :rational_box,
            diagnostic_scale = 1024.0,
        ),
        budget_sec = 600,
    )
    saved = save_r5_strategic_benders_run(c, r, dir)
    println(
        "Saved ",
        relpath(saved),
        ": ",
        r["status"],
        " upper=",
        r["validation"]["upper_bound"],
        " complete=",
        r["cost_optimization_complete"],
    )
elseif action == "verify"
    length(ARGS) == 2 || error("verify RUN")
    x = read_r5_strategic_benders_run(ARGS[2])
    println(
        x.result["run_id"],
        " model=",
        x.validation["model_pass"],
        " full_optimal=",
        x.validation["optimality_pass"],
        " declared_domain=",
        x.validation["domain_optimality_pass"],
    )
elseif action == "compare"
    length(ARGS) == 3 || error("compare RUN REFERENCE")
    println(PaperRebuild.r5_market_text(compare_r5_strategic_benders_runs(ARGS[2], ARGS[3])))
else
    error("未知策略分解操作")
end
