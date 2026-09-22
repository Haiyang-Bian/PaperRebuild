using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA

function battery_boundary_model(rule; optimizer, mode = nothing)
    m=Model(optimizer)
    set_silent(m)
    set_time_limit_sec(m, 60)
    @variable(m, P_ch[1:1, 1:1, 1:1]>=0)
    @variable(m, P_dis[1:1, 1:1, 1:1]>=0)
    @variable(m, 0<=E_end<=1)
    d=Dict(
        "battery_rule"=>rule,
        "periods"=>1,
        "probabilities"=>[1.0],
        "devices"=>[Dict("id"=>"BES", "kind"=>"BES", "P_max_MW"=>1.0)],
    )
    v=Dict{String,Any}("P_ch"=>P_ch, "P_dis"=>P_dis)
    rows=Dict{String,Vector{Any}}()
    PaperRebuild.r7_add_battery_domain!(m, d, v, rows; fixed_modes = mode)
    @constraint(m, P_ch[1]+P_dis[1]<=1)
    @constraint(m, P_ch[1]-P_dis[1]==0.2)
    @constraint(m, E_end==1+0.8P_ch[1]-P_dis[1]/0.8)
    @constraint(m, E_end==1)
    @objective(m, Min, 0)
    (; model = m, variables = v)
end

function battery_transport_fixture(rule)
    p=joinpath(@__DIR__, "../results/summaries/r7-ports-20260920-v1/thermal/hand_fault0_highs")
    old=load_r7_recovery_case(joinpath(p, "case.toml"))
    c=with_r7_battery_rule(old, rule)
    parent=TOML.parsefile(joinpath(p, "parent.toml"))
    ts=TOML.parsefile(joinpath(p, "spec.toml"))
    flow=Dict(
        k=>PaperRebuild.r7_unpack(parent["values"], k) for k in ("m_pipe", "m_source", "m_load")
    )
    s=r7_transport_spec(
        c;
        flow_schedule = flow,
        profiles = ts["profiles"],
        profile_origin = "same frozen original profiles",
        substeps = 4,
    )
    c, s, old
end

