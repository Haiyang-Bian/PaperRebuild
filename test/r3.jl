using JuMP, Clarabel, TOML

@testset "R3 fixed schedule and reconstruction ch03-060" begin
    c = load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    original = deepcopy(c.data)
    m = reshape([1.0, 1.02, 1.0, 1.02], 1, :)
    @test build_r2_model(c; fixed_flows = true, flow_schedule = m).class == "SOCP"
    r = solve_r2_case(
        c;
        optimizer = Clarabel.Optimizer,
        fixed_flows = true,
        flow_schedule = m,
        budget_sec = 60.0,
    )
    @test validate_r2_solution(c, r).model_pass
    @test r["values"]["m_pipe"][1] ≈ vec(m)
    @test c.data == original
    @test r["input_sha256"] == c.sha256
    before = deepcopy(r)
    reconstructed = reconstruct_r3_pressure(c, r)
    @test r == before
    @test reconstructed["objective"] == r["objective"]
    @test all(reconstructed["values"][k] == v for (k, v) in r["values"] if !startswith(k, "kappa_"))
    @test all(
        x.pass for
        x in validate_r2_solution(c, reconstructed).rows if x.equation in ("3-22", "3-25", "3-26")
    )
    @test_throws ArgumentError build_r2_model(c; flow_schedule = m)
    for invalid in (zeros(1, 4), fill(NaN, 1, 4), fill(2.0, 1, 4), ones(2, 4))
        @test_throws ArgumentError build_r2_model(c; fixed_flows = true, flow_schedule = invalid)
    end
    bad = deepcopy(r)
    bad["values"]["P_grid"][1] += 1
    @test_throws ArgumentError reconstruct_r3_pressure(c, bad)
    mktempdir() do dir
        saved = save_r2_run(c, r; root = dir, run_id = "schedule")
        loaded = read_r2_run(saved)
        @test loaded.result["flow_schedule"] == r["flow_schedule"]
        @test validate_r2_solution(loaded.case, loaded.result).model_pass
        other = deepcopy(r)
        other["flow_schedule"] = [ones(4)]
        otherpath = save_r2_run(c, other; root = dir, run_id = "other-schedule")
        @test_throws ArgumentError compare_r2_runs(saved, otherpath)
    end
end

