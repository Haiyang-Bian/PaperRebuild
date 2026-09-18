using PaperRebuild, TOML, SHA
include("r5_market_cases.jl")
root=normpath(joinpath(@__DIR__, ".."))
dest=joinpath(root, "configs", "r5", "market")
ispath(dest)&&error("不覆盖冻结市场案例")
base=load_r5_market_case(joinpath(root, "configs", "r5", "market-base.toml"))
cases=r5_market_study_cases(base)
names=sort!(collect(keys(cases)))
records=[
    Dict("id"=>name*"--"*solver, "case"=>name, "solver"=>solver) for name in names for
    solver in ("highs", "clarabel")
]
append!(
    records,
    [
        Dict("id"=>name*"--gurobi", "case"=>name, "solver"=>"gurobi") for
        name in ("hand_hour", "two_bus")
    ],
)
rules=Dict(
    "schema"=>"r5-market-study-v1",
    "origin"=>"synthetic",
    "budget_sec"=>60.0,
    "objective"=>"Fixed-bid clearing; fixed ordinary-load utility constant omitted; not system resource cost.",
    "acceptance"=>"Unchanged A1 power, KKT 1e-6 and A2 relative objective/duality gap 1e-4.",
    "independent_dual"=>"Same total 60-second budget includes primal, separately built dual and modeling.",
    "settings"=>Dict(
        "highs"=>Dict(
            "threads"=>1,
            "primal_feasibility_tolerance"=>1e-9,
            "dual_feasibility_tolerance"=>1e-9,
        ),
        "clarabel"=>Dict("tol_feas"=>1e-10, "tol_gap_abs"=>1e-10, "tol_gap_rel"=>1e-10),
        "gurobi"=>Dict("Threads"=>1, "Seed"=>23, "FeasibilityTol"=>1e-9, "OptimalityTol"=>1e-9),
    ),
    "input_sha256"=>Dict(name=>cases[name].sha256 for name in names),
    "records"=>records,
)
mkpath(dest)
for name in names
    write(joinpath(dest, name*".toml"), PaperRebuild.r5_market_text(cases[name].data))
end
write(joinpath(dest, "study.toml"), PaperRebuild.r5_market_text(rules))
println("Frozen eight inputs and 18 runs before formal optimization.")
