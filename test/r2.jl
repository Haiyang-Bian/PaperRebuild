using Test, PaperRebuild, JuMP, Clarabel, TOML
const R2_ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(R2_ROOT, "scripts", "r2_setup.jl"))
r2case(name = "single-source") = load_r2_case(joinpath(R2_ROOT, "configs", "r2", name*".toml"))
function r2_edited_case(f; name = "single-source")
    d = deepcopy(r2case(name).data)
    f(d)
    return mktempdir() do directory
        path = joinpath(directory, "case.toml")
        open(io -> TOML.print(io, d), path, "w")
        load_r2_case(path)
    end
end

@testset "R2 transport ch03-027:034" begin
    for delay in (0.5, 1.0, 1.5, 2.0)
        w = water_mass_weights(ones(5), 3600delay, 3600)
        @test sum(w.w) ≈ 1
        @test minimum(w.w) >= -1e-14
        @test sum(w.α)*3600 ≈ 3600delay
        @test sum(w.β[2:end])*3600 ≈ 3600delay
        @test all(abs.((1 .- w.α[1:(end-1)]) .* w.α[2:end]) .<= 1e-14)
    end
    r = replay_water_mass(
        [350.0, 360.0, 350.0, 350.0],
        ones(4),
        fill(340.0, 4),
        ones(4);
        mass_kg = 5400.0,
        dt_h = 1.0,
    )
    @test r.outlet ≈ [340.0, 345.0, 355.0, 355.0]
    kernel = fixed_flow_kernel(1.0, 1000.0, 0.01, 540.0, 1.0, 0.0)
    @test r.outlet ≈ pipe_outlet([350.0, 360.0, 350.0, 350.0], fill(340.0, 4), kernel, 293.0)
    rloss = replay_water_mass(
        fill(353.0, 4),
        ones(4),
        fill(353.0, 4),
        ones(4);
        mass_kg = 1800.0,
        dt_h = 1.0,
        epsilon_W_mK = 0.2,
    )
    @test all(293 .< rloss.outlet .< 353)
    @test rloss.outlet ≈ fill(293+60exp(-0.2*180/(4200*1)), 4)
    varying = replay_water_mass(
        [350.0, 360.0, 350.0, 350.0],
        [1.0, 2.0, 0.5, 1.0],
        fill(340.0, 4),
        ones(4);
        mass_kg = 1800.0,
        dt_h = 1.0,
    )
    @test all(w -> isapprox(sum(w.w), 1; atol = 1e-12), varying.weights)
    @test varying.outlet[1] ≈ 345
    @test_throws ArgumentError water_mass_weights([0.0, 1.0], 100.0, 3600.0)
    @test_throws ArgumentError water_mass_weights([1.0, 1.0], 1e6, 3600.0)
    @test_throws ArgumentError water_mass_weights([NaN, 1.0], 100.0, 3600.0)
    # 同一常值历史和物理管道，细分时间步保持稳态与停留秒数。
    fine = replay_water_mass(
        fill(353.0, 8),
        ones(8),
        fill(353.0, 8),
        ones(8);
        mass_kg = 1800.0,
        dt_h = 0.5,
        epsilon_W_mK = 0.2,
    )
    @test fine.outlet[2:2:end] ≈ rloss.outlet
    @test fine.residence_s[2:2:end] ≈ rloss.residence_s
end

@testset "R2 envelopes and literal counterexamples ch03-042:052" begin
    for x in (1.0, 4.0), y in (2.0, 6.0)
        box = mccormick_bounds(x, y, (1.0, 4.0), (2.0, 6.0))
        @test box.lower ≈ x*y ≈ box.upper
    end
    for x in range(1.0, 4.0; length = 5), y in range(2.0, 6.0; length = 5)
        box = mccormick_bounds(x, y, (1.0, 4.0), (2.0, 6.0))
        @test box.lower <= x*y <= box.upper
    end
    @test_throws ArgumentError mccormick_bounds(1.0, 2.0, (0.0, Inf), (1.0, 3.0))
    @test_throws ArgumentError mccormick_bounds(1.0, 2.0, (3.0, 1.0), (1.0, 3.0))
    # 原式3-42第二项缺比热：真实右上角竟不满足某上包络。
    @test 4.2*4*6 > 4.2*4*2+4*(6-2)
    # 取 AL=1、相同温差消去3-47括号歧义，原3-46仍给E0=2Emax。
    @test 2*(20+20) > 20+20
    # 原3-52的 m*(Tout-Tin) 的混合差分非零，不能称为仿射。
    f(m, Δτ) = m*Δτ
    @test f(2, 2)-f(2, 1)-f(1, 2)+f(1, 1) == 1
    # 成本单位转换及同一物理窗口分步积分。
    @test 1000*0.1 == 100.0
    @test sum(fill(0.2, 4))*1.0 ≈ sum(fill(0.2, 8))*0.5
end

