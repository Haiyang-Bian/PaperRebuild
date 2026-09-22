include("r5_risk_setup.jl")

isempty(ARGS)&&error(
    "命令：run CASE NEWDIR [cuts|critical|paper_critical] [highs|gurobi]；verify DIR；compare LEFT RIGHT",
)
action=first(ARGS)
if action=="run"
    3<=length(ARGS)<=5||error("run CASE NEWDIR [route] [solver]")
    c=load_r5_risk_case(ARGS[2])
    target=abspath(ARGS[3])
    ispath(target)&&error("不覆盖已有运行")
    route=length(ARGS)>=4 ? Symbol(ARGS[4]) : :cuts
    solver=length(ARGS)>=5 ? Symbol(ARGS[5]) : :highs
    spec=R5BendersSpec(
        feasibility = route,
        cut_arithmetic = :rational_box,
        diagnostic_scale = 1024.0,
    )
    optimizer=try
        r5_risk_optimizer(solver)
    catch err
        let cause=err
            ()->throw(cause)
        end
    end
    result=Base.invokelatest(
        solve_r5_benders,
        c;
        optimizer,
        oracle_optimizer = r5_risk_optimizer(:clarabel),
        spec,
        budget_sec = 600,
    )
    path=save_r5_benders_run(c, result, target)
    loaded=read_r5_benders_run(path)
    println(
        "Saved ",
        path,
        " status=",
        result["status"],
        " model=",
        loaded.validation["model_pass"],
        " cost_complete=",
        result["cost_optimization_complete"],
        " scope=",
        loaded.validation["infeasibility_scope"],
    )
elseif action=="verify"
    length(ARGS)==2||error("verify DIR")
    loaded=read_r5_benders_run(ARGS[2])
    println(
        loaded.result["run_id"],
        " status=",
        loaded.result["status"],
        " evidence=",
        loaded.validation["evidence_pass"],
        " model=",
        loaded.validation["model_pass"],
        " stopping=",
        loaded.validation["stopping_pass"],
    )
elseif action=="compare"
    length(ARGS)==3||error("compare LEFT RIGHT")
    TOML.print(stdout, compare_r5_benders_runs(ARGS[2], ARGS[3]); sorted = true)
else
    error("未知Benders命令")
end
