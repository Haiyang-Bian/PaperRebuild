using JuMP, Clarabel, HiGHS, TOML

const MICRO = joinpath(@__DIR__, "..", "configs", "r1", "micro.toml")

@testset "R1-devices ch02-001:019 ch02-072:076" begin
    @test chp_heat(0.2, 0.4, 0.1) ≈ 0.25
    @test chp_efficiency(0.5, 1.0, [0.3, 0.1, 0.0, 0.0]) ≈ 0.35
    @test_throws ArgumentError chp_heat(1, 0.9, 0.2)
    @test pv_available(1, 0.9, 0.5, 1, -0.004, 308.15, 298.15) ≈ 0.432
    @test_throws DomainError pv_available(1, 1, 1, 1, -0.1, 320, 298)
    @test wind_ramp_paper(5, 3, 12, 25, 1) < 0 # 原式疑点，不是修正后风机验证。
    @test battery_step(1, 0.4, 0, 0.9, 0.9, 0.25) ≈ 1.09
    @test battery_step(1, 0, 0.36, 0.9, 0.9, 0.25) ≈ 0.9
    @test heat_storage_step_paper(1, 0, 0, 1, 1, 0.99, 0.25) ≈ 0.99
    @test heat_storage_step_paper(0, 1, 0, 0.9, 0.9, 1, 1) > 1 # 被动性反例保留。
    @test building_step(294.15, 0.11, 283.15, 10, 0.1) ≈ 294.15
    @test heat_power(2, 323.15, 303.15) ≈ 0.168
    @test heat_power(2, 50, 30) ≈ heat_power(2, 323.15, 303.15) # 温差单位一致。
    @test_throws ArgumentError battery_step(1, 0, 0, 0, 1, 1)
    @test electrical_bases(1, 10).Z_ohm == 100
    @test electrical_bases(1, 10).I_kA ≈ 1 / (10sqrt(3))
    @test_throws ArgumentError electrical_bases(0, 10)
end

@testset "R1-pipe ch02-042 ch02-047:054" begin
    k = fixed_flow_kernel(2, 1000, 0.02, 90, 0.25, 0)
    @test k.delay_steps == 1
    @test pipe_outlet([320.0, 330.0], [310.0], k, 280) ≈ [310, 320]
    khalf = fixed_flow_kernel(2, 1000, 0.02, 135, 0.25, 0)
    @test khalf.weights == (0.5, 0.5)
    @test pipe_outlet([320.0, 330.0], [300.0, 310.0], khalf, 280) ≈ [305, 315]
    kshort = fixed_flow_kernel(2, 1000, 0.02, 45, 0.25, 0)
    @test pipe_outlet([320.0], [300.0], kshort, 280) ≈ [310]
    @test_throws ArgumentError pipe_outlet([320.0], [300.0], khalf, 280)
    @test_throws ArgumentError fixed_flow_kernel(-2, 1000, 0.02, 90, 0.25, 0)
    @test mix_temperature([1, 3], [300, 320]) == 315
    @test_throws ArgumentError mix_temperature([0], [300])
    kloss = fixed_flow_kernel(2, 1000, 0.02, 90, 0.25, 0.2)
    @test kloss.J ≈ exp(-0.2 * 900 * 0.5 / (4200 * 1000 * 0.02))
    @test all(280 .< pipe_outlet([320.0, 320.0], [320.0], kloss, 280) .< 320)
end

@testset "R1-analytic HiGHS storage and Clarabel branch" begin
    # 两时段独立电池解析试验：这是带时间模式的项目参考，不冒称原式的 z 范围。
    m = Model(HiGHS.Optimizer)
    set_silent(m)
    @variable(m, 0 <= charge <= 1)
    @variable(m, 0 <= discharge <= 1)
    @constraint(m, 0.9charge == discharge / 0.9)
    @objective(m, Min, charge - 2discharge)
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL
    @test value(charge) ≈ 1
    @test value(discharge) ≈ 0.81
    @test objective_value(m) ≈ -0.62
    # 无损支路解析值：P=.3, Q=.1, v=1, l=.1；用最小 l 保证锥紧。
    m = Model(Clarabel.Optimizer)
    set_silent(m)
    @variable(m, l >= 0)
    @constraint(m, [l + 1, 0.6, 0.2, l - 1] in SecondOrderCone())
    @objective(m, Min, l)
    optimize!(m)
    @test value(l) ≈ 0.1 atol = 1e-7