@testset "R2 inputs and class ch03-001:057" begin
    c = r2case()
    @test_throws ArgumentError r2_edited_case(d -> (d["units"]["power"] = "kW"))
    @test_throws ArgumentError r2_edited_case(d -> (d["heat"]["pipes"][1]["flow_min"] = 0.0))
    @test_throws ArgumentError r2_edited_case(d -> empty!(d["heat"]["pipes"][1]["flow_history"]))
    @test_throws ArgumentError r2_edited_case(d -> (d["electric"]["edges"][1]["to"] = 1))
    @test_throws ArgumentError r2_edited_case(d -> (d["ambient_K"] = [NaN, 293.0, 293.0, 293.0]))
    @test_throws KeyError r2_edited_case(d -> delete!(d, "dt_h"))
    for form in (:wmm_literal, :schpd_literal)
        @test build_r2_model(c; spec = R2Spec(; formulation = form)).status == "blocked"
        @test solve_r2_case(c; optimizer = nothing, spec = R2Spec(; formulation = form))["status"] ==
              "blocked"
    end
    @test build_r2_model(c).class == "nonconvex"
    @test build_r2_model(c; fixed_flows = true).class == "SOCP"
    @test build_r2_model(r2case("two-source"); spec = R2Spec(; formulation = :schpd_mc_v1)).class ==
          "MISOCP"
    @test build_r2_model(c; spec = R2Spec(; formulation = :schpd_mc_v1, heat_balance = :exact)).class ==
          "nonconvex"
    @test_throws ArgumentError R2Spec(; formulation = :unknown)
    @test build_r2_model(
        c;
        spec = R2Spec(; formulation = :schpd_mc_v1, dynamics_product = :exact),
    ).class == "nonconvex"
    terms(t) = [Dict("termination"=>t)]
    @test PaperRebuild.r2_status(terms("TIME_LIMIT"), 1, true, true) == "time_limit_with_incumbent"
    @test PaperRebuild.r2_status(terms("TIME_LIMIT"), 1, false, true) == "time_limit_no_solution"
    @test PaperRebuild.r2_status(terms("LOCALLY_SOLVED"), 1, true, false) == "local_solution"
    @test PaperRebuild.r2_status(terms("NUMERICAL_ERROR"), 1, false, false) == "numerical_failure"
    @test PaperRebuild.r2_status(terms("UNSUPPORTED"), 1, false, false) == "unsupported_solver"
    @test PaperRebuild.r2_status(terms("OPTIMAL"), 1, false, false) == "incomplete_no_solution"
    @test !PaperRebuild.r2_valid_bound(-1e100, "Gurobi")
    @test !PaperRebuild.r2_valid_bound(Inf, "Clarabel")
    @test PaperRebuild.r2_valid_bound(0.0, "Gurobi")
    @test r2_setup_status(ErrorException("No Gurobi license found")) == "not_run_license"
    @test r2_setup_status(ArgumentError("Package Gurobi not found")) == "dependency_missing"
    @test isnothing(r2_setup_status(ErrorException("unexpected program error")))
    @test PaperRebuild.r2_status(terms("INFEASIBLE_OR_UNBOUNDED"), 1, false, false) ==
          "incomplete_no_solution"
end

@testset "R2 saved integration ch03-001:057" begin
    c = r2case()
    r = solve_r2_case(c; optimizer = Clarabel.Optimizer, fixed_flows = true, budget_sec = 60.0)
    @test r["status"] == "solver_optimal"
    report = validate_r2_solution(c, r)
    @test report.model_pass
    @test any(row -> row.scope == "physics" && row.equation == "3-25", report.rows)
    broken = deepcopy(r)
    broken["values"]["P_grid"][1] += 0.1
    @test !validate_r2_solution(c, broken).model_pass
    impossible = r2_edited_case(d -> (d["heat"]["nodes"][2]["H_MW"] .= 10.0))
    failed = solve_r2_case(
        impossible;
        optimizer = Clarabel.Optimizer,
        fixed_flows = true,
        budget_sec = 60.0,
    )
    @test failed["status"] == "infeasible_certified"
    @test !haskey(failed, "values")
    timeout =
        solve_r2_case(c; optimizer = Clarabel.Optimizer, fixed_flows = true, budget_sec = 1e-12)
    @test timeout["status"] == "time_limit_no_solution"
    @test !validate_r2_solution(c, timeout).model_pass
    unsupported = solve_r2_case(c; optimizer = Clarabel.Optimizer, budget_sec = 60.0)
    @test unsupported["status"] == "unsupported_solver"
    license_failure =
        r2_setup_failure(c, R2Spec(), "not_run_license"; fixed_flows = false, budget_sec = 60.0)
    @test !haskey(license_failure, "values")
    mktempdir() do directory
        path = save_r2_run(c, r; root = directory, run_id = "test")
        loaded = read_r2_run(path)
        @test loaded.case.sha256 == c.sha256
        @test loaded.result["objective"] == r["objective"]
        @test validate_r2_solution(loaded.case, loaded.result).model_pass
        @test compare_r2_runs(path, path).cost_difference == 0
        failed_path = save_r2_run(c, license_failure; root = directory, run_id = "missing-license")
        @test read_r2_run(failed_path).result["status"] == "not_run_license"
        @test_throws Base.IOError save_r2_run(c, r; root = directory, run_id = "test")
        open(io -> write(io, "\n# changed\n"), joinpath(path, "solution.toml"), "a")
        @test_throws ArgumentError read_r2_run(path)
    end
    # 简化同模型最大入流枚举：16个四时段选择含相等流量情况；不开商业许可。
    two = r2case("two-source")
    enum = solve_r2_case(
        two;
        optimizer = Clarabel.Optimizer,
        spec = R2Spec(; formulation = :schpd_mc_v1),
        fixed_flows = true,
        enumerate_mixing = true,
        budget_sec = 60.0,
    )
    @test enum["status"] == "solver_optimal"
    @test length(enum["subproblems"]) == 16
    @test validate_r2_solution(two, enum).model_pass
end
