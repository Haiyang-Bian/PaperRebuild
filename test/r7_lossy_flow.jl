using Test, PaperRebuild, JuMP, HiGHS
include("r7_flow_planning_fixtures.jl")

@testset "R7-H5 integrated loss and exclusive batteries" begin
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
    )
    @test_throws Exception joint_test_case(UA = 10.0)
    for UA in (0.0, 10.0)
        c, s=joint_test_case(; UA, thermal = :lossy_gauss, battery_rule = "per_period_exclusive_v1")
        b=build_r7_flow_planning(c, s)
        @test b.model_class=="MILP"
        r=solve_r7_flow_planning(c, s; optimizer = opt, budget_sec = 60)
        @test r["candidate_accepted"]
        @test r["domain_cost_complete"]
        @test r["validation"]["exact_transport_optimality_verified"]===false
        @test all(w["model_pass"] for w in r["validation"]["witness_checks"])
        UA==0 && @test r["validation"]["cost_USD"]≈193.275 atol=1e-6
        mktempdir() do dir
            save_r7_flow_planning(c, s, r, joinpath(dir, "run"))
            @test read_r7_flow_planning(joinpath(dir, "run")).validation["robust_model_pass"]
        end
        nr=solve_r7_normal_flow(
            c.normal,
            s["normal_flow"];
            optimizer = opt,
            budget_sec = 60,
            energy_balance = true,
        )
        @test nr["candidate_accepted"]
        @test nr["domain_cost_complete"]
    end
    c, s=joint_test_case(
        UA = 10.0,
        thermal = :lossy_gauss,
        free_normal = true,
        free_recovery = true,
    )
    @test build_r7_flow_planning(c, s).model_class=="nonconvex_MINLP"
    bad=deepcopy(s)
    bad["normal_flow"]["max_truncation_error"]=1e-3
    @test_throws Exception build_r7_flow_planning(c, bad)
end
