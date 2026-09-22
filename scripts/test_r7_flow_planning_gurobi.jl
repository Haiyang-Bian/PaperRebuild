using Test, PaperRebuild, Gurobi, JuMP, TOML
include(joinpath(@__DIR__, "..", "test", "r7_flow_planning_fixtures.jl"))
length(ARGS)==1 || error("usage: test_r7_flow_planning_gurobi.jl NEW_EVIDENCE_DIR")
out=abspath(only(ARGS))
ispath(out)&&error("不覆盖联合流量开发证据")
mkpath(out)
opt=optimizer_with_attributes(
    Gurobi.Optimizer,
    "Threads"=>1,
    "NonConvex"=>2,
    "FeasibilityTol"=>1e-9,
    "OptimalityTol"=>1e-9,
    "IntFeasTol"=>1e-9,
    "MIPGap"=>1e-8,
    "DualReductions"=>0,
)
@testset "R7-J2/J4 nonconvex continuous shared planning" begin
    for (id, free_normal, healthy, limit) in (
        ("healthy_recovery", false, true, 0.0),
        ("shared_continuous", true, false, 0.4),
        ("zero_loss_impossible", true, false, 0.0),
    )
        c, s=joint_test_case(; free_normal, free_recovery = true, healthy_only = healthy, limit)
        # 每个开发输入在该次优化之前留存；不把该冒烟批次冒称正式统计实验。
        write(
            joinpath(out, id*"-input.toml"),
            PaperRebuild.r7_text(
                Dict(
                    "normal"=>c.normal.data,
                    "planning"=>c.specification,
                    "spec"=>s,
                    "budget_sec"=>60.0,
                    "origin"=>"synthetic_development",
                ),
            ),
        )
        r=solve_r7_flow_planning(c, s; optimizer = opt, budget_sec = 60)
        save_r7_flow_planning(c, s, r, joinpath(out, id))
        println(
            id,
            ": ",
            r["status"],
            " accepted=",
            r["candidate_accepted"],
            " cost=",
            get(r["validation"], "cost_USD", "missing"),
        )
        flush(stdout)
        if id=="zero_loss_impossible"
            @test r["status"]=="infeasible_certified"
            @test !r["candidate_accepted"]
        else
            @test r["candidate_accepted"]
            @test r["validation"]["cost_USD"]<=(healthy ? 192.0285 : 193.275)+1e-4
            @test all(w["thermal"]["same_dispatch_pass"] for w in r["validation"]["witness_checks"])
        end
    end
end
