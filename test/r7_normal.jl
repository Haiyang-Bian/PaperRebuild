using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA

@testset "R7 normal dispatch and event handoff" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r7_normal_case(joinpath(root, "configs/r7/normal-hand.toml"))
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    value_array(r, k) = PaperRebuild.r7_unpack(r["values"], k)
    base=solve_r7_normal(c; optimizer = opt)
    @testset "R7-D1 normal hand cost and physical energy" begin
        @test base["candidate_accepted"]
        @test base["conditional_cost_complete"]
        @test base["validation"]["pipe_reference_pass"]
        @test base["solver_objective_USD"] ≈ 118.4 atol=1e-6
        @test base["validation"]["resource_cost_USD"] ≈ 50.4 atol=1e-6
        @test base["validation"]["grid_payment_USD"] ≈ 68.0 atol=1e-6
        @test base["model_class"]=="MILP"
        @test !base["full_preplan_optimality_verified"]
        @test !base["validation"]["ac_grid_validated"]
        cv=solve_r7_normal(
            c;
            optimizer = Clarabel.Optimizer,
            fixed_commitments = Dict("CHP1"=>ones(Int, 4)),
        )
        @test cv["candidate_accepted"]
        @test cv["solver_objective_USD"] ≈ base["solver_objective_USD"] atol=1e-5
        @test cv["model_class"]=="LP"
        @test !haskey(cv, "lower_bound_USD") ? !cv["conditional_cost_complete"] : true
        @test build_r7_normal(c).model_class!="LP"
        for mask in 0:15
            pattern=[(mask>>(t-1))&1 for t in 1:4]
            er=solve_r7_normal(c; optimizer = opt, fixed_commitments = Dict("CHP1"=>pattern))
            @test er["status"]=="infeasible_certified" || er["candidate_accepted"]
            if er["candidate_accepted"]
                @test er["solver_objective_USD"]>=base["solver_objective_USD"]-1e-6
            end
        end
        @test_throws ErrorException validate_r7_normal(
            c,
            merge(deepcopy(base), Dict("full_preplan_optimality_verified"=>true)),
        )
    end
    @testset "R7-D2 battery and CHP event time" begin
        for at in (1, 2, 4)
            x=r7_normal_event(
                c,
                base;
                event_start = at,
                periods = 1,
                renewable_factor = 0.5,
                loss_limit_MWh = 2.0,
            )
            @test x.case.data["devices"][2]["initial_MWh"] ≈ value_array(base, "E_BES")[2, at, :]
            @test x.case.data["devices"][1]["previous_P_MW"] ≈ (
                at==1 ? c.data["devices"][1]["previous_P_MW"] : value_array(base, "P")[1, at-1, :]
            )
            @test x.evidence["event_case_sha256"]==x.case.sha256
            @test x.evidence["parent_case_sha256"]==c.sha256
            @test !x.evidence["full_preplan_optimality_verified"]
            for p in x.evidence["initial_pipe_profiles"]
                @test p["relative_heat_MWh"] ≈
                      value_array(base, "E_pipe_"*p["side"])[p["pipe"], at, p["scenario"]] atol=1e-7
            end
            rr=solve_r7_recovery(x.case, [0]; optimizer = opt)
            @test rr["candidate_accepted"]
            @test rr["preplan_id"]==base["run_id"]
        end
        @test_throws ErrorException r7_normal_event(
            c,
            base;
            event_start = 4,
            periods = 2,
            renewable_factor = 1,
            loss_limit_MWh = 1,
        )
        bad=deepcopy(base)
        bad["values"]["E_BES"]["data"][2]+=0.01
        @test !validate_r7_normal(c, bad)["model_pass"]
        @test_throws ErrorException r7_normal_event(
            c,
            bad;
            event_start = 2,
            periods = 1,
            renewable_factor = 1,
            loss_limit_MWh = 1,
        )
        d=deepcopy(c.data)
        d["electric"]["price_USD_MWh"]=[10.0, 100.0, 10.0, 100.0]
        d["devices"][2]["eta_ch"]=0.9
        d["devices"][2]["eta_dis"]=0.95
        varying=R7NormalCase(d)
        vr=solve_r7_normal(varying; optimizer = opt)
        @test vr["candidate_accepted"]
        @test abs(value_array(vr, "E_BES")[2, 2, 1]-value_array(vr, "E_BES")[2, 1, 1])>0.05
        event=r7_normal_event(
            varying,
            vr;
            event_start = 2,
            periods = 2,
            renewable_factor = 0.5,
            loss_limit_MWh = 2,
        )
        @test event.case.data["devices"][2]["initial_MWh"]≈value_array(vr, "E_BES")[2, 2, :]
        @test !(event.case.data["devices"][2]["initial_MWh"]≈value_array(vr, "E_BES")[2, end, :])
        @test event.case.data["devices"][1]["previous_P_MW"]≈value_array(vr, "P")[1, 1, :]
        @test all(
            abs(a["delta"])<=a["maximum_roundoff"] for a in event.evidence["boundary_adjustments"]
        )
        repairs=Dict{String,Any}[]
        @test PaperRebuild.r7_boundary_roundoff(
            nextfloat(0.8),
            0.0,
            0.8,
            "fixture",
            "MW",
            repairs,
        )==0.8
        @test only(repairs)["original"]==nextfloat(0.8)
        @test_throws ErrorException PaperRebuild.r7_boundary_roundoff(
            0.8+1e-10,
            0.0,
            0.8,
            "fixture",
            "MW",
            repairs,
        )
    end
    @testset "R7-D3 adopted directions and required inputs" begin
        @test minimum(value_array(base, "Φ_S")[1, :]-value_array(base, "Φ_S")[2, :])>=2500-1e-4
        @test minimum(value_array(base, "Φ_R")[2, :]-value_array(base, "Φ_R")[1, :])>=2500-1e-4
        for change in (
            d->d["heat"]["source_flow_kg_s"][1][1]=4.0,
            d->d["heat"]["pipes"][1]["normal_flow_kg_s"][1]=0.0,
            d->d["heat"]["pipes"][1]["initial_S_profiles"][1]["mass_kg"][1]=17000.0,
            d->d["electric"]["lines"][1]["base_closed"]=0,
            d->d["scenario_information"]="unspecified",
            d->d["heat_terminal_rule"]="implicit",
            d->d["devices"][2]["eta_ch"]=0.0,
        )
            d=deepcopy(c.data)
            change(d)
            @test_throws ErrorException R7NormalCase(d)
        end
        @test_throws ErrorException build_r7_normal(c; fixed_commitments = Dict())
        d=deepcopy(c.data)
        d["thermal_model"]="node_method_fixed_v1"
        d["heat"]["pipes"][1]["history_S_K"]=Any[]
        @test_throws ErrorException R7NormalCase(d)
    end
    @testset "R7-D4 transport superposition and node difference" begin
        for flows in ([5.0, 5.0, 5.0, 5.0], [4.0, 6.0, 5.0, 3.0]), ua in (0.0, 15.0)
            d=deepcopy(c.data)
            p=d["heat"]["pipes"][1]
            p["normal_flow_kg_s"]=flows
            p["UA_S_W_K"]=ua
            map=PaperRebuild.r7_normal_pipe_map(d, p, "S")
            for w in 1:2
                inlet=[341.0, 350.0, 345.0, 344.0]
                replay=PaperRebuild.r7_normal_pipe_replay(d, p, "S", w, inlet)
                @test map.b[:, w]+map.A*inlet ≈ replay.outlet atol=1e-9
                @test map.eb[:, w]+map.E*inlet ≈ replay.energy atol=1e-10
                @test all(abs(s.energy_residual_MWh)<1e-10 for s in replay.steps)
            end
        end
        d=deepcopy(c.data)
        d["thermal_model"]="node_method_fixed_v1"
        nm=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test nm["candidate_accepted"] && nm["validation"]["pipe_reference_pass"]
        @test nm["solver_objective_USD"]≈118.4 atol=1e-6
        d["heat"]["pipes"][1]["UA_S_W_K"]=15.0
        d["heat"]["pipes"][1]["UA_R_W_K"]=10.0
        d["heat_terminal_rule"]="free"
        lossy=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test lossy["candidate_accepted"]
        @test !lossy["validation"]["pipe_reference_pass"]
        @test_throws ErrorException r7_normal_event(
            R7NormalCase(d),
            lossy;
            event_start = 2,
            periods = 1,
            renewable_factor = 0.5,
            loss_limit_MWh = 2,
        )
        d["thermal_model"]="plug_flow_reference_v1"
        ref=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test ref["candidate_accepted"] && ref["validation"]["pipe_reference_pass"]
        d["heat"]["pipes"][1]["normal_flow_kg_s"]=[4.0, 6.0, 5.0, 3.0]
        d["heat"]["source_flow_kg_s"][1]=[4.0, 6.0, 5.0, 3.0]
        d["heat"]["load_flow_kg_s"][2]=[4.0, 6.0, 5.0, 3.0]
        changing=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        # 末时段m=3时，无损极限已经恰为0.63MW；正散热使其严格低于需求。
        @test changing["status"]=="infeasible_certified"
        @test !changing["candidate_accepted"]
        d["heat"]["pipes"][1]["normal_flow_kg_s"][4]=4.0
        d["heat"]["source_flow_kg_s"][1][4]=4.0
        d["heat"]["load_flow_kg_s"][2][4]=4.0
        feasible_flow=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test feasible_flow["candidate_accepted"] &&
              feasible_flow["validation"]["pipe_reference_pass"]
        # 改变时间离散但保持物理时长、负荷、价格和库存，成本不应因漏dt而翻倍。
        d=deepcopy(c.data)
        d["periods"]=8
        d["dt_h"]=0.5
        for key in ("load_MW",)
            d["electric"][key]=[repeat(a; inner = 2) for a in d["electric"][key]]
        end
        d["electric"]["price_USD_MWh"]=repeat(d["electric"]["price_USD_MWh"]; inner = 2)
        for key in ("load_MW", "source_flow_kg_s", "load_flow_kg_s")
            d["heat"][key]=[repeat(a; inner = 2) for a in d["heat"][key]]
        end
        d["heat"]["ambient_K"]=repeat(d["heat"]["ambient_K"]; inner = 2)
        d["heat"]["pipes"][1]["normal_flow_kg_s"]=repeat(
            d["heat"]["pipes"][1]["normal_flow_kg_s"];
            inner = 2,
        )
        half=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test half["candidate_accepted"] && half["conditional_cost_complete"]
        @test half["solver_objective_USD"]≈118.4 atol=1e-6
    end
    @testset "R7-D5 failures budgets and frozen values" begin
        d=deepcopy(c.data)
        d["electric"]["load_MW"][2].=10.0
        impossible=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test impossible["status"]=="infeasible_certified" && !impossible["candidate_accepted"]
        @test !haskey(impossible, "values")
        timeout=solve_r7_normal(c; optimizer = ()->error("must not instantiate"), budget_sec = 0)
        @test timeout["status"]=="budget_exhausted"
        denied=solve_r7_normal(c; optimizer = ()->error("license unavailable fixture"))
        @test denied["status"]=="license_unavailable"
        @test !denied["candidate_accepted"]
        unsupported=solve_r7_normal(c; optimizer = Clarabel.Optimizer)
        @test unsupported["status"]=="solver_error" && !unsupported["candidate_accepted"]
        # 根节点负荷不能被PCC=支路的简记漏掉；压力不足仍是数学不可行。
        d=deepcopy(c.data)
        d["electric"]["load_MW"][1].=0.1
        rootload=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test rootload["candidate_accepted"]
        @test rootload["solver_objective_USD"]≈158.4 atol=1e-6
        d=deepcopy(c.data)
        d["heat"]["delta_pressure_max_Pa"]=6000.0
        pressured=solve_r7_normal(R7NormalCase(d); optimizer = opt)
        @test pressured["status"]=="infeasible_certified"
        mktempdir(root) do folder
            path=joinpath(folder, "normal")
            save_r7_normal(c, base, path)
            copy=read_r7_normal(path)
            @test copy.validation["model_pass"]
            @test copy.result["values"]==base["values"]
            @test_throws ErrorException save_r7_normal(c, base, path)
            file=joinpath(path, "result.toml")
            write(file, read(file, String)*"\n# tampered\n")
            @test_throws ErrorException read_r7_normal(path)
            bad=deepcopy(base)
            bad["values"]["P"]["data"][1]+=0.01
            write(file, PaperRebuild.r7_text(bad))
            manifest=joinpath(path, "files.toml")
            hashes=TOML.parsefile(manifest)
            hashes["files"]["result.toml"]=bytes2hex(sha256(read(file)))
            write(manifest, PaperRebuild.r7_text(hashes))
            @test_throws ErrorException read_r7_normal(path) # 重封哈希仍不能伪造原方程通过。
        end
    end
    @testset "R7-D6 multi-source network and all device signs" begin
        d=deepcopy(c.data)
        e=d["electric"]
        h=d["heat"]
        e["nodes"]=3
        e["load_MW"]=[[0.0, 0.0, 0.0, 0.0], [0.2, 0.2, 0.2, 0.2], [0.6, 0.6, 0.6, 0.6]]
        e["tan_phi"]=[0.0, 0.1, 0.1]
        e["root_eligible"]=[1, 0, 1]
        e["shed_fraction_max"]=ones(3)
        line=deepcopy(e["lines"][1])
        line["from"]=2
        line["to"]=3
        push!(e["lines"], line)
        h["nodes"]=3
        h["load_MW"]=[[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.63, 0.63, 0.63, 0.63]]
        h["source_flow_kg_s"]=[[3.0, 3.0, 3.0, 3.0], [2.0, 2.0, 2.0, 2.0], [0.0, 0.0, 0.0, 0.0]]
        h["load_flow_kg_s"]=[[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [5.0, 5.0, 5.0, 5.0]]
        h["source_flow_max"]=[10.0, 10.0, 0.0]
        h["load_flow_max"]=[0.0, 0.0, 10.0]
        h["source_delta_min"]=zeros(3)
        h["load_delta_min"]=zeros(3)
        h["source_delta_max"]=[80.0, 80.0, 0.0]
        h["load_delta_max"]=[0.0, 0.0, 60.0]
        h["shed_fraction_max"]=ones(3)
        pipe=deepcopy(h["pipes"][1])
        pipe["from"]=2
        pipe["to"]=3
        push!(h["pipes"], pipe)
        h["pipes"][1]["normal_flow_kg_s"].=3.0
        d["devices"][2]["electric_node"]=3
        push!(
            d["devices"],
            Dict(
                "id"=>"EB2",
                "kind"=>"EB",
                "electric_node"=>2,
                "heat_node"=>2,
                "P_max_MW"=>0.5,
                "heat_ratio"=>3.0,
                "cost_P_USD_MWh"=>0.0,
            ),
        )
        push!(
            d["devices"],
            Dict(
                "id"=>"PV2",
                "kind"=>"PV",
                "electric_node"=>2,
                "P_max_MW"=>0.2,
                "available_MW"=>[[0.1, 0.2] for _ in 1:4],
                "cost_P_USD_MWh"=>0.0,
            ),
        )
        push!(
            d["devices"],
            Dict(
                "id"=>"GT3",
                "kind"=>"GT",
                "electric_node"=>3,
                "P_max_MW"=>0.2,
                "Q_max_Mvar"=>0.2,
                "cost_P_USD_MWh"=>200.0,
            ),
        )
        multi=R7NormalCase(d)
        mr=solve_r7_normal(multi; optimizer = opt)
        @test mr["candidate_accepted"] && mr["validation"]["pipe_reference_pass"]
        @test size(value_array(mr, "τ_pipe_R"))==(2, 4, 2)
        @test maximum(value_array(mr, "H")[3, :, :])>0
        @test maximum(value_array(mr, "P")[4, :, :])>0
        @test maximum(value_array(mr, "P")[5, :, :])<1e-6
        @test maximum(value_array(mr, "Q_line"))>0
        event=r7_normal_event(
            multi,
            mr;
            event_start = 2,
            periods = 1,
            renewable_factor = 0.5,
            loss_limit_MWh = 3,
        )
        @test event.case.data["electric"]["nodes"]==3
        @test length(event.evidence["initial_pipe_profiles"])==8
    end
end