end

@testset "R1-input and integration ch02-022:028" begin
    c = load_case(MICRO)
    @test c.data["time"]["T"] == 4
    mktempdir() do dir
        function malformed(f)
            d = deepcopy(c.data)
            f(d)
            path = joinpath(dir, "bad.toml")
            open(io -> TOML.print(io, d), path, "w")
            return path
        end
        @test_throws ArgumentError load_case(malformed(d -> delete!(d, "units")))
        @test_throws ArgumentError load_case(malformed(d -> delete!(d["heat"], "c_w")))
        @test_throws ArgumentError load_case(malformed(d -> d["units"]["power"] = "kW"))
        @test_throws ArgumentError load_case(malformed(d -> d["demand"]["P_D"] = [0.2]))
        @test_throws ArgumentError load_case(malformed(d -> d["heat"]["history_S"] = Float64[]))
        @test_throws ArgumentError load_case(malformed(d -> d["building"]["reference_dt_h"] = 1))
        @test_throws ArgumentError load_case(malformed(d -> d["devices"]["eta_HS_ch"] = 0.9))
        @test_throws ArgumentError load_case(malformed(d -> d["electric"]["to"] = 3))
        r = solve_r1_case(c; optimizer = Clarabel.Optimizer, budget_sec = 120)
        @test r["status"] == "solver_optimal"
        @test length(r["subproblems"]) == 4
        report = validate_r1_solution(c, r)
        @test report.relaxed_pass
        @test report.original_branch_pass
        @test all(r["values"]["P_BS_ch"] .* r["values"]["P_BS_dis"] .<= 1e-12)
        @test all(r["values"]["H_HS_ch"] .* r["values"]["H_HS_dis"] .<= 1e-12)
        scaled_path = malformed() do d
            d["electric"]["S_base_MVA"] = 2.0
            d["electric"]["r_pu"] *= 2
            d["electric"]["x_pu"] *= 2
            d["electric"]["l_max_pu"] /= 4
        end
        scaled_case = load_case(scaled_path)
        scaled = solve_r1_case(scaled_case; optimizer = Clarabel.Optimizer, budget_sec = 120)
        @test scaled["status"] == "solver_optimal"
        @test scaled["objective"] ≈ r["objective"] atol = 1e-6
        @test validate_r1_solution(scaled_case, scaled).original_branch_pass
        changed = deepcopy(r)
        changed["values"]["E_BS"][end] += 0.01
        @test !validate_r1_solution(c, changed).relaxed_pass
        changed = deepcopy(r)
        changed["values"]["P_grid"][1] += 0.01
        @test !validate_r1_solution(c, changed).relaxed_pass
        changed = deepcopy(r)
        changed["values"]["l"][1] += 0.001
        @test !validate_r1_solution(c, changed).original_branch_pass
        saved = save_r1_run(c, r; root = dir, run_id = "roundtrip")
        loaded = read_r1_run(saved)
        @test loaded.result["objective"] == r["objective"]
        @test validate_r1_solution(loaded.case, loaded.result).relaxed_pass
        @test_throws Base.IOError save_r1_run(c, r; root = dir, run_id = "roundtrip")
        @test_throws ArgumentError save_r1_run(c, r; root = dir, run_id = "../escape")
        open(io -> write(io, "\n# tamper\n"), joinpath(saved, "case.toml"), "a")
        @test_throws ArgumentError read_r1_run(saved)
        # 合法但电流容量不足的输入；保留不可行，不读取不存在的 value。
        bad = load_case(malformed(d -> d["electric"]["l_max_pu"] = 1e-10))
        impossible = solve_r1_case(bad; optimizer = Clarabel.Optimizer, budget_sec = 120)
        @test impossible["status"] == "infeasible"
        @test !haskey(impossible, "values")
        @test validate_r1_solution(bad, impossible).status == "not_assessed_no_solution"
        stopped = solve_r1_case(c; optimizer = Clarabel.Optimizer, budget_sec = 1e-12)
        @test stopped["status"] == "incomplete"
    end
end
