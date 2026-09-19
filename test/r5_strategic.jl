using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML
include(joinpath(@__DIR__, "..", "scripts", "r5_strategic_cases.jl"))

@testset "R5-ST 连续报价与独立下层" begin
    c = r5_strategic_fixture()
    @test R5StrategicCase(c.data).sha256 == c.sha256
    @test c.data["market"]["dt_h"] == 1
    for change in (
        d->(d["selection"]="unstated"),
        d->(d["risk"]["commitment"]["day_ahead"]["energy_price"]=[100.0]),
        d->(push!(
            d["market"]["ies"],
            merge(deepcopy(d["market"]["ies"][1]), Dict("id"=>"second")),
        )),
        d->(d["market"]["dt_h"]=0.25),
        d->(d["bid_bounds"]["up_bid"]["upper"]=[-1.0]),
    )
        d = deepcopy(c.data)
        change(d)
        @test_throws ErrorException R5StrategicCase(d)
    end
    b = build_r5_strategic(c)
    @test b.model_type == "linear_MPEC_SOS1_with_risk_branches"
    @test any(occursin("SOS1", t) for t in b.model_types)
    @test objective_function_type(b.model) == AffExpr
    @test all(!has_upper_bound(p.multiplier) for p in values(b.market.pairs))
    pattern = Dict(k=>0 for k in keys(b.market.pairs))
    bf = build_r5_strategic(c; risk_pattern = [0, 0, 0], complementarity_pattern = pattern)
    @test bf.model_type == "fixed_branch_LP"
    @test !any(occursin("SOS1", t) for t in bf.model_types)
    @test_throws ErrorException build_r5_strategic(c; complementarity_pattern = Dict("bad"=>0))
    highs = optimizer_with_attributes(
        HiGHS.Optimizer,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
    )
    clarabel = optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
    runs = Dict{String,Any}[]
    for optimizer in (highs, clarabel)
        r = solve_r5_strategic(
            c;
            optimizer,
            oracle_optimizer = highs,
            risk_pattern = [0, 0, 0],
            complementarity_pattern = pattern,
            budget_sec = 60,
        )
        @test r["status"] == "solver_optimal"
        @test r["validation"]["model_pass"]
        @test r["validation"]["selected_kkt_pass"]
        @test !r["validation"]["selected_market"]["kkt_pass"] # 没有伪造原始MOI对偶
        @test r["validation"]["independent_market_kkt_pass"]
        @test r["validation"]["risk_pass"]
        @test r["cost_optimization_complete"]
        @test r["validation"]["bound_scope"] == "declared_fixed_branch"
        @test r["validation"]["worst_total_cost_USD"] ≈ 2.085 atol=1e-5
        @test r["risk_policy"]["first_stage"]["P_DA_MW"] ≈ [0.08] atol=1e-6
        @test r["risk_policy"]["first_stage"]["R_up_MW"] ≈ [0.08] atol=1e-6
        @test r["risk_policy"]["first_stage"]["R_down_MW"] ≈ [0.062] atol=1e-6
        @test !haskey(r["selected_market"], "raw_duals")
        @test !haskey(r["risk_policy"], "solver_objective_bound")
        push!(runs, r)
    end
    r = first(runs)
    for field in ("bids", "bridge", "multiplier", "oracle")
        bad = deepcopy(r)
        if field=="bids"
            bad["bids"]["energy_bid"][1] = 201.0
            @test_throws ErrorException validate_r5_strategic(c, bad)
        elseif field=="bridge"
            bad["risk_policy"]["first_stage"]["P_DA_MW"][1] += 0.01
            @test_throws ErrorException validate_r5_strategic(c, bad)
        elseif field=="multiplier"
            bad["selected_market"]["multipliers"]["energy"][1] += 10.0
            @test !validate_r5_strategic(c, bad)["selected_kkt_pass"]
        else
            delete!(bad["risk_policy"]["oracles"], "risk")
            @test !validate_r5_strategic(c, bad)["risk_pass"]
        end
    end
    bad = deepcopy(r)
    bad["selected_market"]["raw_duals"] = Dict()
    @test_throws ErrorException validate_r5_strategic(c, bad)
    no = solve_r5_strategic(c; optimizer = highs, oracle_optimizer = highs, budget_sec = 60)
    @test no["status"] == "unsupported_solver"
    @test !no["validation"]["optimality_pass"]
    timed = solve_r5_strategic(
        c;
        optimizer = highs,
        oracle_optimizer = highs,
        budget_sec = 1e-12,
        risk_pattern = [0, 0, 0],
        complementarity_pattern = pattern,
    )
    @test timed["status"] == "budget_exhausted_before_solve"
    @test !timed["has_candidate"]
    infeasible=r5_strategic_fixture("physical_infeasible")
    pattern_bad=Dict(k=>0 for k in keys(build_r5_strategic(infeasible).market.pairs))
    ri=solve_r5_strategic(
        infeasible;
        optimizer = highs,
        oracle_optimizer = highs,
        risk_pattern = [0, 0, 0],
        complementarity_pattern = pattern_bad,
        budget_sec = 60,
    )
    @test ri["status"]=="solver_infeasible"
    @test !ri["validation"]["model_pass"]
    mktempdir() do dir
        path = joinpath(dir, "hand")
        save_r5_strategic_run(c, r, path)
        @test read_r5_strategic_run(path).validation["optimality_pass"]
        @test_throws ErrorException save_r5_strategic_run(c, r, path)
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# tampered")
        end
        @test_throws ErrorException read_r5_strategic_run(path)
    end
end

@testset "R5-ST 阶梯供给与私人成本" begin
    highs=optimizer_with_attributes(
        HiGHS.Optimizer,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
    )
    for fixed_bid in (false, true)
        c=r5_strategic_merit_fixture(; fixed_bid)
        patterns=Dict(k=>0 for k in keys(build_r5_strategic(c).market.pairs))
        for k in keys(patterns)
            occursin("lower/R_", k) && (patterns[k]=1)
        end
        patterns["g_cap_up/1/1"]=1
        patterns["lower/P_G/2/1"]=fixed_bid ? 0 : 1
        r=solve_r5_strategic(
            c;
            optimizer = highs,
            oracle_optimizer = highs,
            risk_pattern = [0, 0, 0],
            complementarity_pattern = patterns,
            budget_sec = 60,
        )
        @test r["cost_optimization_complete"]
        @test r["validation"]["worst_total_cost_USD"]≈(fixed_bid ? 14.2 : 7.46) atol=1e-5
        @test r["risk_policy"]["first_stage"]["P_DA_MW"]≈[fixed_bid ? 0.142 : 0.1] atol=1e-6
        @test r["validation"]["selected_market"]["LMP_USD_MWh"][1][1]≈(fixed_bid ? 100.0 : 20.0) atol=1e-5
    end
end
