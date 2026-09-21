using Test, PaperRebuild, TOML, JuMP, HiGHS
root=dirname(@__DIR__)
push!(LOAD_PATH, joinpath(root, "tools/solvers"))
pushfirst!(DEPOT_PATH, joinpath(root, ".julia"))
include("r9_gurobi_start.jl")
using .R9GurobiStart: Gurobi
env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
oracle=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1, "output_flag"=>false)
c=R5RiskCase(TOML.parsefile(joinpath(root, "configs/r5/risk/hard_zero.toml")))
w=solve_r9_common_witness(c; optimizer = oracle, budget_sec = 30)
@testset "R9 original-risk native LP/MIP seeded solve" begin
    for lp in (true, false)
        opt=optimizer_with_attributes(
            ()->Gurobi.Optimizer(env),
            "Threads"=>1,
            "FeasibilityTol"=>1e-9,
            "OptimalityTol"=>1e-9,
            "MIPGap"=>1e-9,
        )
        if lp
            push!(opt.params, MOI.RawOptimizerAttribute("Method")=>0)
            push!(opt.params, MOI.RawOptimizerAttribute("LPWarmStart")=>2)
        end
        r=solve_r9_seeded_risk(
            c,
            w;
            optimizer = opt,
            seed! = R9GurobiStart.set_native_start!,
            oracle_optimizer = oracle,
            pattern = lp ? zeros(Int, 3) : nothing,
            budget_sec = 60,
        )
        @test r["has_candidate"] && r["status"]=="solver_optimal"
        @test r["native_start"]["exact_readback"]
        @test r["native_start"]["attribute"]==(lp ? "PStart" : "Start")
        @test all(
            r["validation"][k] for k in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
        )
        @test r["solver_objective"]<r["initial_point_audit"]["objective"]-1e-3
    end
end
