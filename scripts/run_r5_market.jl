include("r5_market_setup.jl")
length(ARGS) in (2, 3, 4) || error("参数：案例TOML 新运行目录 [highs|clarabel|gurobi] [秒]")
c=load_r5_market_case(ARGS[1])
solver=length(ARGS)>=3 ? Symbol(ARGS[3]) : :highs
budget=length(ARGS)>=4 ? parse(Float64, ARGS[4]) : 60.0
optimizer=try
    r5_market_optimizer(solver)
catch err
    let cause=err
        ()->throw(cause)
    end
end
r=Base.invokelatest(solve_r5_market, c; optimizer, budget_sec = budget)
save_r5_market_run(c, r, ARGS[2])
println(
    r["run_id"],
    " | ",
    r["status"],
    " | primal=",
    r["validation"]["model_pass"],
    " | KKT=",
    r["validation"]["kkt_pass"],
)
