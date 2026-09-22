using Test, JuMP, HiGHS, PaperRebuild, TOML
isdefined(@__MODULE__, :joint_test_case) || include("r7_flow_planning_fixtures.jl")

@testset "R8-E1:E3 steady energy balance and independent accounting" begin
    c, _=joint_test_case(; limit = 0.4, battery_rule = "per_period_exclusive_v1")
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "mip_rel_gap"=>1e-9,
        "mip_feasibility_tolerance"=>1e-8,
        "primal_feasibility_tolerance"=>1e-8,
    )
    @test_throws ErrorException r8_energy_spec(c; pipe_capacity_MW = [Inf])
    @test_throws ErrorException r8_energy_spec(c; pipe_capacity_MW = [])
    @test_throws ErrorException r8_energy_spec(c; pipe_capacity_MW = [1.0], mode = :unknown)
    @test_throws ErrorException r8_energy_spec(c; pipe_capacity_MW = [1.0], loss_rule = :unknown)
    runs=Dict{String,Any}()
    for mode in (:economic, :threshold, :penalty)
        s=r8_energy_spec(c; pipe_capacity_MW = [1.05], mode, loss_rule = :lossless)
        b=build_r8_energy_model(c, s)
        @test b.model_class=="MILP"
        @test all(F in (VariableRef, AffExpr) for (F, _) in list_of_constraint_types(b.model))
        @test isempty(
            intersect(Set(keys(b.normal_variables)), Set(PaperRebuild.R8_ENERGY_NORMAL_REMOVED)),
        )
        @test all(
            isempty(
                intersect(Set(keys(w.variables)), Set(PaperRebuild.R8_ENERGY_RECOVERY_REMOVED)),
            ) for w in b.recovery
        )
        r=solve_r8_energy_case(c, s; optimizer = opt, budget_sec = 60)
        println(
            mode,
            " primary=",
            r["primary"]["status"],
            " ",
            get(r["primary"], "error", ""),
            " evaluation=",
            get(get(r, "evaluation", Dict()), "status", "missing"),
            " ",
            get(get(r, "evaluation", Dict()), "error", ""),
        )
        @test r["validation"]["primary_model_pass"]
        @test r["validation"]["recovery_verified"]
        @test r["primary"]["validation"]["objective_complete"]
        @test r["evaluation"]["validation"]["objective_complete"]
        @test r["wall_budget_pass"]
        @test !r["validation"]["dynamic_heat_verified"]
        nq=r["primary"]["validation"]["normal_check"]
        @test nq["shared"]["shared_block_pass"] && !nq["shared"]["model_pass"]
        @test !nq["shared"]["pipe_reference_pass"]
        @test validate_r8_energy_solution(c, s, TOML.parse(PaperRebuild.r7_text(r)))==r["validation"]
        runs[String(mode)]=r
        mktempdir() do dir
            dest=joinpath(dir, "energy")
            save_r8_energy_run(c, s, r, dest)
            @test read_r8_energy_run(dest).result["run_id"]==r["run_id"]
            @test_throws ErrorException save_r8_energy_run(c, s, r, dest)
            open(joinpath(dest, "result.toml"), "a") do io
                write(io, "\n# changed\n")
            end
            @test_throws ErrorException read_r8_energy_run(dest)
        end
        bad=deepcopy(r)
        bad["primary"]["solver_objective"]+=1
        @test_throws ErrorException validate_r8_energy_solution(c, s, bad)
        bad=deepcopy(r)
        bad["evaluation"]["fixed_normal_sha256"]="wrong"
        @test_throws ErrorException validate_r8_energy_solution(c, s, bad)
    end
    @test runs["economic"]["primary"]["normal"]["normal_cost_USD"]≈192.0 atol=1e-5
    @test runs["economic"]["evaluation"]["validation"]["event_upper_MWh"]≈[1.0375, 1.0375] atol=1e-5
    @test runs["threshold"]["primary"]["normal"]["normal_cost_USD"]≈193.275 atol=1e-5
    @test runs["penalty"]["primary"]["solver_objective"]≈593.275 atol=1e-4
    for (cap, limits) in ((0.3, [0.4, 0.4]), (1.05, [0.0, 0.0]))
        s=r8_energy_spec(c; pipe_capacity_MW = [cap], limits_MWh = limits, loss_rule = :lossless)
        r=solve_r8_energy_case(c, s; optimizer = opt, budget_sec = 60)
        @test r["primary"]["status"]=="infeasible_certified"
        @test !haskey(r, "evaluation")
    end
    s=r8_energy_spec(c; pipe_capacity_MW = [1.05])
    r=solve_r8_energy_case(c, s; optimizer = opt, budget_sec = 0)
    @test r["primary"]["status"]=="budget_exhausted"
    r=solve_r8_energy_case(c, s; optimizer = ()->error("license unavailable test"), budget_sec = 60)
    @test r["primary"]["status"]=="license_unavailable"
    d=deepcopy(c.normal.data)
    for p in d["heat"]["pipes"]
        p["UA_S_W_K"]=10.0
        p["UA_R_W_K"]=10.0
    end
    lossy=R7PlanningCase(R7NormalCase(d), c.specification)
    @test_throws ErrorException r8_energy_spec(
        lossy;
        pipe_capacity_MW = [1.05],
        loss_rule = :lossless,
    )
    s=r8_energy_spec(lossy; pipe_capacity_MW = [1.05], mode = :economic)
    r=solve_r8_energy_case(lossy, s; optimizer = opt, budget_sec = 60)
    @test r["validation"]["primary_model_pass"]
    heatloss=(10*(342.15-293.15)+10*(323.10238095238094-293.15))/1e6
    @test r["primary"]["normal"]["normal_cost_USD"]≈192-4*80*heatloss atol=1e-5
    bad=deepcopy(r["primary"]["normal"])
    vals=PaperRebuild.r7_unpack(bad["values"], "P_PCC")
    vals[1]+=0.1
    bad["values"]["P_PCC"]=PaperRebuild.r7_pack(vals)
    @test !PaperRebuild.r8_energy_normal_check(lossy, s, bad)["model_pass"]
end
