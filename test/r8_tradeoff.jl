using Test, JuMP, HiGHS, PaperRebuild, TOML
isdefined(@__MODULE__, :joint_test_case) || include("r7_flow_planning_fixtures.jl")
@testset "R8-T1:T5 objectives, fixed-plan risk and evidence" begin
    c, f=joint_test_case(; limit = 0.4, battery_rule = "per_period_exclusive_v1")
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "mip_rel_gap"=>1e-9,
        "mip_feasibility_tolerance"=>1e-8,
        "primal_feasibility_tolerance"=>1e-8,
    )
    @test PaperRebuild.r8_loss_caps(c)≈[1.2, 1.2]
    @test_throws ErrorException r8_spec(c, f; mode = :unknown)
    @test_throws ErrorException r8_spec(c, f; mode = :penalty, penalty_USD_MWh = -1)
    @test_throws ErrorException r8_spec(c, f; mode = :threshold, limits_MWh = [0.4])
    @test_throws ErrorException r8_spec(c, f; mode = :threshold, topology = :invalid)
    runs=Dict{String,Any}()
    for (mode, limits) in
        ((:economic, [0.4, 0.4]), (:threshold, [0.4, 0.4]), (:penalty, [0.4, 0.4]))
        s=r8_spec(c, f; mode, limits_MWh = limits)
        r=solve_r8_case(c, f, s; optimizer = opt, budget_sec = 60)
        runs[String(mode)]=r
        println(
            mode,
            " primary=",
            r["primary"]["status"],
            " ",
            get(r["primary"], "error", ""),
            " eval=",
            get(get(r, "evaluation", Dict()), "status", "missing"),
            " ",
            get(get(r, "evaluation", Dict()), "error", ""),
        )
        @test r["validation"]["normal_plan_pass"]
        @test r["validation"]["planning_objective_complete"]
        @test r["validation"]["recovery_verified"]
        @test r["validation"]["recovery_objective_complete"]
        @test all(r["validation"]["evaluation"]["event_optimality_pass"])
        @test r["wall_budget_pass"]
        @test isequal(validate_r8_solution(c, f, s, r), r["validation"])
        mktempdir() do dir
            dest=joinpath(dir, "record")
            save_r8_run(c, f, s, r, dest)
            @test read_r8_run(dest).result["run_id"]==r["run_id"]
            @test_throws ErrorException save_r8_run(c, f, s, r, dest)
            open(joinpath(dest, "result.toml"), "a") do io
                write(io, "\n# altered\n")
            end
            @test_throws ErrorException read_r8_run(dest)
        end
    end
    econ, cap, pen=runs["economic"], runs["threshold"], runs["penalty"]
    @test econ["validation"]["primary"]["normal_cost_USD"]≈192.0 atol=1e-5
    @test !econ["validation"]["threshold_pass"]
    @test econ["validation"]["evaluation"]["event_upper_MWh"]≈fill(1.0375, 2) atol=1e-5
    @test cap["validation"]["threshold_pass"]
    @test cap["validation"]["primary"]["normal_cost_USD"]≈193.275 atol=1e-5
    @test pen["validation"]["primary"]["objective_value"]≈593.275 atol=1e-4
    @test pen["validation"]["primary"]["normal_cost_USD"]≈193.275 atol=1e-5
    @test isempty(econ["primary"]["witnesses"])
    @test econ["evaluation"]["objective_kind"]=="sum_event_worst_expected_unserved_energy_MWh"
    @test pen["primary"]["objective_kind"]=="normal_cost_plus_event_unserved_penalty_USD"
    s=r8_spec(c, f; mode = :threshold, limits_MWh = zeros(2))
    bad=solve_r8_case(c, f, s; optimizer = opt, budget_sec = 60)
    @test bad["primary"]["status"]=="infeasible_certified"
    @test !bad["validation"]["normal_plan_pass"]
    @test !haskey(bad, "evaluation")
    r=solve_r8_case(c, f, s; optimizer = opt, budget_sec = 0)
    @test r["primary"]["status"]=="budget_exhausted"
    @test !haskey(r, "evaluation")
    broken=()->error("license missing for test fixture")
    r=solve_r8_case(c, f, s; optimizer = broken, budget_sec = 60)
    @test r["primary"]["status"]=="license_unavailable"
    s=r8_spec(
        c,
        f;
        mode = :threshold,
        topology = :retain_surviving,
        heat_preparation = :no_net_charge,
    )
    r=solve_r8_case(c, f, s; optimizer = opt, budget_sec = 60)
    @test r["validation"]["normal_plan_pass"]
    @test any(x["id"]=="R8-T5-topology" for x in r["primary"]["validation"]["rows"])
    @test any(x["id"]=="R8-T5-no-net-charge" for x in r["primary"]["validation"]["rows"])
    wrong=deepcopy(r)
    wrong["primary"]["solver_objective"]+=1.0
    @test_throws ErrorException validate_r8_solution(c, f, s, wrong)
    wrong=deepcopy(r)
    wrong["evaluation"]["fixed_normal_sha256"]="fake"
    @test_throws ErrorException validate_r8_solution(c, f, s, wrong)
end
