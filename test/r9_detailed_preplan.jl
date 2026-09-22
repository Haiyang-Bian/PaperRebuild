using Test, PaperRebuild, JuMP, HiGHS, TOML

function detailed_preplan_fixture(; loss_limit = 0.4, conductance = 0.0)
    root = dirname(@__DIR__)
    d = TOML.parsefile(joinpath(root, "configs/r7/normal-reserve-hand.toml"))
    d["heat"]["pipes"][1]["UA_S_W_K"] = conductance
    rules = TOML.parsefile(joinpath(root, "configs/r7/planning-reserve-hand.toml"))
    foreach(e -> e["loss_limit_MWh"] = loss_limit, rules["events"])
    c = R7PlanningCase(R7NormalCase(d), rules)
    flows = Dict{String,Any}()
    for p in PaperRebuild.r7_planning_pairs(c)
        T = rules["events"][p.event]["periods"]
        f = any(==(1), p.fault) ? 0.0 : 5.0
        flows[PaperRebuild.r7_planning_pair_key(p)] = Dict(
            "m_pipe" => fill(f, 1, T),
            "m_source" => vcat(fill(f, 1, T), zeros(1, T)),
            "m_load" => vcat(zeros(1, T), fill(f, 1, T)),
        )
    end
    c, flows
end

