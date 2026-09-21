using Test, PaperRebuild, HiGHS
include("r9_reserve_support.jl")
@testset "R9 single-event ambiguity versus independent transport LP" begin
    p=[0.02, 0.13, 0.25, 0.60]
    points=[0.0, 0.1, 0.3, 1.0]
    D=abs.(points .- points')
    for rho in (0.0, 0.01, 0.15, 1.0), i in eachindex(p)
        score=zeros(4)
        score[i]=1.0
        r=r5_worst_distribution(
            p,
            D,
            score,
            rho;
            optimizer = HiGHS.Optimizer,
            quantity = :probability,
        )
        @test r["validation"]["pass"]
        bound=R9ReserveSupport.single_event_bound(p, D, rho, i)
        @test isapprox(bound, r["validation"]["primal_value"]; atol = 1e-8, rtol = 0)
        rho==0 && @test bound==p[i]
        rho==1 && @test isapprox(bound, 1.0; atol = 1e-12)
    end
    @test_throws ErrorException R9ReserveSupport.single_event_bound(p, D, -0.1, 1)
    @test_throws ErrorException R9ReserveSupport.single_event_bound(p, zeros(2, 2), 0.1, 1)
end
