using JuMP, Clarabel, SHA, TOML
isdefined(@__MODULE__, :r9_trading_fixture) || include("fixtures/r9_trading.jl")

function r9_network_test_protocol()
    p=TOML.parsefile(joinpath(@__DIR__, "../configs/r9/network-protocol.toml"))
    p["electric_ties"]=[[1, 3]]
    p["heat_ties"]=[[1, 3]]
    p["electric_base_switches"]=[[1, 2], [2, 3]]
    p["heat_base_switches"]=[[1, 2], [2, 3]]
    p
end

function r9_network_test_modes(c; E = nothing, H = nothing, T = c.data["T"])
    n=c.data["network_control"]
    em=E===nothing ? repeat(reshape(n["electric_initial"], :, 1), 1, T) : E
    hm=H===nothing ? reshape(n["heat_initial"], :, 1) : H
    Dict(
        "z_storage"=>zeros(Int, length(c.data["devices"]), T),
        "heat_direction"=>repeat(hm, 1, T),
        "u_E"=>em,
        "u_H"=>hm,
    )
end

@testset "R9-RN1 full graph and equipment design identity" begin
    root=normpath(joinpath(@__DIR__, ".."))
    parent=r9_trading_case(
        joinpath(root, "docs/reading/ch07"),
        joinpath(root, "configs/r9/trading-protocol.toml"),
    )
    # 7.5转录修正会改变整份来源哈希；历史身份应由冻结来源重建，不能强迫现行来源沿用旧哈希。
    frozen=r9_trading_case(
        joinpath(root, "results/summaries/r9-inputs-20260920-v1"),
        joinpath(root, "configs/r9/trading-protocol.toml"),
    )
    @test frozen.sha256=="73595793a7b47b3e39e4b4aa97a323ac35989887802b54ed113f36fa01dc4d1d"
    current_data, frozen_data=deepcopy(parent.data), deepcopy(frozen.data)
    current_sources=pop!(current_data["provenance"], "source_hashes")
    frozen_sources=pop!(frozen_data["provenance"], "source_hashes")
    @test current_data==frozen_data # 全部7.3数值、协议及其余来源仍逐值相同。
    @test Set(keys(current_sources))==Set(keys(frozen_sources))
    @test Set(k for k in keys(current_sources) if current_sources[k]!=frozen_sources[k]) ==
          Set(["inputs.toml"])
    @test parent.sha256!=frozen.sha256
    p=joinpath(root, "configs/r9/network-protocol.toml")
    legacy=r9_reconfiguration_case(parent, p)
    equipment=r9_reconfiguration_case(parent, p; design = :equipment, policy = :joint)
    for c in (legacy, equipment)
        @test length(c.data["electric"]["edges"])==47
        @test length(c.data["heat"]["pipes"])==39
        @test sum(c.data["network_control"]["electric_switchable"])==10
        @test sum(c.data["network_control"]["heat_switchable"])==4
        for key in ("actors", "devices", "grid_price", "settlement", "T", "dt_h", "units")
            @test c.data[key]==parent.data[key]
        end
        @test c.data["network_control"]["parent_sha256"]==parent.sha256
        @test build_r9_trading_model(c).model_class=="MISOCP"
        @test_throws ErrorException r9_trading_heat_cut(c, [1], 1)
        @test_throws ErrorException audit_r9_trading_capacity(c)
    end
    @test legacy.data["electric"]["edges"][1:43]==parent.data["electric"]["edges"]
    @test legacy.data["heat"]["pipes"][1:37]==parent.data["heat"]["pipes"]
    @test equipment.data["electric"]["edges"][37]["P_max_MW"] >
          parent.data["electric"]["edges"][37]["P_max_MW"]
    for (side, key, nb) in (("electric", "edges", 43), ("heat", "pipes", 37))
        for edge in legacy.data[side][key][(nb+1):end]
            path=edge["design_parent_path"]
            originals=parent.data[side][key][path]
            if side=="electric"
                @test edge["r_pu"]==sum(x["r_pu"] for x in originals)
                @test edge["P_max_MW"]==minimum(x["P_max_MW"] for x in originals)
            else
                @test edge["length_m"]==sum(x["length_m"] for x in originals)
                @test edge["loss_MW"]≈PaperRebuild.r4_loss(edge)
                @test edge["H_max_MW"]==minimum(x["H_max_MW"] for x in originals)
            end
        end
    end
    @test parent.source_text==PaperRebuild.r4_text(parent.data)
    @test_throws ErrorException r9_reconfiguration_case(legacy, p)
    for change in (
        d->(d["network_control"]["electric_initial"][1]=0),
        d->(d["network_control"]["heat_initial"][end]=1),
        d->(d["network_control"]["dwell_steps"]=0),
        d->(d["network_control"]["heat_action_CNY"]=-1),
        d->(d["network_control"]["stable_history_steps"]=-1),
        d->(d["schema"]="r9-trading-case-v1"),
    )
        d=deepcopy(legacy.data)
        change(d)
        @test_throws ErrorException R9TradingCase(d)
    end
