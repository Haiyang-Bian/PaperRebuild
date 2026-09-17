using Test, JuMP, Clarabel

@testset "R3 analytic transport Jacobian" begin
    for flows in ([0.8, 1.1, 0.9, 1.2], [0.6, 0.7, 1.1, 0.8]), mass in (1800.0, 4100.0)
        J = r3_transport_jacobian(flows, mass, 3600.0; loss_rate = 1e-5)
        @test !J.switching
        for step in (1e-3, 1e-4, 1e-5), k in eachindex(flows)
            plus, minus = copy(flows), copy(flows)
            plus[k] += step
            minus[k] -= step
            a = r3_transport_jacobian(plus, mass, 3600.0; loss_rate = 1e-5)
            b = r3_transport_jacobian(minus, mass, 3600.0; loss_rate = 1e-5)
            @test maximum(abs.((a.w-b.w)/(2step)-J.Jw[:, k])) < 1e-4
            @test abs((a.decay-b.decay)/(2step)-J.Jdecay[k]) < 1e-5
        end
    end
    @test r3_transport_jacobian([0.5, 1.0, 1.0], 1800, 3600).switching
    @test_throws ArgumentError r3_transport_jacobian([0.0, 1.0], 1800, 3600)
    @test_throws ArgumentError r3_transport_jacobian([0.5, 0.5], 5000, 3600)
end

@testset "R3 dual signs and complete value sensitivity" begin
    for setkind in (:fix, :equality, :lower, :upper)
        model=Model(Clarabel.Optimizer)
        set_silent(model)
        @variable(model, x)
        cr =
            setkind==:fix ? (fix(x, 2); FixRef(x)) :
            setkind==:equality ? @constraint(model, x==2) :
            setkind==:lower ? @constraint(model, x>=2) : @constraint(model, x<=2)
        sign=setkind==:upper ? -1.0 : 1.0
        @objective(model, Min, sign*x)
        optimize!(model)
        @test dual(cr) ≈ sign atol=1e-6
        @test PaperRebuild.r3_kkt(model)["trusted"]
    end
    for name in ("single-source", "two-source"), mode in (:dispatch, :diagnostic)
        c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", name*".toml"))
        m=PaperRebuild.r2_flow_matrix(c)
        # 低流量弹性例保留非零松弛，验证归一化系数的导数。
        mode==:diagnostic && (m .*= 0.72)
        r=PaperRebuild.r3_solve(
            c,
            ()->build_r3_subproblem(c, m; mode),
            Clarabel.Optimizer;
            sensitivity = true,
        )
        @test haskey(r, "sensitivity")
        s=r["sensitivity"]
        if !s["trusted"]
            @show name mode s["reason"] get(s, "stationarity", 0) get(s, "complementarity", 0) get(
                s,
                "relative_gap",
                0,
            )
        end
        @test s["trusted"]
        s["trusted"] || continue
        grad=reduce(vcat, permutedims.(s["gradient"]))
        for step in (1e-3, 3e-4, 1e-4)
            plus=PaperRebuild.r3_solve(
                c,
                ()->build_r3_subproblem(c, m .+ step; mode),
                Clarabel.Optimizer,
            )
            minus=PaperRebuild.r3_solve(
                c,
                ()->build_r3_subproblem(c, m .- step; mode),
                Clarabel.Optimizer,
            )
            fd=(plus["solver_objective"]-minus["solver_objective"])/(2step)
            @test abs(fd-sum(grad))/max(1, abs(fd)) <= 1e-3
        end
    end
end
