using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML

@testset "R7 compatible ports and isolated heat bound" begin
    root=normpath(joinpath(@__DIR__, ".."))
    old=load_r7_recovery_case(joinpath(root, "configs/r7/recovery-hand.toml"))
    c=with_r7_port_temperature_bounds(old)
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    @testset "R7-C1 versioned interval projection" begin
        @test !haskey(old.data, "recovery_model")
        @test c.sha256!=old.sha256
        @test with_r7_port_temperature_bounds(c).sha256==c.sha256
        d=deepcopy(c.data)
        delete!(d, "recovery_model")
        @test R7RecoveryCase(d).sha256==old.sha256
        bad=deepcopy(c.data)
        bad["recovery_model"]="implicit_change"
        @test_throws ErrorException R7RecoveryCase(bad)
        b=r7_port_temperature_bounds(c)
        @test b.source_min[1]==10
        @test b.source_max[1]==50
        @test b.load_min[2]==10
        @test b.load_max[2]==50
        model=build_r7_recovery(c, [1])
        @test haskey(model.constraints, "R7-C1-source")
        @test !haskey(build_r7_recovery(old, [1]).constraints, "R7-C1-source")
        @test all(F in (VariableRef, AffExpr) for (F, _) in list_of_constraint_types(model.model))
    end
    legacy=solve_r7_recovery(old, [1]; optimizer = opt)
    severed=solve_r7_recovery(c, [1]; optimizer = opt)
    healthy=solve_r7_recovery(c, [0]; optimizer = opt)
    @testset "R7-C2 bound, counterexamples and independent values" begin
        proof=r7_island_heat_bound(c, [1])
        @test proof["applicable"]
        @test proof["minimum_heat_loss_MWh"]≈0.4
        @test !proof["attainability_verified"]
        @test !r7_island_heat_bound(old, [1])["applicable"]
        @test !r7_island_heat_bound(c, [0])["applicable"]
        @test_throws Exception r7_island_heat_bound(c, [2])
        @test legacy["validation"]["loss_MWh"]≈17/30 atol=1e-7
        @test severed["candidate_accepted"]
        @test severed["loss_optimization_complete"]
        @test severed["validation"]["loss_MWh"]≈0.8 atol=1e-7
        @test healthy["candidate_accepted"]
        @test healthy["validation"]["loss_MWh"]≈0 atol=1e-7
        @test !severed["validation"]["detailed_heat_validated"]
        fake=deepcopy(legacy)
        fake["version"]=PaperRebuild.r7_recovery_version(c)
        fake["case_sha256"]=c.sha256
        q=validate_r7_recovery(c, fake)
        @test !q["model_pass"]
        @test any(startswith(row["id"], "R7-C1")&&!row["pass"] for row in q["rows"])
        @test_throws Exception validate_r7_recovery(old, severed)
        # 即使只有微小正负荷，也不能把它按A1容差裁成零来制造解析证书。
        d=deepcopy(c.data)
        d["electric"]["load_MW"][1][1]=1e-10
        @test !r7_island_heat_bound(R7RecoveryCase(d), [1])["applicable"]
        d=deepcopy(c.data)
        battery=deepcopy(d["devices"][2])
        battery["id"]="source_buffer"
        battery["electric_node"]=1
        push!(d["devices"], battery)
        @test !r7_island_heat_bound(R7RecoveryCase(d), [1])["applicable"]
        d=deepcopy(c.data)
        d["heat"]["shed_fraction_max"][2]=0.5
        hard=R7RecoveryCase(d)
        @test r7_island_heat_bound(hard, [1])["hard_shedding_conflict"]
        @test solve_r7_recovery(hard, [1]; optimizer = opt)["status"]=="infeasible_certified"
        # 实际LP行提取必须带入新增必要条件；不能只改MILP然后继续复用旧对偶。
        dual=build_r7_recourse_dual(r7_recovery_lp(c, [0]), [1]; optimizer = opt)
        set_silent(dual.model)
        optimize!(dual.model)
        @test objective_value(dual.model)≈0.8 atol=1e-7
        @test validate_r7_dual(dual.lp, [1], value.(dual.lambda))["dual_feasible"]
        spec=r7_thermal_spec(
            c,
            severed;
            profiles = :uniform,
            profile_origin = "explicit hand initial state",
            substeps = 4,
        )
        heat=solve_r7_thermal_reconstruction(c, severed, spec; optimizer = opt, budget_sec = 60)
        @test heat["validation"]["same_dispatch_pass"]
        @test heat["validation"]["heat_unserved_MWh"]≈0.4 atol=1e-7
        lp=solve_r7_recovery(c, [1]; optimizer = Clarabel.Optimizer, fixed_z = [0])
        @test lp["candidate_accepted"]
        @test lp["validation"]["loss_MWh"]≈0.8 atol=1e-6
        @test solve_r7_recovery(c, [1]; optimizer = opt, budget_sec = 0)["status"]=="budget_exhausted"
        @test solve_r7_recovery(c, [1]; optimizer = ()->error("license unavailable fixture"))["status"]=="license_unavailable"
        mktempdir() do dir
            dst=joinpath(dir, "recovery")
            save_r7_recovery(c, severed, dst)
            @test read_r7_recovery(dst).validation["model_pass"]
            @test_throws Exception save_r7_recovery(c, severed, dst)
            open(joinpath(dst, "case.toml"), "a") do io
                write(io, "\n# tamper\n")
            end
            @test_throws Exception read_r7_recovery(dst)
        end
    end
    @testset "R7-C3 planning domain and common event propagation" begin
        n=load_r7_normal_case(joinpath(root, "configs/r7/normal-reserve-hand.toml"))
        oldspec=TOML.parsefile(joinpath(root, "configs/r7/planning-reserve-hand.toml"))
        spec=deepcopy(oldspec)
        spec["recovery_model"]="r7_recovery_port_checked_v1"
        strict=R7PlanningCase(n, spec)
        @test PaperRebuild.r7_recovery_version(PaperRebuild.r7_event_template(strict, 1))=="r7_recovery_port_checked_v1"
        @test PaperRebuild.r7_recovery_version(
            PaperRebuild.r7_event_template(R7PlanningCase(n, oldspec), 1),
        )=="r7_recovery_checked_v1"
        for method in (:extensive, :finite_fault_ccg)
            r=solve_r7_planning(strict; optimizer = opt, method, budget_sec = 60)
            @test r["status"]=="infeasible_certified"
            @test !r["candidate_accepted"]
        end
        spec=deepcopy(spec)
        foreach(e->e["loss_limit_MWh"]=0.4, spec["events"])
        relaxed=R7PlanningCase(n, spec)
        for method in (:extensive, :finite_fault_ccg)
            r=solve_r7_planning(relaxed; optimizer = opt, method, budget_sec = 60)
            @test r["candidate_accepted"]
            @test r["conditional_cost_complete"]
            @test r["validation"]["cost_USD"]≈193.275 atol=1e-6
            nr=r["iterations"][r["validation"]["candidate_iteration"]]["master"]["normal"]
            e=PaperRebuild.r7_planning_event(relaxed, nr, 1)
            @test e.evidence["event_case_sha256"]==e.case.sha256
            @test e.evidence["recovery_model"]=="r7_recovery_port_checked_v1"
            @test r7_island_heat_bound(e.case, [1])["minimum_heat_loss_MWh"]≈0.4
        end
    end
end
