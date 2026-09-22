include("r5_market_setup.jl")
length(ARGS) in (2, 3, 4)||error("参数：案例TOML 新运行目录 [highs|clarabel|gurobi] [秒预算]")
case=load_r5_dispatch_case(ARGS[1])
solver=length(ARGS)>=3 ? Symbol(ARGS[3]) : :highs
budget=length(ARGS)==4 ? parse(Float64, ARGS[4]) : 60.0
optimizer=r5_market_optimizer(solver)
r=Base.invokelatest(solve_r5_dispatch, case; optimizer, budget_sec = budget)
save_r5_dispatch_run(case, r, ARGS[2])
println(
    r["status"],
    "; model=",
    r["validation"]["model_pass"],
    "; cost complete=",
    r["cost_optimization_complete"],
)