@testset "R3 elastic diagnostic and workflow" begin
    c = load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    m = fill(0.5, 1, 4)
    b = build_r3_subproblem(c, m; mode = :diagnostic)
    @test b.class=="SOCP"
    @test all(r.equation in ("3-17", "3-35", "3-36", "3-33", "3-34") for r in b.elastic_rows)
    sp = PaperRebuild.r3_solve(c, ()->build_r3_subproblem(c, m), Clarabel.Optimizer)
    @test sp["status"]=="infeasible_certified"
    elastic = PaperRebuild.r3_solve(
        c,
        ()->build_r3_subproblem(c, m; mode = :diagnostic),
        Clarabel.Optimizer,
    )
    @test elastic["status"]=="solver_optimal"
    @test elastic["solver_objective"]>0
    @test elastic["objective_kind"]=="normalized_slack"
    @test elastic["operating_cost"]!=elastic["solver_objective"]
    check = validate_r3_solution(c, elastic)
    @test check.model_pass
    @test !check.physical_pass
    corrupted = deepcopy(elastic)
    corrupted["values"]["elastic_positive"][1] += 0.1
    @test !validate_r3_solution(c, corrupted).model_pass
    too_much = deepcopy(c.data)
    too_much["electric"]["nodes"][2]["P_MW"] .= 100.0
    hard = R2Case(too_much, "synthetic-hard-fixture")
    failed = PaperRebuild.r3_solve(
        hard,
        ()->build_r3_subproblem(hard, m; mode = :diagnostic),
        Clarabel.Optimizer,
    )
    @test failed["status"]=="infeasible_certified"
    @test_throws ArgumentError build_r3_subproblem(c, m; mode = :diagnostic, physical = true)
    @test build_r3_subproblem(c, ones(1, 4); physical = true).class=="nonconvex"
    @test repair_r3_flow(c, m; optimizer = Clarabel.Optimizer, budget_sec = 60.0)["status"]=="unsupported_solver"
    expired = solve_r3_feasibility(
        c;
        optimizer = Clarabel.Optimizer,
        initial_flow = ones(1, 4),
        budget_sec = 1e-12,
    )
    @test expired["status"]=="budget_exhausted"
    @test !validate_r3_solution(c, expired).physical_pass
    run = solve_r3_feasibility(
        c;
        optimizer = nothing,
        convex_optimizer = Clarabel.Optimizer,
        initial_flow = ones(1, 4),
        budget_sec = 60.0,
    )
    @test validate_r3_solution(c, run).physical_pass
    @test run["final_stage"]>0
    @test all(s["stage"]!="direct_repair" for s in run["stages"])
    @test_throws ArgumentError solve_r3_feasibility(c; initial_flow = m, initial_run = "unused")
    no_license = PaperRebuild.r3_solve(
        c,
        ()->build_r3_subproblem(c, ones(1, 4)),
        ()->error("license fixture unavailable"),
    )
    @test no_license["status"]=="not_run_license"
    @test !haskey(no_license, "values")
    failed_init = solve_r3_feasibility(c; optimizer = ()->error("license fixture unavailable"))
    @test failed_init["status"]=="initialization_failed"
    @test failed_init["stages"][1]["status"]=="not_run_license"
    mktempdir() do dir
        saved_failure=save_r3_run(c, failed_init; root = dir, run_id = "failed-init")
        @test !read_r3_run(saved_failure).validation.physical_pass
    end
    @test_throws ErrorException PaperRebuild.r3_solve(
        c,
        ()->build_r3_subproblem(c, ones(1, 4)),
        ()->error("unexpected implementation error"),
    )
    mktempdir() do dir
        path = save_r3_run(c, run; root = dir, run_id = "r3-test")
        restored = read_r3_run(path)
        @test restored.validation.physical_pass
        @test restored.result["initial_flow"]==run["initial_flow"]
        @test_throws Base.IOError save_r3_run(c, run; root = dir, run_id = "r3-test")
        open(io->write(io, "\n# tamper\n"), joinpath(path, "run.toml"), "a")
        @test_throws ArgumentError read_r3_run(path)
    end
end

@testset "R3 input history and mass replay boundaries" begin
    c = load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    two = load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "two-source.toml"))
    reversed_port = repeat(reshape([1.5, 0.5], 2, 1), 1, 4)
    @test_throws ArgumentError build_r3_subproblem(two, reversed_port)
    missing = deepcopy(c.data)
    missing["heat"]["pipes"][1]["flow_history"] = [1.0]
    @test_throws ArgumentError build_r3_subproblem(R2Case(missing, "history-fixture"), ones(1, 4))
    for dt in (0.5, 1.0), flow in ([0.5, 0.5, 1.0, 1.0], [0.75, 1.25, 0.75, 1.25])
        d=deepcopy(c.data)
        d["dt_h"]=dt
        cc=R2Case(d, "time-fixture")
        v=Dict("m_pipe"=>[flow], "tau_S_in"=>[[343.0, 350.0, 360.0, 353.0]])
        pipe=d["heat"]["pipes"][1]
        ref=replay_water_mass(
            v["tau_S_in"][1],
            flow,
            pipe["S_history_K"],
            pipe["flow_history"];
            mass_kg = 1800.0,
            dt_h = dt,
            epsilon_W_mK = 0.2,
        )
        for t in 1:4
            independent=PaperRebuild.r3_mass_replay(cc, v, 1, t, "S")
            @test independent.out≈ref.outlet[t] atol=1e-10
            @test sum(independent.weights)≈1.0 atol=1e-12
        end
    end
    degenerate=deepcopy(c.data)
    degenerate["heat"]["pipes"][1]["flow_min"]=1.0
    degenerate["heat"]["pipes"][1]["flow_max"]=1.0
    cc=R2Case(degenerate, "equal-bounds-fixture")
    @test PaperRebuild.r3_distance(cc, ones(1, 4), ones(1, 4))==0.0
    @test isempty(PaperRebuild.r3_build_repair(cc, ones(1, 4)).variables["flow_deviation"])
end