end

@testset "R9-RN2 N4 fixed trees, closed ties and independent physics" begin
    parent=r9_trading_fixture()
    p=r9_network_test_protocol()
    # 3×3树选择穷举，验证连通域与逐弧方向，而不连续松弛二元变量。
    trees=[[1, 1, 0], [1, 0, 1], [0, 1, 1]]
    for e in trees, h in trees
        c=r9_reconfiguration_case(parent, p; policy = :joint)
        modes=r9_network_test_modes(c; E = reshape(e, :, 1), H = reshape(h, :, 1))
        # 树[0,1,1]中，2--3的参考方向要反转；源仍为节点1。
        h==[0, 1, 1] && (modes["heat_direction"][2, 1]=0)
        r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes, budget_sec = 60.0)
        @test r["validation"]["model_pass"]
        @test r["validation"]["heat_energy_mass_pass"]
        @test r["validation"]["ledger_pass"]
        @test r["model_version"]=="r9_trading_reconfiguration_v1"
        s=only(r["stages"])
        network=validate_r9_network(c, s["values"])
        expected=5.0*(sum(abs.(e .- [1, 1, 0]))+sum(abs.(h .- [1, 1, 0])))
        @test network["switching_CNY"]≈expected atol=1e-5
        loss=sum(pipe["loss_MW"]*on for (pipe, on) in zip(c.data["heat"]["pipes"], h))
        @test r["system_cost_CNY"]≈100*(1+loss)+expected atol=1e-4
        for (j, on) in enumerate(h)
            if on==0
                @test maximum(abs, s["values"]["H_plus_in"][j])<1e-6
                @test maximum(abs, s["values"]["H_minus_in"][j])<1e-6
            end
        end
        bad=deepcopy(s)
        bad["values"]["a_H"][1][1]+=1.0
        @test !validate_r9_trading_solution(c, bad)["model_pass"]
        bad=deepcopy(s)
        bad["values"]["F_E"][1][1]+=0.1
        @test !validate_r9_trading_solution(c, bad)["model_pass"]
    end
    c=r9_reconfiguration_case(parent, p; policy = :fixed)
    modes=r9_network_test_modes(c)
    r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes, budget_sec = 60.0)
    @test r["validation"]["model_pass"]
    bad=deepcopy(modes)
    bad["u_E"][end, 1]=1
    @test_throws ErrorException build_r9_trading_model(c; modes = bad)
    delete!(bad, "u_E")
    @test_throws ErrorException build_r9_trading_model(c; modes = bad)
    # 仅有边数不够：独立遍历拒绝断开/成环；被篡改的原值不能冒充通过。
    bad=deepcopy(only(r["stages"]))
    bad["values"]["u_E"][end][1]=1
    @test !validate_r9_trading_solution(c, bad)["model_pass"]
end

@testset "R9-RN3 dwell, daily valves and zero action fee" begin
    parent=r9_trading_fixture(; T = 3)
    p=r9_network_test_protocol()
    p["electric_action_CNY"]=p["heat_action_CNY"]=0.0
    c=r9_reconfiguration_case(parent, p; policy = :joint)
    E=[1 1 1; 0 0 1; 1 1 0]
    m=r9_network_test_modes(c; E)
    r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes = m, budget_sec = 60.0)
    @test r["validation"]["model_pass"]
    @test sum(sum(x) for x in only(r["stages"])["values"]["a_E"])≈4 atol=1e-5
    m["u_E"]=[1 1 1; 0 1 1; 1 0 0]
    r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes = m, budget_sec = 60.0)
    @test r["status"]=="infeasible_certified"
    m["u_H"]=ones(Int, 3, 3)
    @test_throws ErrorException build_r9_trading_model(c; modes = m)
end

@testset "R9-RN5 archive and budget preserve versioned topology" begin
    c=r9_reconfiguration_case(r9_trading_fixture(), r9_network_test_protocol(); policy = :joint)
    modes=r9_network_test_modes(c)
    r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes, budget_sec = 60.0)
    @test validate_r9_trading_run(c, r)["model_pass"]
    mktempdir() do dir
        path=save_r9_trading_run(c, r; directory = dir, run_id = "network")
        loaded=read_r9_trading_run(path)
        @test loaded.result["validation"]["model_pass"]
        text=read(joinpath(path, "input.toml"), String)
        write(joinpath(path, "input.toml"), text*"\n# tampered\n")
        @test_throws ErrorException read_r9_trading_run(path)
    end
    r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes, budget_sec = 0.0)
    @test !r["validation"]["model_pass"]
    @test only(r["stages"])["solver"]=="not_started"
    r=solve_r9_trading_case(
        c;
        optimizer = Clarabel.Optimizer,
        modes,
        operation = :independent,
        budget_sec = 60.0,
    )
    @test r["validation"]["local_plans_pass"]
    @test r["validation"]["model_pass"]
end
