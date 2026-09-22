module R7InitialProfileTests
using Test, PaperRebuild, JuMP, HiGHS, TOML
const PR=PaperRebuild
const ROOT=dirname(@__DIR__)
const OPT=optimizer_with_attributes(
    HiGHS.Optimizer,
    "threads"=>1,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
    "mip_feasibility_tolerance"=>1e-9,
    "mip_rel_gap"=>1e-9,
)

function profile_case()
    d=TOML.parsefile(joinpath(ROOT, "configs/r7/normal-hand.toml"))
    p=only(d["heat"]["pipes"])
    cp, M, flow, ua, ambient=4200.0, 18000.0, 5.0, 50.0, 293.15
    temperatures=Dict("S"=>343.15, "R"=>313.15)
    for side in ("S", "R")
        state=PR.R7PipeState([
            PR.R7PipeSegment(M, ambient, temperatures[side]-ambient, ua/(M*cp*flow), true),
        ])
        p["initial_$(side)_profiles"]=[
            r7_initial_profile(state; provenance = "synthetic exact steady pipe") for _ in 1:2
        ]
        p["UA_$(side)_W_K"]=ua
    end
    sout=ambient+(temperatures["S"]-ambient)*exp(-ua/(cp*flow))
    rout=ambient+(temperatures["R"]-ambient)*exp(-ua/(cp*flow))
    d["heat"]["load_MW"][2]=fill(cp/1e6*flow*(sout-temperatures["R"]), 4)
    d["devices"][1]["previous_P_MW"]=fill(cp/1e6*flow*(temperatures["S"]-rout), 2)
    R7NormalCase(d)
end

function flow_spec(c; thermal = :lossy_gauss)
    pipe=fill(5.0, 1, 4)
    source=[5.0 5 5 5; 0 0 0 0]
    load=[0.0 0 0 0; 5 5 5 5]
    r7_normal_flow_spec(
        c;
        pipe_min = pipe,
        pipe_max = pipe,
        source_min = source,
        source_max = source,
        load_min = load,
        load_max = load,
        thermal,
    )
end

@testset "R9-RI1 exact initial profiles and inherited space" begin
    old=load_r7_normal_case(joinpath(ROOT, "configs/r7/normal-hand.toml"))
    legacy=old.data["heat"]["pipes"][1]["initial_S_profiles"][1]
    @test PR.r7_initial_state(legacy).segments[1].amplitude_K==0.0
    @test PR.r7_initial_mean(legacy, 4200.0, 333.15)==343.15
    c=profile_case()
    p=only(c.data["heat"]["pipes"])
    state=PR.r7_normal_initial(c.data, p, "S", 1)
    encoded=r7_initial_profile(state; provenance = "roundtrip")
    roundtrip=PR.r7_initial_state(TOML.parse(PR.r7_text(encoded)))
    for x in (0.0, 100.0, 9000.0, 18000.0)
        @test r7_pipe_temperature(state, x)==r7_pipe_temperature(roundtrip, x)
    end
    @test_throws ErrorException r7_initial_profile(state; provenance = "")
    for mutator in (
        x->(x["schema"]="unknown"),
        x->(x["provenance"]=""),
        x->(x["segments"][1]["from_left"]=1),
        x->(x["segments"][1]["rate_per_kg"]=-1.0),
        x->(x["temperature_K"]=[343.15]),
    )
        bad=deepcopy(encoded)
        mutator(bad)
        @test_throws ErrorException PR.r7_initial_state(bad)
    end
    bad=deepcopy(c.data)
    bad["heat"]["pipes"][1]["initial_S_profiles"][1]["segments"][1]["amplitude_K"]=100.0
    @test_throws ErrorException R7NormalCase(bad)
    bad=deepcopy(c.data)
    bad["thermal_model"]="node_method_fixed_v1"
    @test_throws ErrorException R7NormalCase(bad)
    spec=Dict(
        "schema"=>"r7-planning-spec-v1",
        "normal_domain"=>"prescribed_positive_fixed_electric_topology",
        "recovery_model"=>"r7_recovery_checked_v1",
        "events"=>[
            Dict(
                "id"=>"event",
                "event_start"=>2,
                "periods"=>1,
                "renewable_factor"=>0.4,
                "loss_limit_MWh"=>2.0,
            ),
        ],
    )
    planning=R7PlanningCase(c, spec)
    template=PR.r7_event_template(planning, 1)
    @test template.data["heat"]["pipes"][1]["initial_S_K"][1]≈r7_pipe_inventory(
        state;
        cp_J_kgK = 4200.0,
        reference_K = 333.15,
    ).mean_K atol=1e-12
    r=solve_r7_normal(c; optimizer = OPT, budget_sec = 60)
    @test r["candidate_accepted"]
    @test r["validation"]["model_pass"]
    event=PR.r7_planning_event(planning, r, 1)
    @test !isempty(event.evidence["initial_pipe_profiles"])
    @test any(
        any(s["amplitude_K"]!=0 for s in p["segments"]) for
        p in event.evidence["initial_pipe_profiles"]
    )
