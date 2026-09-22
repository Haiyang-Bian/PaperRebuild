using PaperRebuild, JuMP, Gurobi, Test, TOML
include(joinpath(@__DIR__, "..", "test", "r7_flow_planning_fixtures.jl"))
length(ARGS)==1 || error("usage: test_r7_lossy_flow_gurobi.jl NEW_OUTPUT")
dest=abspath(only(ARGS))
ispath(dest)&&error("不覆盖有损联合开发运行")
mkpath(dest)
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
@testset "R7-H5 continuous lossy joint development evidence" begin
    for (id, healthy, limit) in (("healthy", true, 0.0), ("all_faults", false, 0.4))
        c, s=joint_test_case(;
            UA = 10.0,
            thermal = :lossy_gauss,
            free_normal = true,
            free_recovery = true,
            healthy_only = healthy,
            limit,
            battery_rule = "per_period_exclusive_v1",
        )
        write(
            joinpath(dest, id*"-input.toml"),
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
        save_r7_flow_planning(c, s, r, joinpath(dest, id))
        println(
            id,
            " status=",
            r["status"],
            " accepted=",
            r["candidate_accepted"],
            " cost=",
            get(r["validation"], "cost_USD", "missing"),
            " error=",
            get(r, "error", "none"),
        )
        flush(stdout)
        @test !r["full_thesis_domain_verified"]
        @test read_r7_flow_planning(joinpath(dest, id)).result["status"]==r["status"]
        if r["candidate_accepted"]
            @test all(w["model_pass"] for w in r["validation"]["witness_checks"])
        else
            @test r["status"] in
                  ("time_limit_no_solution", "time_limit_with_solution", "budget_exhausted")
        end
    end
end
