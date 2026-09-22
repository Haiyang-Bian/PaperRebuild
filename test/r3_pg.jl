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

@testset "R3 convex projection and outer trace" begin
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    m=PaperRebuild.r2_flow_matrix(c)
    b=build_r3_projection(c, m)
    @test b.class=="SOCP"
    @test !haskey(b.constraints, "3-33")
    @test haskey(b.constraints, "3-26")
    p=PaperRebuild.r3_project(c, m, Clarabel.Optimizer)
    @test p["status"]=="projected"
    @test maximum(abs, PaperRebuild.r3_matrix(p["flow"])-m)<1e-4
    p2=PaperRebuild.r3_project(c, PaperRebuild.r3_matrix(p["flow"]), Clarabel.Optimizer)
    @test maximum(abs, PaperRebuild.r3_matrix(p2["flow"])-m)<2e-4
    impossible=PaperRebuild.r3_project(
        c,
        m,
        Clarabel.Optimizer;
        center = m,
        gradient = zeros(size(m)),
        violation = 1.0,
    )
    @test impossible["status"]=="projection_infeasible"
    @test PaperRebuild.r3_project(c, m, nothing)["status"]=="not_run_solver"
    @test PaperRebuild.r3_project(c, m, ()->error("license fixture"))["status"]=="not_run_license"
    @test_throws ArgumentError build_r3_projection(c, zeros(2, 4))
    @test_throws ArgumentError solve_r3_projected_gradient(c; budget_sec = 601)
    @test !r3_value_sensitivity(c, build_r3_subproblem(c, m))["trusted"]
    @test !r3_value_sensitivity(c, build_r3_subproblem(c, m; physical = true))["trusted"]
    @test PaperRebuild.r3_project(c, m, Clarabel.Optimizer; deadline = 0)["status"]=="budget_exhausted"
    d=deepcopy(c.data)
    d["heat"]["pipes"][1]["flow_min"]=1.0
    d["heat"]["pipes"][1]["flow_max"]=1.0
    fixed=R2Case(d, "equal-box")
    projected=PaperRebuild.r3_project(fixed, fill(2.0, 1, 4), Clarabel.Optimizer)
    @test projected["status"]=="projected"
    @test maximum(abs, PaperRebuild.r3_matrix(projected["flow"]) .- 1)<1e-6
    run=solve_r3_projected_gradient(
        c;
        initial_flow = m,
        convex_optimizer = Clarabel.Optimizer,
        max_iterations = 3,
        budget_sec = 60,
    )
    @show run["outer_status"] length(run["iterations"]) run["final_stage"]
    @test run["final_stage"]>0
    @test all(validate_r3_iteration(c, row).pass for row in run["iterations"])
    @test !any(r["stage"]=="direct_repair" for r in run["stages"])
    @test validate_r3_solution(c, run).physical_pass
    corrupted=deepcopy(run)
    corrupted["iterations"][1]["merit"]+=1
    @test_throws ArgumentError validate_r3_solution(c, corrupted)
    mktempdir() do dir
        saved=save_r3_run(c, run; root = dir, run_id = "pg-fixture")
        @test read_r3_run(saved).validation.physical_pass
        open(io->write(io, "\n#tamper"), joinpath(saved, "run.toml"), "a")
        @test_throws ArgumentError read_r3_run(saved)
    end
    noinit=solve_r3_projected_gradient(c; budget_sec = 1)
    @test noinit["outer_status"]=="initialization_not_run_solver"
    license=solve_r3_projected_gradient(c; optimizer = ()->error("license fixture"), budget_sec = 1)
    @test license["outer_status"]=="initialization_failed"
    harddata=deepcopy(c.data)
    harddata["electric"]["nodes"][2]["P_MW"].=10.0
    hard=solve_r3_projected_gradient(
        R2Case(harddata, "hard-infeasible");
        initial_flow = m,
        convex_optimizer = Clarabel.Optimizer,
        max_iterations = 2,
        budget_sec = 60,
    )
    @test hard["outer_status"]=="hard_constraints_infeasible"
    @test hard["final_stage"]==0
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
        for q in eachindex(m), step in (1e-3, 3e-4, 1e-4)
            delta=zeros(size(m))
            delta[q]=step
            plus=PaperRebuild.r3_solve(
                c,
                ()->build_r3_subproblem(c, m+delta; mode),
                Clarabel.Optimizer,
            )
            minus=PaperRebuild.r3_solve(
                c,
                ()->build_r3_subproblem(c, m-delta; mode),
                Clarabel.Optimizer,
            )
            fd=(plus["solver_objective"]-minus["solver_objective"])/(2step)
            @test abs(fd-grad[q])/max(1, abs(fd))<=1e-3
        end
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
