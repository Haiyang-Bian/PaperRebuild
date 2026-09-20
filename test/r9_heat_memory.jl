using Test, TOML

@testset "R9-V5 independent WMM memory energy identity" begin
    root = dirname(@__DIR__)
    parent = joinpath(root, "results/summaries/r9-numerics-20260921-v2")
    c = load_r9_pv_case(joinpath(parent, "case.toml"))
    saved =
        TOML.parsefile(joinpath(parent, "runs/cf_ct_gurobi_original/result.toml"))["stage"]["values"]
    a = r9_heat_memory_balance(c, saved)
    @test length(a.rows) == 74
    @test abs(a.memory_change_MWh) < 1e-10
    @test abs(a.residual_MWh) < 1e-10
    @test a.attenuation_MWh > 0
    @test a.net_MWh ≈ r9_daily_heat_balance(c, saved).pipe_net_MWh atol=1e-10
    # 无损单调入口降温：净热量只能来自WMM记忆；不用建模器生成温度。
    d = deepcopy(c.data)
    for p in d["heat"]["pipes"]
        p["epsilon_W_mK"] = 0.0
    end
    no_loss = R2Case(d, c.sha256)
    v = deepcopy(saved)
    E, T = length(d["heat"]["pipes"]), d["T"]
    for (p, pipe) in enumerate(d["heat"]["pipes"]), side in ("S", "R")
        v["m_pipe"][p] = [first(pipe["fixed_flow"])*(0.8+0.4t/T) for t in 1:T]
        v["tau_"*side*"_in"][p] = [last(pipe[side*"_history_K"])-3t/T for t in 1:T]
    end
    for p in 1:E, side in ("S", "R"), t in 1:T
        v["tau_"*side*"_out"][p][t] = PaperRebuild.r3_mass_replay(no_loss, v, p, t, side).out
    end
    a = r9_heat_memory_balance(no_loss, v)
    expected =
        -6d["heat"]["cp_J_kgK"] *
        sum(d["heat"]["rho_kg_m3"]*p["area_m2"]*p["length_m"] for p in d["heat"]["pipes"]) / 3.6e9
    @test a.memory_change_MWh ≈ expected
    @test a.net_MWh ≈ expected atol=1e-10
    @test abs(a.attenuation_MWh) < 1e-10
    @test maximum(abs(r.residual_MWh) for r in a.rows) < 1e-10
    # 不以保存的star值作为证据；坏出口只改变损耗项，仍须独立物理检查。
    v["tau_S_star"] .= [fill(NaN, T) for _ in 1:E]
    @test r9_heat_memory_balance(no_loss, v).memory_change_MWh == a.memory_change_MWh
    d["dt_h"] *= 2
    doubled = r9_heat_memory_balance(R2Case(d, c.sha256), v)
    @test doubled.memory_change_MWh == a.memory_change_MWh
    @test abs(doubled.residual_MWh) < 1e-10
    bad = deepcopy(v)
    bad["m_pipe"][1][1] = 0.0
    @test_throws ArgumentError r9_heat_memory_balance(c, bad)
    bad = deepcopy(v)
    bad["tau_S_out"][1][1] = NaN
    @test_throws ArgumentError r9_heat_memory_balance(c, bad)
    delete!(bad, "tau_S_out")
    @test_throws ArgumentError r9_heat_memory_balance(c, bad)
    bad = deepcopy(v)
    pop!(bad["m_pipe"])
    @test_throws ArgumentError r9_heat_memory_balance(c, bad)
end
