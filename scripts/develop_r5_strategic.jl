include("r5_strategic_setup.jl")
include("r5_strategic_cases.jl")
which = length(ARGS)>=1 ? Symbol(ARGS[1]) : :gurobi
name = length(ARGS)>=2 ? ARGS[2] : "hard_zero"
dest =
    length(ARGS)>=3 ? ARGS[3] :
    joinpath("results", "runs", "r5-strategic-dev-"*Dates.format(Dates.now(), "yyyymmdd-HHMMSS"))
ispath(dest) && error("开发记录不覆盖")
c = r5_strategic_fixture(name)
kwargs =
    which==:gurobi ? (;) :
    (
        risk_pattern = [0, 0, 0],
        complementarity_pattern = Dict(k=>0 for k in keys(build_r5_strategic(c).market.pairs)),
    )
r = solve_r5_strategic(
    c;
    optimizer = r5_strategic_optimizer(which),
    oracle_optimizer = r5_market_optimizer(:highs),
    budget_sec = 120.0,
    kwargs...,
)
save_r5_strategic_run(c, r, dest)
println(r["status"], " ", get(r, "error", ""))
v = r["validation"]
println(
    "model=",
    v["model_pass"],
    " independent=",
    v["independent_market_kkt_pass"],
    " risk=",
    v["risk_pass"],
    " total=",
    get(v, "worst_total_cost_USD", NaN),
    " complete=",
    r["cost_optimization_complete"],
)
