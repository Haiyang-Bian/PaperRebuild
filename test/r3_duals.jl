using Test, JuMP, Clarabel

@testset "R3 dual scaling minimal examples" begin
    for scale in (1.0, 1000.0), active in (true, false)
        model = Model(Clarabel.Optimizer)
        set_silent(model)
        @variable(model, m)
        @variable(model, 0 <= k <= 10)
        fix(m, 1.0)
        @constraint(model, scale*[k+1, 2m, k-1] in SecondOrderCone())
        active || fix(k, 2.0; force = true)
        @objective(model, Min, k)
        optimize!(model)
        evidence = PaperRebuild.r3_kkt(model)
        @test evidence["trusted"]
        @test objective_value(model) ≈ (active ? 1 : 2) atol=1e-6
        @test dual(FixRef(m)) ≈ (active ? 2 : 0) atol=1e-4
    end
end
