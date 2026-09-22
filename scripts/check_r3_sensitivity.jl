push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r3_setup.jl")
using Clarabel
if "--gurobi" in ARGS
    import Gurobi
end
c=load_r2_case("configs/r2/single-source.toml")
m=PaperRebuild.r2_flow_matrix(c)
b=build_r3_subproblem(c, m)
r=PaperRebuild.r3_solve(
    c,
    ()->b,
    "--gurobi" in ARGS ? r3_gurobi_factory(Gurobi) : Clarabel.Optimizer;
    sensitivity = true,
)
s=r["sensitivity"]
println(
    "KKT ",
    [(k, get(s["kkt"], k, missing)) for k in ("primal", "dual", "complementarity", "stationarity")],
)
for row in sort(get(s["kkt"], "rows", []); by = x->-x["complementarity"])[1:5]
    println(row)
end
