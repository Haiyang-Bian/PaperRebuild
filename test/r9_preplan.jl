using Test, PaperRebuild, JuMP, HiGHS, TOML, SHA

@testset "R9 prescribed-flow preplanning" begin
    root=dirname(@__DIR__)
    c=load_r7_planning_case(
        joinpath(root, "configs/r7/normal-reserve-hand.toml"),
        joinpath(root, "configs/r7/planning-reserve-hand.toml"),
    )
    pairs=PaperRebuild.r7_planning_pairs(c)
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    specs=Dict(
        mode=>r9_preplan_spec(c; mode, pairs, penalty_MWh = 500.0) for
        mode in (:economic, :penalty, :threshold)
    )
    @testset "R9-RP1 unchanged normal and declared selected faults" begin
        original=deepcopy(c)
        for (mode, s) in specs
            b=build_r9_preplan(c, s)
            @test b.carrier.normal.sha256==c.normal.sha256
            @test isequal(b.carrier.normal.data, c.normal.data)
            @test length(b.recovery)==(mode==:economic ? 0 : 4)
            @test b.model_class=="MILP"
            @test all(F in (VariableRef, AffExpr) for (F, _) in list_of_constraint_types(b.model))
        end
        @test isequal(original.specification, c.specification)
        @test original.sha256==c.sha256
        @test_throws ErrorException r9_preplan_spec(c; mode = :typo, pairs, penalty_MWh = 500)
        @test_throws ErrorException r9_preplan_spec(
            c;
            mode = :penalty,
            pairs = [],
            penalty_MWh = 500,
        )
        @test_throws ErrorException r9_preplan_spec(
            c;
            mode = :penalty,
            pairs = [pairs[1]],
            penalty_MWh = 500,
        )
        @test_throws ErrorException r9_preplan_spec(
            c;
            mode = :penalty,
            pairs = vcat(pairs, [pairs[1]]),
            penalty_MWh = 500,
        )
        @test_throws ErrorException r9_preplan_spec(c; mode = :penalty, pairs, penalty_MWh = -1)
        @test_throws ErrorException r9_preplan_spec(c; mode = :penalty, pairs, penalty_MWh = Inf)
        wrong=deepcopy(specs[:penalty])
        wrong["currency"]="CNY"
        @test_throws ErrorException build_r9_preplan(c, wrong)
    end
    @testset "R9-RP2 max over faults not sum and zero-price degeneration" begin
        b=build_r9_preplan(c, specs[:penalty]; optimizer = opt)
        for w in b.recovery
            @constraint(b.model, w.loss==(only(w.pair.fault)==0 ? 0.2 : 0.3))
        end
        @objective(b.model, Min, sum(b.ζ))
        set_silent(b.model)
        optimize!(b.model)
        @test termination_status(b.model)==MOI.OPTIMAL
        @test objective_value(b.model)≈0.6 atol=1e-7
        @test sum(value(w.loss) for w in b.recovery)≈1.0 atol=1e-7
    end
    runs=Dict(mode=>solve_r9_preplan(c, s; optimizer = opt, budget_sec = 60) for (mode, s) in specs)
    @testset "R9-RP3 analytical reserve cost and independent handoff" begin
        a=runs[:economic]
        @test a["candidate_accepted"]
        @test a["validation"]["normal_cost"]≈192.0 atol=1e-6
        @test !a["validation"]["selected_threshold_witness_pass"]
        for mode in (:penalty, :threshold)
            r=runs[mode]
            @test r["candidate_accepted"]
            @test r["conditional_objective_complete"]
            @test r["validation"]["normal_cost"]≈193.275 atol=1e-6
            @test r["validation"]["whole_fault_threshold_witness_pass"]
            @test !r["independent_recovery_performed"]
            n=r["master"]["normal"]
            @test !haskey(n, "lower_bound_USD")
            @test n["solver_objective_USD"]≈r["validation"]["normal_cost"] atol=1e-9
            ev=PaperRebuild.r7_planning_event(c, n, 1)
            rec=solve_r7_recovery(ev.case, [1]; optimizer = opt, budget_sec = 60)
            @test rec["candidate_accepted"]
            @test rec["validation"]["loss_MWh"]≈0.0 atol=1e-7
            @test ev.evidence["parent_result_sha256"]==PaperRebuild.r7_digest(n)
        end
        s=r9_preplan_spec(c; mode = :penalty, pairs, penalty_MWh = 0)
        zero=solve_r9_preplan(c, s; optimizer = opt, budget_sec = 60)
        @test zero["candidate_accepted"]
        @test zero["validation"]["normal_cost"]≈192.0 atol=1e-6
        @test zero["validation"]["penalty_cost"]==0.0
        @test zero["solver_objective"]≈runs[:economic]["solver_objective"] atol=1e-6
        # 正罚值但边际代价过高时，罚费可大于零，正常子记录仍只保存运行成本。
        soft=r9_preplan_spec(c; mode = :penalty, pairs, penalty_MWh = 0.01)
        sr=solve_r9_preplan(c, soft; optimizer = opt, budget_sec = 60)
        @test sr["candidate_accepted"]
        @test sr["validation"]["penalty_cost"]>0
        @test sr["solver_objective"]>sr["master"]["normal"]["solver_objective_USD"]
        subset=r9_preplan_spec(c; mode = :threshold, pairs = pairs[[2, 4]], penalty_MWh = 500)
        sub=solve_r9_preplan(c, subset; optimizer = opt, budget_sec = 60)
        @test sub["candidate_accepted"]
        @test sub["validation"]["selected_threshold_witness_pass"]
        @test !sub["validation"]["subset_covers_whole_faults"]
        @test !sub["validation"]["whole_fault_threshold_witness_pass"]
    end
    @testset "R9-RP3 impossible capacity and failure states" begin
        old=load_r7_planning_case(
            joinpath(root, "configs/r7/normal-hand.toml"),
            joinpath(root, "configs/r7/planning-hand.toml"),
        )
        s=r9_preplan_spec(
            old;
            mode = :threshold,
            pairs = PaperRebuild.r7_planning_pairs(old),
            penalty_MWh = 500,
        )
        r=solve_r9_preplan(old, s; optimizer = opt, budget_sec = 60)
        @test r["status"]=="infeasible_certified"
        @test !r["candidate_accepted"]
        zero=solve_r9_preplan(c, specs[:penalty]; optimizer = opt, budget_sec = 0)
        @test zero["status"]=="budget_exhausted"
        @test !haskey(zero, "master")
        expired=solve_r9_preplan(
            c,
            specs[:penalty];
            optimizer = opt,
            budget_sec = 60,
            deadline = time()-1,
        )
        @test expired["status"]=="budget_exhausted"
        missing=solve_r9_preplan(
            c,
            specs[:penalty];
            optimizer = ()->error("license unavailable fixture"),
            budget_sec = 60,
        )
        @test missing["status"]=="license_unavailable"
        @test !missing["candidate_accepted"]
        @test_throws ErrorException solve_r9_preplan(
            c,
            specs[:penalty];
            optimizer = opt,
            budget_sec = 601,
        )
        fake=deepcopy(runs[:penalty])
        fake["master"]["normal"]["lower_bound_USD"]=0.0
        @test_throws ErrorException validate_r9_preplan(c, specs[:penalty], fake)
        fake=deepcopy(runs[:penalty])
        fake["solver_objective"]+=1.0
        @test !validate_r9_preplan(c, specs[:penalty], fake)["objective_pass"]
        fake=deepcopy(runs[:penalty])
        pop!(fake["master"]["witnesses"])
        @test_throws ErrorException validate_r9_preplan(c, specs[:penalty], fake)
        fake=deepcopy(runs[:penalty])
        fake["master"]["normal"]["case_sha256"]="changed"
        @test_throws ErrorException validate_r9_preplan(c, specs[:penalty], fake)
    end
    @testset "R9-RP1 CNY and critical-only service retain separate ledgers" begin
        d=deepcopy(c.normal.data)
        d["schema"]="r7-normal-case-v2"
        d["currency"]="CNY"
        d["units"]["price"]="CNY/MWh"
        d["electric"]["price_MWh"]=pop!(d["electric"], "price_USD_MWh")
        for g in d["devices"]
            g["cost_P_MWh"]=pop!(g, "cost_P_USD_MWh")
            g["kind"]=="CHP" && (g["startup_cost"]=pop!(g, "startup_cost_USD"))
        end
        cn=with_r7_critical_load(
            R7NormalCase(d),
            d["electric"]["load_MW"];
            provenance = "Synthetic currency/service fixture, all electric demand critical",
        )
        cc=R7PlanningCase(cn, c.specification)
        ss=r9_preplan_spec(cc; mode = :penalty, pairs, penalty_MWh = 500.0)
        rr=solve_r9_preplan(cc, ss; optimizer = opt, budget_sec = 60)
        @test rr["candidate_accepted"]
        @test rr["currency"]=="CNY"
        @test ss["service_objective"]=="critical_electric_v1"
        @test rr["validation"]["normal_cost"]≈193.275 atol=1e-6
        @test rr["master"]["normal"]["schema"]=="r7-normal-result-v2"
        @test !haskey(rr["master"]["normal"], "solver_objective_USD")
        @test all(
            haskey(v["check"], "loss_ordinary_electric_MWh") for
            v in rr["validation"]["master_check"]["witness_checks"]
        )
    end
    @testset "R9 preplanning immutable values and frozen replay" begin
        dir=mktempdir()
        save_r9_preplan(c, specs[:penalty], runs[:penalty], joinpath(dir, "run"))
        @test read_r9_preplan(joinpath(dir, "run")).validation["model_pass"]
        @test_throws ErrorException save_r9_preplan(
            c,
            specs[:penalty],
            runs[:penalty],
            joinpath(dir, "run"),
        )
        dest=joinpath(dir, "relocated")
        cp(joinpath(dir, "run"), dest)
        m=Module(gensym(:ReplayR9Preplan))
        Base.include(m, joinpath(dest, "code/replay.jl"))
        x=Base.invokelatest(getfield, m, :x)
        @test x.validation["model_pass"]
        @test isequal(x.result, runs[:penalty])
        open(io->write(io, "# tamper\n"), joinpath(dest, "result.toml"), "a")
        @test_throws ErrorException read_r9_preplan(dest)
        println("R9 preplan test evidence: ", dir)
    end
end
