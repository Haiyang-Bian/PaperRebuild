using Test, PaperRebuild, JuMP, HiGHS

include("r7_lossy_mass_fixtures.jl")

@testset "R7-H1/H2 lossy mass coordinates and independent parcels" begin
    opt = optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads" => 1,
        "primal_feasibility_tolerance" => 1e-9,
        "dual_feasibility_tolerance" => 1e-9,
    )
    for q in ([0.3, 0.0, 0.7, 2.1], [1.0, 1.0, 1.0, 1.0], [2.2, 0.2, 1.7, 0.5]),
        rate in (0.0, 0.08, 0.2)

        dt = [1.0, 0.5, 1.5, 1.0]
        ambient = [-0.2, 0.1, -0.1, 0.0]
        inlet = [0.4, 0.5, 0.9, 0.7]
        b = lossy_kernel_fixture(q; optimizer = opt, rate, dt, ambient, inlet)
        optimize!(b.model)
        @test termination_status(b.model) == MOI.OPTIMAL
        check_lossy_kernel_replay(b, q; rate, dt, ambient, inlet)
        @test b.block.quadrature_bound < 1e-10
        @test all(F in (VariableRef, AffExpr) for (F, S) in list_of_constraint_types(b.model))
    end
    # 停流仍冷却；不以任意出口占位温度制造热量。
    b = lossy_kernel_fixture(
        [0.0, 0.0];
        optimizer = opt,
        rate = 0.2,
        ambient = [0.1, 0.1],
        initial = [0.7, 0.7],
    )
    optimize!(b.model)
    @test termination_status(b.model) == MOI.OPTIMAL
    @test value(b.inventory[3]) ≈ 0.1+0.6exp(-0.4) atol=1e-10
    @test sum(value.(b.block.loss)) ≈ 0.6*(1-exp(-0.4)) atol=1e-10
    # 均值合格并不代表每段都合格：小冷段越过温区下限必须拒绝。
    b = lossy_kernel_fixture(
        [0.0];
        optimizer = opt,
        rate = 0.2,
        ambient = [-0.5],
        initial = [0.01, 0.9],
    )
    optimize!(b.model)
    @test termination_status(b.model) == MOI.INFEASIBLE
end

@testset "R7-H4 quadrature contract and nonlinear type" begin
    for n in (5, 10)
        x, w = PaperRebuild.r7_gauss_unit(n)
        @test all(0 .< x .< 1) && all(w .> 0)
        for p in 0:(2n-1)
            @test sum(w .* x .^ p) ≈ 1/(p+1) atol=5e-15
        end
        @test r7_loss_quadrature_bound(0.0, 1.0; order = n) == 0.0
    end
    @test_throws Exception r7_loss_quadrature_bound(1, 1; order = 3)
    @test_throws Exception r7_loss_quadrature_bound(Inf, 1)
    @test_throws Exception lossy_kernel_fixture([-0.1])
    @test_throws Exception lossy_kernel_fixture([0.1]; rate = 100)
    @test_throws Exception lossy_kernel_fixture([0.1]; dt = [0.0])
    b = lossy_kernel_fixture([0.3, 0.0, 0.7]; variable_flow = true)
    @test any(F == NonlinearExpr for (F, S) in list_of_constraint_types(b.model))
    @test b.block.nonlinear_loss
end
