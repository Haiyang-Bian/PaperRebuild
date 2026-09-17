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

@testset "R3 quadratic expression derivatives in KKT" begin
    for quadratic_objective in (false, true)
        model=Model(Clarabel.Optimizer)
        set_silent(model)
        @variable(model, m)
        @variable(model, k>=0)
        fix(m, 1.0)
        if quadratic_objective
            fix(k, 0.0; force = true)
            @objective(model, Min, 0.5m^2)
        else
            @constraint(model, m^2<=k)
            @objective(model, Min, k)
        end
        optimize!(model)
        @test PaperRebuild.r3_kkt(model)["trusted"]
        @test objective_value(model)≈(quadratic_objective ? 0.5 : 1.0) atol=1e-6
        @test dual(FixRef(m))≈(quadratic_objective ? 1.0 : 2.0) atol=1e-5
    end
end

@testset "R3 physical units and redundant cones" begin
    for unit_scale in (1.0, 1000.0), redundant in (false, true)
        model=Model(Clarabel.Optimizer)
        set_silent(model)
        for key in ("tol_gap_abs", "tol_gap_rel", "tol_feas")
            set_optimizer_attribute(model, key, 1e-10)
        end
        @variable(model, q)
        @variable(model, 0<=k<=10)
        # q分别用kg/s与g/s表示同一流量，数学乘子通过链式法则换回kg/s。
        fix(q, unit_scale)
        @constraint(model, [k+1, 2q/unit_scale, k-1] in SecondOrderCone())
        redundant && @constraint(model, [k+1, 2q/unit_scale, k-1] in SecondOrderCone())
        @objective(model, Min, k)
        optimize!(model)
        @test PaperRebuild.r3_kkt(model)["trusted"]
        @test objective_value(model)≈1 atol=1e-6
        @test unit_scale*dual(FixRef(q))≈2 atol=1e-4
    end
end
