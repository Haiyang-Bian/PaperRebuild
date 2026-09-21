using Test, PaperRebuild, JuMP, HiGHS
root=dirname(@__DIR__)
push!(LOAD_PATH, joinpath(root, "tools/solvers"))
pushfirst!(DEPOT_PATH, joinpath(root, ".julia"))
include("r9_gurobi_start.jl")
using .R9GurobiStart: Gurobi
env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
oracle=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1, "output_flag"=>false)
c=load_r5_risk_case(joinpath(root, "configs/r5/risk/hard_zero.toml"))
w=solve_r9_common_witness(c; optimizer = oracle, budget_sec = 30)
@testset "R9-CX1:CX3 native compact LP/MIP and actual solver logging" begin
    # Gurobi日志句柄可在优化器析构前保持打开；保留项目tmp下独立目录供核查。
    let dir=mktempdir(joinpath(root, "tmp"); prefix = "r9-compact-native-", cleanup = false)
        for lp in (true, false)
            logfile=joinpath(dir, lp ? "lp.log" : "mip.log")
            opt=optimizer_with_attributes(
                ()->Gurobi.Optimizer(env),
                "Threads"=>1,
                "FeasibilityTol"=>1e-9,
                "OptimalityTol"=>1e-9,
                "MIPGap"=>1e-9,
                "LogFile"=>logfile,
                "LogToConsole"=>0,
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
                representation = :r9_compact_v1,
                solver_log = true,
            )
            @test r["status"]=="solver_optimal" && r["has_candidate"]
            @test r["native_start"]["exact_readback"]
            @test r["native_start"]["attribute"]==(lp ? "PStart" : "Start")
            @test all(
                r["validation"][k] for
                k in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
            )
            @test r["solver_objective"]≈2.085 atol=1e-7
            @test r["representation"]=="r9_compact_v1" && r["solver_logging_requested"]
            # 真实优化进度必须进入文件；文件存在或只有头部均不足以证明日志启用。
            logtext=read(logfile, String)
            @test occursin("Optimize a model with", logtext)
            @test occursin("Optimal objective", logtext) ||
                  occursin("Optimal solution found", logtext)
        end
    end
end