@testset "R9 detailed preplan and inherited thermal compatibility" begin
    opt = optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads" => 1,
        "primal_feasibility_tolerance" => 1e-9,
        "dual_feasibility_tolerance" => 1e-9,
        "mip_feasibility_tolerance" => 1e-9,
        "mip_rel_gap" => 1e-9,
    )
    c, flows = detailed_preplan_fixture()
    pairs = PaperRebuild.r7_planning_pairs(c)
    specs = Dict(
        mode => r9_detailed_preplan_spec(c; mode, pairs, flows, penalty_MWh = 500.0) for
        mode in (:economic, :penalty, :threshold)
    )
    @testset "R9-DP1 explicit linked domain and unchanged normal" begin
        for (mode, s) in specs
            b = build_r9_detailed_preplan(c, s)
            @test b.carrier.normal.sha256 == c.normal.sha256
            @test isequal(b.carrier.normal.data, c.normal.data)
            @test length(b.recovery) == (mode == :economic ? 0 : length(pairs))
            @test all(haskey(w, :thermal_variables) && haskey(w, :prefix) for w in b.recovery)
            @test b.model_class == "MILP"
            @test all(F in (VariableRef, AffExpr) for (F, _) in list_of_constraint_types(b.model))
        end
        @test_throws ErrorException r9_detailed_preplan_spec(
            c;
            mode = :penalty,
            pairs,
            flows,
            penalty_MWh = 500.0,
            substeps = true,
        )
        @test_throws ErrorException r9_detailed_preplan_spec(
            c;
            mode = :penalty,
            pairs,
            flows = Dict(),
            penalty_MWh = 500.0,
        )
        @test_throws ErrorException build_r9_detailed_preplan(
            c,
            specs[:penalty];
            deadline = time() - 1,
        )
        broken = deepcopy(specs[:penalty])
        broken["thermal_rule"] = "aggregate"
        @test_throws ErrorException build_r9_detailed_preplan(c, broken)
        @test specs[:penalty]["base_spec"]["version"] == "r9_prescribed_preplan_v1"
    end
    @testset "R9-DP2 one epigraph per event not per fault" begin
        b = build_r9_detailed_preplan(c, specs[:penalty]; optimizer = opt)
        # 零流故障失去热供应，统一固定足够大的可实现失供，以隔离max和sum语义。
        for w in b.recovery
            @constraint(b.model, w.loss == (only(w.pair.fault) == 0 ? 0.8 : 0.9))
        end
        @objective(b.model, Min, sum(b.ζ))
        set_silent(b.model)
        optimize!(b.model)
        @test termination_status(b.model) == MOI.OPTIMAL
        @test objective_value(b.model) ≈ 1.8 atol = 1e-7
        @test sum(value(w.loss) for w in b.recovery) ≈ 3.4 atol = 1e-7
    end
    runs = Dict(
        mode => solve_r9_detailed_preplan(c, s; optimizer = opt, budget_sec = 60) for
        (mode, s) in specs
    )
    @testset "R9-DP3 independent state and objective evidence" begin
        @test runs[:economic]["candidate_accepted"]
        @test runs[:economic]["validation"]["normal_cost"] ≈ 192.0 atol = 1e-6
        @test !runs[:economic]["validation"]["detailed_disaster_heat_verified"]
        for mode in (:penalty, :threshold)
            r = runs[mode]
            @test r["candidate_accepted"]
            @test r["conditional_objective_complete"]
            @test r["validation"]["detailed_disaster_heat_verified"]
            @test r["validation"]["whole_fault_threshold_witness_pass"]
            @test !r["independent_recovery_performed"]
            @test !haskey(r["master"]["normal"], "lower_bound_USD")
            @test r["master"]["normal"]["solver_objective_USD"] ≈ r["validation"]["normal_cost"] atol =
                1e-8
            w = first(r["master"]["witnesses"])
            ev = PaperRebuild.r7_linked_event(
                PaperRebuild.r9_detailed_preplan_check(c, specs[mode]),
                specs[mode]["linked_spec"],
                r["master"]["normal"],
                pairs[1],
            )
            @test r9_handoff_temperature_check(ev.case, ev.spec)["necessary_condition_pass"]
            fake = deepcopy(r)
            fake["master"]["witnesses"][1]["normal_inlets"]["1/S/1"][1] += 1.0
            @test !validate_r9_detailed_preplan(c, specs[mode], fake)["model_pass"]
            fake = deepcopy(r)
            fake["solver_objective"] += 1.0
            @test !validate_r9_detailed_preplan(c, specs[mode], fake)["objective_pass"]
            fake = deepcopy(r)
            fake["master"]["witnesses"][1]["lower_bound_MWh"] = 0.0
            @test_throws ErrorException validate_r9_detailed_preplan(c, specs[mode], fake)
        end
        zero = solve_r9_detailed_preplan(c, specs[:penalty]; optimizer = opt, budget_sec = 0)
        @test zero["status"] == "budget_exhausted" && !haskey(zero, "master")
        missing = solve_r9_detailed_preplan(
            c,
            specs[:penalty];
            optimizer = () -> error("license unavailable fixture"),
            budget_sec = 60,
        )
        @test missing["status"] == "license_unavailable" && !missing["candidate_accepted"]
        impossible = r9_detailed_preplan_spec(
            c;
            mode = :threshold,
            pairs,
            flows,
            penalty_MWh = 500.0,
            limits_MWh = [0.0, 0.0],
        )
        failed = solve_r9_detailed_preplan(c, impossible; optimizer = opt, budget_sec = 60)
        @test failed["status"] == "infeasible_certified" && !failed["candidate_accepted"]
        out = mktempdir()
        dir = save_r9_detailed_preplan(c, specs[:penalty], runs[:penalty], joinpath(out, "saved"))
        @test read_r9_detailed_preplan(dir).validation["model_pass"]
        @test_throws ErrorException save_r9_detailed_preplan(
            c,
            specs[:penalty],
            runs[:penalty],
            dir,
        )
        relocated = joinpath(out, "relocated")
        cp(dir, relocated)
        m = Module(gensym(:R9DetailedReplay))
        Base.include(m, joinpath(relocated, "code/replay.jl"))
        x = Base.invokelatest(getfield, m, :x)
        @test isequal(x.result, runs[:penalty])
        open(io -> write(io, "# tampered\n"), joinpath(relocated, "result.toml"), "a")
        @test_throws ErrorException read_r9_detailed_preplan(relocated)
        println("Detailed preplan test evidence: ", out)
    end
    @testset "R9-DH1 necessary interval and spatial checks" begin
        s = specs[:penalty]["linked_spec"]
        carrier = PaperRebuild.r9_detailed_preplan_check(c, specs[:penalty])
        for p in pairs
            ev = PaperRebuild.r7_linked_template(carrier, s, p)
            before = PaperRebuild.r7_digest(Dict("case" => ev.case.data, "spec" => ev.spec))
            q = r9_handoff_temperature_check(ev.case, ev.spec)
            @test q["necessary_condition_pass"]
            @test !q["sufficiency_claimed"] && !q["optimization_performed"]
            @test before == PaperRebuild.r7_digest(Dict("case" => ev.case.data, "spec" => ev.spec))
            @test_throws ErrorException r9_handoff_temperature_check(
                ev.case,
                ev.spec;
                deadline = time() - 1,
            )
            @test_throws ErrorException r9_handoff_temperature_check(
                ev.case,
                ev.spec;
                deadline = NaN,
            )
        end
        cold, fs = detailed_preplan_fixture(; conductance = 10000.0)
        cold_spec = r9_detailed_preplan_spec(
            cold;
            mode = :penalty,
            pairs = PaperRebuild.r7_planning_pairs(cold),
            flows = fs,
            penalty_MWh = 500.0,
        )
        ev = PaperRebuild.r7_linked_template(
            PaperRebuild.r9_detailed_preplan_check(cold, cold_spec),
            cold_spec["linked_spec"],
            pairs[1],
        )
        q = r9_handoff_temperature_check(ev.case, ev.spec)
        @test !q["necessary_condition_pass"]
        @test any(r["conflict"] && r["relation"] == "R7-T4-spatial" for r in q["rows"])
        @test q["maximum_unavoidable_violation_K"] > 1e-4
    end
end