@testset "R7 explicit battery domain" begin
    root=normpath(joinpath(@__DIR__, ".."))
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    @testset "R7-B2 preserved injection is not preserved energy" begin
        effect=r7_battery_cycle_effect(5/9, 16/45, 0.8, 0.8, 1.0)
        @test effect.net_injection_change_MW==0
        @test effect.charge_MW≈0.2
        @test effect.discharge_MW==0
        @test effect.energy_increment_MWh≈0.16
        @test r7_battery_cycle_effect(5/9, 16/45, 0.8, 0.8, 0.25).energy_increment_MWh≈0.04
        @test r7_battery_cycle_effect(0.4, 0.2, 1.0, 1.0, 1.0).energy_increment_MWh==0
        @test_throws ErrorException r7_battery_cycle_effect(-1, 0, 1, 1, 1)
        @test_throws ErrorException r7_battery_cycle_effect(1, 1, 0, 1, 1)
        for optimizer in (opt, Clarabel.Optimizer)
            b=battery_boundary_model("paper_sum_bound"; optimizer)
            optimize!(b.model)
            @test termination_status(b.model)==MOI.OPTIMAL
            @test value(only(b.variables["P_ch"]))≈5/9 atol=1e-6
            @test value(only(b.variables["P_dis"]))≈16/45 atol=1e-6
        end
        b=battery_boundary_model("per_period_exclusive_v1"; optimizer = opt)
        optimize!(b.model)
        @test termination_status(b.model)==MOI.INFEASIBLE
        for mode in (0, 1)
            b=battery_boundary_model(
                "per_period_exclusive_v1";
                optimizer = Clarabel.Optimizer,
                mode = Dict("BES"=>fill(mode, 1, 1)),
            )
            optimize!(b.model)
            @test termination_status(b.model)==MOI.INFEASIBLE
        end
    end
    c, s, old=battery_transport_fixture("per_period_exclusive_v1")
    @testset "R7-B1 declared domain and fixed modes" begin
        @test old.data["battery_rule"]=="paper_sum_bound"
        @test c.sha256!=old.sha256
        @test with_r7_battery_rule(c, "paper_sum_bound").sha256==old.sha256
        @test_throws ErrorException with_r7_battery_rule(c, "unregistered")
        @test build_r7_recovery(c, [0]; fixed_z = [1]).model_class=="MILP"
        @test build_r7_transport_recovery(c, [0], s; fixed_z = [1]).model_class=="MILP"
        modes=Dict("BES2"=>zeros(Int, c.data["periods"], length(c.data["probabilities"])))
        @test build_r7_transport_recovery(c, [0], s; fixed_z = [1], fixed_battery_modes = modes).model_class=="LP"
        @test_throws ErrorException build_r7_recovery(old, [0]; fixed_battery_modes = modes)
        @test_throws ErrorException build_r7_recovery(c, [0]; fixed_battery_modes = Dict())
        @test_throws ErrorException build_r7_recovery(
            c,
            [0];
            fixed_battery_modes = Dict("BES2"=>fill(0.5, 1, 2)),
        )
        @test_throws ErrorException build_r7_recovery(
            c,
            [0];
            fixed_battery_modes = Dict("BES2"=>[0, 1]),
        )
        @test_throws ErrorException r7_recovery_lp(c, [1])
        @test_throws ErrorException build_r7_adversary(c, [])
        @test_throws ErrorException solve_r7_adversary(c; optimizer = opt, budget_sec = 0)
        @test !haskey(build_r7_recovery(old, [0]).variables, "b_BES")
        r=solve_r7_transport_recovery(c, [0], s; optimizer = opt, budget_sec = 60)
        @test get(r, "error", "")==""
        @test r["validation"]["model_pass"]
        @test r["validation"]["shared"]["mutual_exclusivity_pass"]
        @test r["validation"]["loss_MWh"]≈2/45 atol=1e-6
        raw=PaperRebuild.r7_unpack(r["values"], "b_BES")
        fixed=Dict(
            dev["id"]=>round.(Int, raw[g, :, :]) for
            (g, dev) in enumerate(c.data["devices"]) if dev["kind"]=="BES"
        )
        rr=solve_r7_transport_recovery(
            c,
            [0],
            s;
            optimizer = Clarabel.Optimizer,
            fixed_z = [1],
            fixed_battery_modes = fixed,
            budget_sec = 60,
        )
        @test rr["validation"]["model_pass"]
        @test rr["model_class"]=="LP"
        @test rr["validation"]["loss_MWh"]≈r["validation"]["loss_MWh"] atol=1e-6
        corrupt=deepcopy(rr)
        corrupt["fixed_battery_modes"]["BES2"]["data"][1]=1-fixed["BES2"][1]
        @test !validate_r7_transport_recovery(c, s, corrupt)["model_pass"]
        corrupt=deepcopy(r)
        corrupt["values"]["b_BES"]["data"][2]=0.5
        @test !validate_r7_transport_recovery(c, s, corrupt)["model_pass"]
        delete!(corrupt["values"], "b_BES")
        @test_throws ErrorException validate_r7_transport_recovery(c, s, corrupt)
        @test solve_r7_transport_recovery(c, [0], s; optimizer = opt, budget_sec = 0)["status"]=="budget_exhausted"
        unsupported=solve_r7_transport_recovery(
            c,
            [0],
            s;
            optimizer = Clarabel.Optimizer,
            fixed_z = [1],
            budget_sec = 60,
        )
        @test unsupported["status"]=="solver_or_build_error"
        @test !unsupported["validation"]["model_pass"]
        mktempdir() do d
            p=joinpath(d, "saved")
            save_r7_transport_recovery(c, s, rr, p)
            @test read_r7_transport_recovery(p).validation["model_pass"]
            open(joinpath(p, "case.toml"), "a") do io
                write(io, "\n# altered\n")
            end
            @test_throws ErrorException read_r7_transport_recovery(p)
        end
    end
    @testset "R7-B2 explicit ideal reconstruction of frozen original values" begin
        dir=joinpath(
            root,
            "results/summaries/r7-transport-20260920-v1/records/hand_reference_fault0_clarabel_n16",
        )
        source=load_r7_recovery_case(joinpath(dir, "case.toml"))
        spec=TOML.parsefile(joinpath(dir, "spec.toml"))
        parent=TOML.parsefile(joinpath(dir, "result.toml"))
        original=deepcopy(parent)
        out=r7_reconstruct_battery_cycles(source, spec, parent)
        @test parent==original
        @test out.result["validation"]["model_pass"]
        @test out.result["validation"]["shared"]["mutual_exclusivity_pass"]
        @test out.result["validation"]["loss_MWh"]≈0 atol=1e-6
        @test out.result["thermal_values"]==parent["thermal_values"]
        @test out.result["values"]["E_BES"]==parent["values"]["E_BES"]
        @test !haskey(out.result, "lower_bound_MWh")
        @test !out.result["optimized_again"]
        @test !out.result["validation"]["conditional_optimality_pass"]
        @test_throws ErrorException r7_reconstruct_battery_cycles(out.case, out.spec, out.result)
        mktempdir() do d
            save_r7_transport_recovery(out.case, out.spec, out.result, joinpath(d, "reconstructed"))
            @test read_r7_transport_recovery(joinpath(d, "reconstructed")).validation["model_pass"]
        end
    end
    @testset "R7-B3 normal event and finite fault planning" begin
        normal=with_r7_battery_rule(
            load_r7_normal_case(joinpath(root, "configs/r7/normal-hand.toml")),
            "per_period_exclusive_v1",
        )
        n=solve_r7_normal(normal; optimizer = opt, budget_sec = 60)
        @test get(n, "error", "")==""
        @test n["candidate_accepted"]
        @test n["validation"]["mutual_exclusivity_pass"]
        @test n["validation"]["cost_USD"]≈118.4 atol=1e-6
        ev=r7_normal_event(
            normal,
            n;
            event_start = 2,
            periods = 1,
            renewable_factor = 0.5,
            loss_limit_MWh = 0.4,
        )
        @test ev.case.data["battery_rule"]=="per_period_exclusive_v1"
        @test ev.case.data["devices"][2]["initial_MWh"]≈PaperRebuild.r7_unpack(n["values"], "E_BES")[
            2,
            2,
            :,
        ]
        rec=solve_r7_recovery(ev.case, [0]; optimizer = opt, budget_sec = 60)
        @test rec["candidate_accepted"]
        @test rec["validation"]["mutual_exclusivity_pass"]
        raw=PaperRebuild.r7_unpack(n["values"], "b_BES")
        modes=Dict("BES2"=>round.(Int, raw[2, :, :]))
        u=Dict("CHP1"=>ones(Int, 4))
        @test build_r7_normal(normal; fixed_commitments = u).model_class=="MILP"
        @test build_r7_normal(normal; fixed_commitments = u, fixed_battery_modes = modes).model_class=="LP"
        q=solve_r7_normal(
            normal;
            optimizer = Clarabel.Optimizer,
            fixed_commitments = u,
            fixed_battery_modes = modes,
            budget_sec = 60,
        )
        @test q["candidate_accepted"]
        @test q["solver_objective_USD"]≈118.4 atol=1e-5
        mktempdir() do d
            save_r7_normal(normal, n, joinpath(d, "normal"))
            @test read_r7_normal(joinpath(d, "normal")).validation["model_pass"]
            save_r7_recovery(ev.case, rec, joinpath(d, "recovery"))
            @test read_r7_recovery(joinpath(d, "recovery")).validation["model_pass"]
        end
        original=load_r7_planning_case(
            joinpath(root, "configs/r7/normal-reserve-hand.toml"),
            joinpath(root, "configs/r7/planning-reserve-hand.toml"),
        )
        planning=R7PlanningCase(
            with_r7_battery_rule(original.normal, "per_period_exclusive_v1"),
            original.specification,
        )
        @test_throws ErrorException solve_r7_planning(
            planning;
            optimizer = opt,
            method = :nested_indicator_ccg,
            budget_sec = 0,
        )
        for method in (:extensive, :finite_fault_ccg)
            r=solve_r7_planning(planning; optimizer = opt, method, budget_sec = 60)
            @test get(r, "error", "")==""
            @test r["candidate_accepted"]
            @test r["conditional_cost_complete"]
            @test r["validation"]["cost_USD"]≈193.275 atol=1e-6
            @test !r["validation"]["detailed_disaster_heat_verified"]
        end
    end
end
