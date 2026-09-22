using Test, PaperRebuild, JuMP, HiGHS, TOML
isdefined(@__MODULE__, :joint_test_case) || include("r7_flow_planning_fixtures.jl")

@testset "R9-RC3 declared-currency planning and recovery penalty" begin
    root=normpath(joinpath(@__DIR__, ".."))
    old, flow=joint_test_case(; limit = 0.4, battery_rule = "per_period_exclusive_v1")
    old_hash=old.sha256
    d=deepcopy(old.normal.data)
    d["schema"]="r7-normal-case-v2"
    d["currency"]="CNY"
    d["units"]["price"]="CNY/MWh"
    d["name"]="synthetic_currency_planning_hand"
    d["electric"]["price_MWh"]=pop!(d["electric"], "price_USD_MWh")
    for g in d["devices"]
        g["cost_P_MWh"]=pop!(g, "cost_P_USD_MWh")
        g["kind"]=="CHP" && (g["startup_cost"]=pop!(g, "startup_cost_USD"))
    end
    c=R7PlanningCase(R7NormalCase(d), old.specification)
    flow["case_sha256"]=c.sha256
    flow["normal_flow"]["case_sha256"]=c.normal.sha256
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    no_usd(x) =
        x isa AbstractDict ? all(!occursin("_USD", string(k))&&no_usd(v) for (k, v) in x) :
        x isa AbstractArray ? all(no_usd, x) : true
    archive=mktempdir(joinpath(root, "tmp"); cleanup = false)
    n=solve_r7_normal_flow(c.normal, flow["normal_flow"]; optimizer = opt, budget_sec = 60)
    @test n["candidate_accepted"] && n["domain_cost_complete"]
    @test n["schema"]=="r7-normal-flow-result-v2" && n["currency"]=="CNY"
    @test n["validation"]["cost"]≈192.0 atol=1e-5
    @test no_usd(n)
    save_r7_normal_flow(c.normal, flow["normal_flow"], n, joinpath(archive, "normal-flow"))
    @test read_r7_normal_flow(joinpath(archive, "normal-flow")).validation["model_pass"]
    for method in (:extensive, :finite_fault_ccg)
        r=solve_r7_planning(c; optimizer = opt, method, budget_sec = 60)
        @test r["validation"]["robust_model_pass"]
        @test r["currency"]=="CNY" && r["schema"]=="r7-planning-result-v2"
        @test r["validation"]["currency"]=="CNY"
        @test r["objective_kind"]=="expected_normal_cost_CNY" && no_usd(r)
        path=joinpath(archive, "planning-"*string(method))
        save_r7_planning(c, r, path)
        @test read_r7_planning(path).validation["robust_model_pass"]
    end
    flows=Dict{String,Any}()
    for pair in PaperRebuild.r7_planning_pairs(c)
        b=PaperRebuild.r7_joint_bounds(flow, pair)
        flows[PaperRebuild.r7_planning_pair_key(pair)]=Dict(
            "m_pipe"=>b["pipe_min"],
            "m_source"=>b["source_min"],
            "m_load"=>b["load_min"],
        )
    end
    linked=r7_linked_planning_spec(c; flows, substeps = 1)
    lr=solve_r7_linked_planning(c, linked; optimizer = opt, method = :extensive, budget_sec = 60)
    @test lr["validation"]["robust_model_pass"]
    @test lr["schema"]=="r7-linked-planning-result-v2" && lr["currency"]=="CNY"
    @test lr["validation"]["cost"]≈193.275 atol=1e-5
    @test no_usd(lr)
    save_r7_linked_planning(c, linked, lr, joinpath(archive, "linked"))
    @test read_r7_linked_planning(joinpath(archive, "linked")).validation["robust_model_pass"]
    jr=solve_r7_flow_planning(c, flow; optimizer = opt, budget_sec = 60)
    @test jr["candidate_accepted"] && jr["domain_cost_complete"]
    @test jr["schema"]=="r7-flow-planning-result-v2" && jr["currency"]=="CNY"
    @test jr["validation"]["cost"]≈193.275 atol=1e-5
    @test no_usd(jr)
    save_r7_flow_planning(c, flow, jr, joinpath(archive, "joint"))
    @test read_r7_flow_planning(joinpath(archive, "joint")).validation["robust_model_pass"]

    for energy in (false, true), mode in (:economic, :threshold, :penalty)
        s=energy ?
          r8_energy_spec(
            c;
            pipe_capacity_MW = [1.05],
            mode,
            loss_rule = :lossless,
            penalty_MWh = 10000.0,
        ) : r8_spec(c, flow; mode, penalty_MWh = 10000.0)
        @test s["currency"]=="CNY" && s["penalty_MWh"]==10000.0 && no_usd(s)
        r=energy ? solve_r8_energy_case(c, s; optimizer = opt, budget_sec = 60) :
          solve_r8_case(c, flow, s; optimizer = opt, budget_sec = 60)
        @test r["validation"]["primary_model_pass"] && r["validation"]["recovery_verified"]
        @test r["currency"]=="CNY" && endswith(r["schema"], "-v2")
        @test no_usd(r)
        p=r["primary"]
        cost=p["validation"]["normal_cost"]
        @test p["validation"]["currency"]=="CNY"
        expected=mode==:penalty ? cost+10000.0sum(p["eta_MWh"]) : cost
        @test p["solver_objective"]≈expected atol=1e-4
        @test p["objective_kind"]==(
            mode==:penalty ? "normal_cost_plus_event_unserved_penalty_CNY" :
            "expected_normal_cost_CNY"
        )
        @test r["evaluation"]["objective_kind"]=="sum_event_worst_expected_unserved_energy_MWh"
        @test r["evaluation"]["validation"]["objective_complete"]
        path=joinpath(archive, "r8-"*string(energy)*"-"*string(mode))
        if energy
            save_r8_energy_run(c, s, r, path)
            @test read_r8_energy_run(path).validation["primary_model_pass"]
        else
            save_r8_run(c, flow, s, r, path)
            @test read_r8_run(path).validation["primary_model_pass"]
        end
        bad=deepcopy(r)
        bad["currency"]="USD"
        @test_throws ErrorException (
            energy ? validate_r8_energy_solution(c, s, bad) : validate_r8_solution(c, flow, s, bad)
        )
        # 显式元数据也不能让下层阶段的错误币种通过。
        bad=deepcopy(r)
        bad["primary"]["currency"]="USD"
        @test_throws ErrorException (
            energy ? validate_r8_energy_solution(c, s, bad) : validate_r8_solution(c, flow, s, bad)
        )
    end
    @test_throws ErrorException r8_spec(c, flow; mode = :penalty)
    @test_throws ErrorException r8_spec(c, flow; mode = :penalty, penalty_USD_MWh = 500.0)
    @test_throws ErrorException r8_energy_spec(
        c;
        pipe_capacity_MW = [1.05],
        penalty_USD_MWh = 500.0,
    )
    @test_throws ErrorException r8_energy_spec(c; pipe_capacity_MW = [1.05], penalty_MWh = 0.0)
    @test_throws ErrorException r8_spec(c, flow; mode = :penalty, penalty_MWh = Inf)
    oldflow=deepcopy(flow)
    oldflow["case_sha256"]=old.sha256
    oldflow["normal_flow"]["case_sha256"]=old.normal.sha256
    @test r8_spec(old, oldflow; mode = :penalty)["penalty_USD_MWh"]==500.0
    @test_throws ErrorException r8_spec(old, oldflow; mode = :penalty, penalty_MWh = 500.0)
    @test old.sha256==old_hash
    println("Currency planning evidence preserved: ", relpath(archive, root))
end
