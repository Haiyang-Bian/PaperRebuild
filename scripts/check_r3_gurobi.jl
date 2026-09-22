# 本机开发检查，不冒充开放CI或完整正式批次。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Test, Clarabel
include("r3_setup.jl")
import Gurobi
factory = r3_gurobi_factory(Gurobi)
entry = Dict("case"=>"single-source", "initialization"=>"low_flow", "flow_kg_s"=>0.5)
c, m = r3_study_case(entry)
r = solve_r3_feasibility(
    c;
    optimizer = factory,
    convex_optimizer = Clarabel.Optimizer,
    initial_flow = m,
    budget_sec = 120.0,
)
path = save_r3_run(c, r)
println("R3_DEV_RUN=", path)
for s in r["stages"]
    println(
        s["stage"],
        ": ",
        s["status"],
        " physics=",
        s["physics_pass"],
        " cost=",
        get(s, "operating_cost", missing),
        " objective=",
        get(s, "solver_objective", missing),
    )
    if haskey(s, "values") && !s["physics_pass"]
        failed = filter(row->!row.pass, validate_r3_solution(c, s).rows)
        println(first(failed, min(6, length(failed))))
    end
end
@testset "R3 commercial direct repair" begin
    @test validate_r3_solution(c, r).physical_pass
    @test any(s->s["stage"]=="direct_repair" && s["physics_pass"], r["stages"])
    @test r["elapsed_sec"]<=120.0+5.0
end