end

@testset "R9-RI2 exponential mass kernel versus independent parcel replay" begin
    cp, M, lo, hi=4200.0, 18000.0, 303.15, 353.15
    # 两段、两种空间方向和正负幅值；实际端点均在温区内，base不必在温区内。
    state=PR.R7PipeState([
        PR.R7PipeSegment(0.4M, 293.15, 45.0, 0.12/M, true),
        PR.R7PipeSegment(0.6M, 343.15, -15.0, 0.07/M, false),
    ])
    profile=r7_initial_profile(state; provenance = "two-direction exponential kernel fixture")
    initial=PR.r7_initial_transport(profile, M, lo, hi)
    for ua in (0.0, 50.0), q in ([0.2, 0.0, 0.35, 1.1], [0.75, 0.5, 0.25, 0.0])
        dt=[0.25, 0.5, 0.25, 0.25]
        inlets=[340.15, 343.15, 333.15, 343.15]
        ambient=[293.15, 292.15, 295.15, 293.15]
        model=Model(OPT)
        set_silent(model)
        @variable(model, 0<=tin[1:4]<=1)
        @variable(model, 0<=tout[1:4]<=1)
        @variable(model, 0<=energy[1:5]<=1)
        for t in 1:4
            @constraint(model, tin[t]==(inlets[t]-lo)/(hi-lo))
        end
        kernel=PR.add_r7_lossy_mass_transport!(
            model,
            q,
            tin,
            tout,
            energy,
            initial.mass,
            initial.mean;
            initial_spatial = initial.spatial,
            dt_h = dt,
            decay_per_h = 3600ua/(M*cp),
            ambient = (ambient .- lo) ./ (hi-lo),
        )
        @objective(model, Min, 0)
        optimize!(model)
        @test termination_status(model)==MOI.OPTIMAL
        @test kernel.quadrature_bound<=1e-10
        current=state
        @test value(energy[1])≈r7_pipe_inventory(current; cp_J_kgK = cp, reference_K = lo).relative_heat_MWh/(
            M*cp/3.6e9*(hi-lo)
        ) atol=1e-10
        for t in 1:4
            step=r7_pipe_step(
                current;
                mass_flow_kg_s = q[t]*M/(3600dt[t]),
                inlet_K = inlets[t],
                ambient_K = ambient[t],
                dt_h = dt[t],
                cp_J_kgK = cp,
                UA_W_K = ua,
                reference_K = lo,
            )
            if q[t]>0
                @test lo+(hi-lo)*value(tout[t])≈step.outlet_mean_K atol=1e-8
            end
            current=step.state
            @test value(energy[t+1])≈r7_pipe_inventory(current; cp_J_kgK = cp, reference_K = lo).relative_heat_MWh/(
                M*cp/3.6e9*(hi-lo)
            ) atol=1e-9
        end
    end
    @test_throws ErrorException PR.r7_initial_spatial_check(
        initial.mass,
        initial.mean .+ 0.01,
        initial.spatial,
        0.0,
        1.0,
    )
end

