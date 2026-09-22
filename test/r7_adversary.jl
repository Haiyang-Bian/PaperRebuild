using PaperRebuild, JuMP, HiGHS, Test, TOML

@testset "R7-inner-dual" begin
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
    )
    c=load_r7_recovery_case(joinpath(@__DIR__, "..", "configs/r7/recovery-hand.toml"))
    @testset "R7-I1-row-extraction" begin
        lp=r7_recovery_lp(c, [1])
        @test length(lp.data["fault_names"])==1
        @test validate_r7_dual(lp, [0], lp.data["dual_seed"])["dual_feasible"]
        @test validate_r7_dual(lp, [1], lp.data["dual_seed"])["dual_feasible"]
        for (z, gamma) in (([1], [0]), ([0], [1]), ([0], [0]))
            p=solve_r7_recovery(c, gamma; optimizer = opt, fixed_z = z)
            dl=build_r7_recourse_dual(r7_recovery_lp(c, z), gamma; optimizer = opt)
            set_silent(dl.model)
            optimize!(dl.model)
            @test termination_status(dl.model)==JuMP.MOI.OPTIMAL
            v=validate_r7_dual(dl.lp, gamma, value.(dl.lambda))
            @test v["dual_feasible"]
            @test p["candidate_accepted"]
            @test v["dual_objective_MWh"]≈p["validation"]["loss_MWh"] atol=1e-7
        end
        # 原线仍闭合时无法适用于断线故障；该LP对偶应无界，不能排除故障。
        b=build_r7_recourse_dual(lp, [1]; optimizer = opt)
        set_silent(b.model)
        optimize!(b.model)
        @test termination_status(b.model) in
              (JuMP.MOI.DUAL_INFEASIBLE, JuMP.MOI.INFEASIBLE_OR_UNBOUNDED)
        @test_throws Exception build_r7_recovery(c, [0]; fault_variables = true)
        @test_throws Exception build_r7_recovery(
            c,
            [0];
            fixed_z = [1],
            fault_variables = true,
            boundary_variables = true,
        )
    end
    @testset "R7-I2-free-variables-and-common-seed" begin
        m=Model()
        @variable(m, x>=0)
        @variable(m, y)
        @variable(m, 0<=g<=1)
        @constraint(m, y==-2)
        @constraint(m, 1<=x+y-g<=3)
        @objective(m, Min, 2x)
        lp=PaperRebuild.r7_linear_recourse(m, [g])
        for gamma in ([0], [1])
            b=build_r7_recourse_dual(lp, gamma; optimizer = opt)
            set_silent(b.model)
            optimize!(b.model)
            @test objective_value(b.model)≈6+2gamma[1] atol=1e-8
            @test validate_r7_dual(lp, gamma, value.(b.lambda))["dual_feasible"]
        end
        @test_throws Exception PaperRebuild.r7_linear_recourse(m, [g, g])
        @objective(m, Min, -x)
        @test_throws Exception PaperRebuild.r7_linear_recourse(m, [g])
        @objective(m, Min, x)
        @constraint(m, x^2<=2)
        @test_throws Exception PaperRebuild.r7_linear_recourse(m, [g])
    end
    @testset "R7-I3-finite-cap-not-dual-M" begin
        cap=r7_recovery_loss_cap(c)
        @test cap.feasible_upper_MWh≈1.0
        @test cap.cap_MWh≈2.0
        b=build_r7_adversary(c, [[1], [0]])
        @test b.model_class=="MILP_native_indicators"
        @test !b.automatic_bridges
        @test all(!has_lower_bound(v) for bl in b.blocks for v in bl.lambda)
        @test_throws Exception build_r7_adversary(c, [[1], [1]])
        @test_throws Exception build_r7_adversary(c, [[2]])
    end
    @testset "R7-I4-fault-dependent-topology-domain" begin
        tie=load_r7_recovery_case(joinpath(@__DIR__, "..", "configs/r7/inner-tie-two-hour.toml"))
        z=[0, 1, 1]
        @test PaperRebuild.r7_topology_roots(tie, [0, 0, 0], z)===nothing
        @test PaperRebuild.r7_topology_roots(tie, [1, 0, 0], z)!==nothing
        lp=r7_recovery_lp(tie, z)
        for gamma in ([0, 0, 0], [1, 0, 0])
            b=build_r7_recourse_dual(lp, gamma; optimizer = opt)
            set_silent(b.model)
            optimize!(b.model)
            if sum(gamma)==0
                @test termination_status(b.model) in
                      (JuMP.MOI.DUAL_INFEASIBLE, JuMP.MOI.INFEASIBLE_OR_UNBOUNDED)
            else
                @test termination_status(b.model)==JuMP.MOI.OPTIMAL
                @test objective_value(b.model)≈0 atol=1e-7
            end
        end
    end
    @testset "R7-I5-budget-and-unsupported-native" begin
        r=solve_r7_adversary(c; optimizer = opt, budget_sec = 0)
        @test r["status"]=="budget_exhausted"
        @test r["validation"]["threshold_status"]=="unresolved"
        r=solve_r7_adversary(c; optimizer = opt)
        @test r["status"]=="solver_or_build_error"
        @test r["validation"]["upper_bound_MWh"]==Inf
        @test !r["validation"]["gap_certified"]
        r=solve_r7_adversary(c; optimizer = nothing)
        @test r["status"]=="solver_or_build_error"
        @test_throws Exception solve_r7_adversary(c; optimizer = opt, max_iterations = 0)
        @test_throws Exception solve_r7_adversary(c; optimizer = opt, deadline = NaN)
        @test_throws Exception solve_r7_adversary(c; optimizer = opt, budget_sec = -1)
    end
end
