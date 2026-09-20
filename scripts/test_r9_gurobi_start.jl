# 可选商用环境专项；不纳入无许可CI，也不求解科研案例。
using Test, Gurobi, JuMP
include(joinpath(@__DIR__, "gurobi_primal_start.jl"))

@testset "R9 native initial point covers bridges without changing scientific controls" begin
    model = Model(Gurobi.Optimizer)
    set_silent(model)
    @variable(model, 0.0 <= x <= 2.0)
    @variable(model, 1.0 <= y <= 8.0)
    @constraint(model, y == exp(x))
    @constraint(model, [2+x, y/2, x] in SecondOrderCone())
    @objective(model, Min, y)
    MOI.Utilities.attach_optimizer(backend(model))
    point = Dict(x=>1.0, y=>exp(1.0))
    before = copy(point)
    report = set_gurobi_native_primal_start!(model, point)
    @test point == before
    @test report["original_point_unchanged"]
    @test report["all_finite"]
    @test report["original_count"] == 2
    @test report["native_count"] == 6
    @test report["fixed_auxiliary_count"] == 1
    @test report["linear_auxiliary_count"] == 3
    @test report["maximum_linear_violation"] < 1e-12
    @test report["maximum_bound_violation"] == 0
    @test !has_values(model)
    @test set_gurobi_native_primal_start!(model, point) == report
    @test_throws ErrorException set_gurobi_native_primal_start!(model, Dict(x=>1.0))
    @test_throws ErrorException set_gurobi_native_primal_start!(model, Dict(x=>NaN, y=>exp(1.0)))
    # 无法从等式唯一确定的额外量不能任意补零。
    native = unsafe_backend(model)
    @test Gurobi.GRBaddvar(
        native,
        0,
        C_NULL,
        C_NULL,
        0.0,
        -Inf,
        Inf,
        Gurobi.GRB_CONTINUOUS,
        "unresolved_auxiliary",
    ) == 0
    @test_throws ErrorException set_gurobi_native_primal_start!(model, point)
end

@testset "R9 implied physical cones and their retained sign conditions" begin
    for v in (0.81, 1.0, 1.21), P in (-2.0, 0.0, 2.0), Q in (-0.5, 0.0, 0.5)
        ell = (P^2+Q^2)/v
        cone = [v+ell, 2P, 2Q, ell-v]
        @test cone[1] >= 0
        @test abs(cone[1]^2-sum(abs2, cone[2:end])) < 1e-12
    end
    for mu in (1e-3, 0.1, 1.0), m in (0.1, 1.0, 30.0)
        kappa = mu*m^2
        cone = [kappa+1, 2sqrt(mu)*m, kappa-1]
        @test cone[1] >= 0
        @test abs(cone[1]^2-sum(abs2, cone[2:end])) < 1e-9
    end
    # 只保留乘积等式而丢掉平方量正号不能得到原锥；是禁止删除边界的反例。
    v, ell, P, Q = -1.0, -1.0, 1.0, 0.0
    @test v*ell == P^2+Q^2
    @test v+ell < 0
end