@testset "R9-RI3 spatial error contract and end-to-end inheritance" begin
    c=profile_case()
    zero_data=deepcopy(c.data)
    zero_data["heat"]["pipes"][1]["UA_S_W_K"]=0.0
    zero_data["heat"]["pipes"][1]["UA_R_W_K"]=0.0
    zero_case=R7NormalCase(zero_data)
    zero_spec=flow_spec(zero_case; thermal = :lossless)
    timed=solve_r7_normal_flow(zero_case, zero_spec; optimizer = OPT, budget_sec = 0)
    @test timed["bound_scope"]=="adopted_spatial_profile_model_not_full_PDE"
    @test timed["validation"]["exact_transport_optimality_verified"]===false
    @test !timed["candidate_accepted"]
    free=deepcopy(zero_spec)
    for kind in ("pipe", "source", "load")
        free[kind*"_min"]=PR.r7_pack(0.8PR.r7_unpack(zero_spec, kind*"_min"))
        free[kind*"_max"]=PR.r7_pack(1.2PR.r7_unpack(zero_spec, kind*"_max"))
    end
    @test build_r7_normal_flow(zero_case, free).model_class=="nonconvex_MINLP"
    normal=solve_r7_normal_flow(
        c,
        flow_spec(c);
        optimizer = OPT,
        budget_sec = 60,
        energy_balance = true,
    )
    @test normal["candidate_accepted"]
    @test normal["domain_cost_complete"]
    @test normal["validation"]["model_pass"]
    bad=deepcopy(c.data)
    p=bad["heat"]["pipes"][1]
    p["initial_S_profiles"][1]=r7_initial_profile(
        PR.R7PipeState([PR.R7PipeSegment(18000.0, 333.15, 10.0, 40/18000, true)]);
        provenance = "valid-temperature but excessive quadrature remainder",
    )
    @test_throws ErrorException flow_spec(R7NormalCase(bad))
    for n in (5, 10), rate in (0.0, 0.05, 0.5)
        s=(; base = -0.2, amplitude = 0.9, rate, from_left = true)
        exact=s.base+s.amplitude*(rate==0 ? 1.0 : -expm1(-rate)/rate)
        shape=PR.r7_initial_spatial_check([1.0], [exact], [s], 0.0, 1.0)
        bound=PR.r7_initial_quadrature_bound(0.0, shape, [0.0], 0.0, 1.0; order = n)
        x, w=PR.r7_gauss_unit(n)
        quad=s.base+s.amplitude*sum(w .* exp.(-rate .* x))
        # 解析截断界不含Float64节点和求和舍入；此项单列舍入裕量，不改变A1。
        @test abs(quad-exact)<=bound+2e-15
    end
    d=deepcopy(c.data)
    d["electric"]["fault_budget"]=0
    plan=Dict(
        "schema"=>"r7-planning-spec-v1",
        "normal_domain"=>"prescribed_positive_fixed_electric_topology",
        "recovery_model"=>"r7_recovery_checked_v1",
        "events"=>[
            Dict(
                "id"=>"healthy",
                "event_start"=>2,
                "periods"=>1,
                "renewable_factor"=>0.4,
                "loss_limit_MWh"=>2.0,
            ),
        ],
    )
    pc=R7PlanningCase(R7NormalCase(d), plan)
    rb=Dict{String,Any}()
    for pair in PR.r7_planning_pairs(pc)
        rb[PR.r7_planning_pair_key(pair)]=Dict(
            "pipe_min"=>fill(5.0, 1, 1),
            "pipe_max"=>fill(5.0, 1, 1),
            "source_min"=>[5.0; 0;;],
            "source_max"=>[5.0; 0;;],
            "load_min"=>[0.0; 5;;],
            "load_max"=>[0.0; 5;;],
        )
    end
    jointspec=r7_flow_planning_spec(pc; normal_flow = flow_spec(pc.normal), recovery_bounds = rb)
    zero_plan=R7PlanningCase(zero_case, plan)
    zero_joint=r7_flow_planning_spec(
        zero_plan;
        normal_flow = zero_spec,
        recovery_bounds = Dict(
            PR.r7_planning_pair_key(pair)=>first(values(rb)) for
            pair in PR.r7_planning_pairs(zero_plan)
        ),
    )
    zero_result=solve_r7_flow_planning(zero_plan, zero_joint; optimizer = OPT, budget_sec = 0)
    @test zero_result["validation"]["bound_scope"]=="adopted_spatial_profile_model_not_full_PDE"
    joint=solve_r7_flow_planning(pc, jointspec; optimizer = OPT, budget_sec = 60)
    @test joint["candidate_accepted"]
    @test joint["domain_cost_complete"]
    @test all(w["model_pass"] for w in joint["validation"]["witness_checks"])
    archive=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    save_r7_normal_flow(c, flow_spec(c), normal, joinpath(archive, "normal"))
    save_r7_flow_planning(pc, jointspec, joint, joinpath(archive, "joint"))
    for name in ("normal", "joint")
        path=joinpath(archive, name)
        @test isfile(joinpath(path, "code/src/core/r7_initial_profile.jl"))
        moved=joinpath(archive, "moved_"*name)
        cp(path, moved)
        readrun=name=="normal" ? read_r7_normal_flow : read_r7_flow_planning
        @test readrun(moved).result["candidate_accepted"]
        file=joinpath(moved, name=="normal" ? "case.toml" : "normal.toml")
        open(file, "a") do io
            write(io, "\n# deliberate tamper\n")
        end
        @test_throws ErrorException readrun(moved)
    end
    println("Initial profile development evidence: ", relpath(archive, ROOT))
end
end
