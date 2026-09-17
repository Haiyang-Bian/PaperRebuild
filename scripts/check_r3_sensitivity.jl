include("r3_setup.jl")
using Clarabel
c=load_r2_case("configs/r2/single-source.toml")
m=PaperRebuild.r2_flow_matrix(c)
b=build_r3_subproblem(c, m)
r=PaperRebuild.r3_solve(c, ()->b, Clarabel.Optimizer; sensitivity = true)
s=r["sensitivity"]
println(
    "KKT ",
    [(k, get(s["kkt"], k, missing)) for k in ("primal", "dual", "complementarity", "stationarity")],
)
for row in get(s["kkt"], "rows", [])
    if row["complementarity"]>1e-5 || row["primal_error"]>1e-5
        println(row)
    end
end
