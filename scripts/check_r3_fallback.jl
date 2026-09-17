# 显式故障注入：最终费用调度无法调用求解器时，不丢弃已验证的修正候选。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Test, Clarabel
include("r3_setup.jl")
import Gurobi
factory=r3_gurobi_factory(Gurobi)
counter=Ref(0)
function injected_factory()
    counter[]+=1
    counter[]>1 && error("license fixture: intentionally unavailable during final dispatch")
    return factory()
end
c, m=r3_study_case(Dict("case"=>"single-source", "initialization"=>"low_flow", "flow_kg_s"=>0.5))
r=solve_r3_feasibility(
    c;
    optimizer = injected_factory,
    convex_optimizer = Clarabel.Optimizer,
    initial_flow = m,
    budget_sec = 60.0,
)
r["fault_injection"]="final dispatch optimizer throws a synthetic license error; not a real license failure"
path=save_r3_run(c, r)
loaded=read_r3_run(path)
@testset "R3 verified incumbent survives final dispatch failure" begin
    @test counter[]==2
    @test r["status"]=="feasible_incumbent"
    @test !r["cost_optimization_complete"]
    @test loaded.validation.physical_pass
    @test r["stages"][r["final_stage"]]["stage"]=="direct_repair"
    @test last(r["stages"])["status"]=="not_run_license"
end
println("R3_FALLBACK_FIXTURE=", path)
