using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA

function linked_test_case(; limit = 0.4, exclusive = false, healthy_only = false)
    root=normpath(joinpath(@__DIR__, ".."))
    normal=TOML.parsefile(joinpath(root, "configs/r7/normal-reserve-hand.toml"))
    healthy_only && (normal["electric"]["fault_budget"]=0)
    exclusive && (normal["battery_rule"]="per_period_exclusive_v1")
    rules=TOML.parsefile(joinpath(root, "configs/r7/planning-reserve-hand.toml"))
    foreach(e->e["loss_limit_MWh"]=limit, rules["events"])
    c=R7PlanningCase(R7NormalCase(normal), rules)
    flows=Dict{String,Any}()
    for p in PaperRebuild.r7_planning_pairs(c)
        T=rules["events"][p.event]["periods"]
        f=any(==(1), p.fault) ? 0.0 : 5.0
        flows[PaperRebuild.r7_planning_pair_key(p)]=Dict(
            "m_pipe"=>fill(f, 1, T),
            "m_source"=>vcat(fill(f, 1, T), zeros(1, T)),
            "m_load"=>vcat(zeros(1, T), fill(f, 1, T)),
        )
    end
    c, r7_linked_planning_spec(c; flows, substeps = 4)
end

@testset "R7 linked normal spatial state and recovery planning" begin
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    c, s=linked_test_case()
    @testset "R7-L1 affine history and spatial memory" begin
        for event in 1:2, side in ("S", "R"), w in 1:2, fault in ([0], [1])
            pair=(event = event, fault = fault)
            H=c.specification["events"][event]["event_start"]-1
            K=4
            mid=c.normal.data["heat"]["$(side)_reference_K"]
            input=mid .+ 0.01 .* sin.(collect(1:(H+K)))
            map=r7_linked_pipe_map(c, s, pair, 1, side, w)
            sim=r7_linked_pipe_replay(c, s, pair, 1, side, w, input[1:H], input[(H+1):end])
            sample=PaperRebuild.r7_thermal_samples(sim, (h = c.normal.data["heat"], K = K), side)
            @test maximum(abs.(map.b+map.A*input-sample))<1e-9
            normal=PaperRebuild.r7_normal_pipe_replay(
                c.normal.data,
                c.normal.data["heat"]["pipes"][1],
                side,
                w,
                vcat(input[1:H], fill(mid, c.normal.data["periods"]-H)),
            )
            @test PaperRebuild.r7_thermal_extrema(sim.states[1])≈PaperRebuild.r7_thermal_extrema(
                normal.states[H+1],
            ) atol=1e-10
            @test all(iszero, map.A[K+1, (H+1):end])
        end
        # 同库存、冷热位置相反，事件首段出口不同；不允许用均温自由重建状态。
        function front(reverse_order)
            d=deepcopy(c.normal.data)
            for profile in d["heat"]["pipes"][1]["initial_S_profiles"]
                profile["mass_kg"]=[9000.0, 9000.0]
                profile["temperature_K"]=reverse_order ? [352.0, 334.0] : [334.0, 352.0]
            end
            rules=deepcopy(c.specification)
            rules["events"]=[merge(first(rules["events"]), Dict("event_start"=>1))]
            case=R7PlanningCase(R7NormalCase(d), rules)
            fs=Dict(
                PaperRebuild.r7_planning_pair_key(p)=>Dict(
                    "m_pipe"=>fill(0.5, 1, 1),
                    "m_source"=>reshape([0.5, 0.0], 2, 1),
                    "m_load"=>reshape([0.0, 0.5], 2, 1),
                ) for p in PaperRebuild.r7_planning_pairs(case)
            )
            spec=r7_linked_planning_spec(case; flows = fs, substeps = 4)
            r7_linked_pipe_replay(
                case,
                spec,
                (event = 1, fault = [0]),
                1,
                "S",
                1,
                Float64[],
                fill(343.0, 4),
            )
        end
        a, b=front(false), front(true)
        @test a.steps[1].before.relative_heat_MWh≈b.steps[1].before.relative_heat_MWh atol=1e-12
        @test a.steps[1].outlet_mean_K-b.steps[1].outlet_mean_K≈18.0 atol=1e-9
        @test_throws ErrorException r7_linked_pipe_replay(
            c,
            s,
            (event = 1, fault = [0]),
            1,
            "S",
            1,
            Float64[],
            fill(340.0, 4),
        )
        @test_throws ErrorException r7_linked_pipe_map(
            c,
            s,
            (event = 1, fault = [0]),
            1,
            "S",
            1;
            deadline = time()-1,
        )
        # 非整步、流向切换及有损情形，仅验证管输运算子；未宣称对应网络可实施。
        d=deepcopy(c.normal.data)
        p=d["heat"]["pipes"][1]
        p["UA_S_W_K"]=250.0
        p["UA_R_W_K"]=150.0
        p["flow_change_max_kg_s"]=10.0
        d["heat"]["source_flow_max"]=[10.0, 10.0]
        d["heat"]["load_flow_max"]=[10.0, 10.0]
        d["heat"]["source_flow_kg_s"][2]=fill(1.0, d["periods"])
        d["heat"]["load_flow_kg_s"][2]=fill(6.0, d["periods"])
        d["heat"]["source_delta_max"][2]=80.0
        d["heat"]["load_delta_max"][1]=60.0
        push!(
            d["devices"],
            Dict(
                "id"=>"EB_reverse_test",
                "kind"=>"EB",
                "electric_node"=>2,
                "heat_node"=>2,
                "P_max_MW"=>1.0,
                "heat_ratio"=>1.0,
                "cost_P_USD_MWh"=>0.0,
            ),
        )
        rules=deepcopy(c.specification)
        rules["events"]=[merge(first(rules["events"]), Dict("periods"=>2))]
        cm=R7PlanningCase(R7NormalCase(d), rules)
        fs=Dict(
            PaperRebuild.r7_planning_pair_key(pair)=>Dict(
                "m_pipe"=>reshape([2.3, -1.7], 1, 2),
                "m_source"=>[2.3 0.0; 0.0 1.7],
                "m_load"=>[0.0 1.7; 2.3 0.0],
            ) for pair in PaperRebuild.r7_planning_pairs(cm)
        )
        sm=r7_linked_planning_spec(cm; flows = fs, substeps = 3)
        for side in ("S", "R")
            mid=d["heat"]["$(side)_reference_K"]
            input=mid .+ 0.05 .* collect(1:7)
            map=r7_linked_pipe_map(cm, sm, (event = 1, fault = [0]), 1, side, 1)
            sim=r7_linked_pipe_replay(
                cm,
                sm,
                (event = 1, fault = [0]),
                1,
                side,
                1,
                input[1:1],
                input[2:end],
            )
            sample=PaperRebuild.r7_thermal_samples(sim, (h = d["heat"], K = 6), side)
            @test maximum(abs.(map.b+map.A*input-sample))<1e-9
            @test all(abs(z.energy_residual_MWh)<1e-10 for z in sim.steps)
            @test all(z.loss_MWh>0 for z in sim.steps)
        end
    end
    @testset "R7-L2 shared planning and independent fault witnesses" begin
        @test build_r7_linked_planning(c, s).model_class=="MILP"
        @test isempty(build_r7_linked_planning(c, s; included = []).recovery)
        @test_throws ErrorException build_r7_linked_planning(
            c,
            s;
            included = [(event = 9, fault = [0])],
        )
        ex=solve_r7_linked_planning(c, s; optimizer = opt, method = :extensive, budget_sec = 60)
        cc=solve_r7_linked_planning(
            c,
            s;
            optimizer = opt,
            method = :finite_fault_ccg,
            budget_sec = 60,
        )
        for r in (ex, cc)
            @test r["candidate_accepted"]
            @test r["conditional_cost_complete"]
            @test r["validation"]["substep_transport_verified"]
            @test r["validation"]["cost_USD"]≈193.275 atol=1e-6
            @test !r["validation"]["full_variable_flow_verified"]
            n=r["iterations"][r["validation"]["candidate_iteration"]]["master"]["normal"]
            energy=PaperRebuild.r7_unpack(n["values"], "E_BES")
            @test all(isapprox.(energy[2, 2:3, :], 0.8; atol = 1e-6))
        end
        @test length(cc["iterations"])>=2
        @test any(!isempty(i["added_pairs"]) for i in cc["iterations"])
        n=cc["iterations"][cc["validation"]["candidate_iteration"]]["master"]["normal"]
        for pair in PaperRebuild.r7_planning_pairs(c)
            ev=PaperRebuild.r7_linked_event(c, s, n, pair)
            rr=solve_r7_transport_recovery(
                ev.case,
                pair.fault,
                ev.spec;
                optimizer = Clarabel.Optimizer,
                fixed_z = 1 .- pair.fault,
                budget_sec = 60,
            )
            @test rr["validation"]["model_pass"]
            @test rr["validation"]["loss_MWh"]<=0.4+1e-6
        end
        cx, sx=linked_test_case(exclusive = true)
        rx=solve_r7_linked_planning(cx, sx; optimizer = opt, method = :extensive, budget_sec = 60)
        @test rx["candidate_accepted"]
        @test rx["validation"]["cost_USD"]≈193.275 atol=1e-6
        c0, s0=linked_test_case(limit = 0)
        for method in (:extensive, :finite_fault_ccg)
            r=solve_r7_linked_planning(c0, s0; optimizer = opt, method, budget_sec = 60)
            @test r["status"]=="infeasible_certified"
            @test !r["candidate_accepted"]
        end
        @testset "R7-L3 provenance failures and original value replay" begin
            wrong=deepcopy(ex)
            w=wrong["iterations"][1]["master"]["witnesses"][1]
            w["normal_inlets"]["1/S/1"][1]+=1
            @test !validate_r7_linked_planning(c, s, wrong)["robust_model_pass"]
            wrong=deepcopy(ex)
            wrong["iterations"][1]["master"]["witnesses"][1]["thermal_values"]["E_S"]["data"][1]+=0.01
            @test !validate_r7_linked_planning(c, s, wrong)["robust_model_pass"]
            wrong=deepcopy(cc)
            wrong["iterations"][end]["audits"][1]=deepcopy(wrong["iterations"][1]["audits"][1])
            @test_throws ErrorException validate_r7_linked_planning(c, s, wrong)
            bad=deepcopy(s)
            pop!(bad["flows"])
            @test_throws ErrorException build_r7_linked_planning(c, bad)
            mktempdir() do dir
                dest=joinpath(dir, "new")
                save_r7_linked_planning(c, s, cc, dest)
                @test isequal(read_r7_linked_planning(dest).result, cc)
                @test_throws ErrorException save_r7_linked_planning(c, s, cc, dest)
                open(io->write(io, "# tampered\n"), joinpath(dest, "result.toml"), "a")
                @test_throws ErrorException read_r7_linked_planning(dest)
            end
        end
    end
    @testset "R7-L4 shared budget and failures" begin
        r=solve_r7_linked_planning(c, s; optimizer = opt, budget_sec = 0)
        @test isempty(r["iterations"])
        @test r["status"]=="budget_exhausted"
        @test !r["candidate_accepted"]
        @test_throws ErrorException solve_r7_linked_planning(
            c,
            s;
            optimizer = opt,
            budget_sec = 601,
        )
        @test_throws ErrorException solve_r7_linked_planning(
            c,
            s;
            optimizer = opt,
            method = :nested_indicator_ccg,
        )
        r=solve_r7_linked_planning(
            c,
            s;
            optimizer = ()->error("license unavailable fixture"),
            budget_sec = 60,
        )
        @test r["status"]=="license_unavailable"
        @test !r["candidate_accepted"]
        expired=solve_r7_linked_planning(
            c,
            s;
            optimizer = ()->error("thermal_build_deadline"),
            budget_sec = 60,
        )
        @test expired["status"]=="budget_exhausted" && !expired["candidate_accepted"]
        r=solve_r7_linked_planning(c, s; optimizer = Clarabel.Optimizer, budget_sec = 60)
        @test r["status"]=="solver_or_build_error"
        @test !r["candidate_accepted"]
    end
end
