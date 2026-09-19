module R5StrategicBendersTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML
include(joinpath(@__DIR__, "..", "scripts", "r5_strategic_cases.jl"))
const highs = optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
    "mip_feasibility_tolerance"=>1e-9,
    "mip_rel_gap"=>1e-9,
)
const clarabel = optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
rule(route = :cuts; max_iterations = 200) = R5BendersSpec(
    feasibility = route,
    cut_arithmetic = :rational_box,
    diagnostic_scale = 1024.0,
    max_iterations = max_iterations,
)
pattern(c) = Dict(k=>0 for k in keys(build_r5_strategic_benders_master(c).market.pairs))
const runs = Dict{Symbol,Any}()

@testset "R5-SB 市场主问题和声明域" begin
    c = r5_strategic_fixture()
    b = build_r5_strategic_benders_master(c)
    @test b.bound_scope == "full_optimistic_MPEC"
    @test termination_status(b.model) == MOI.OPTIMIZE_NOT_CALLED
    @test any(occursin("SOS1", t) for t in b.model_types)
    @test objective_function_type(b.model) == AffExpr
    @test all(!has_upper_bound(p.multiplier) for p in values(b.market.pairs))
    pat = pattern(c)
    fixed = build_r5_strategic_benders_master(c; complementarity_pattern = pat)
    @test fixed.bound_scope == "fixed_complementarity_domain"
    @test !any(occursin("SOS1", t) for t in fixed.model_types)
    @test build_r5_strategic_benders_master(c; spec = rule(:paper_critical)).bound_scope ==
          "restricted_comfort_domain"
    @test build_r5_strategic_benders_master(
        c;
        spec = rule(:paper_critical),
        complementarity_pattern = pat,
    ).bound_scope == "fixed_complementarity_and_comfort_domain"
    @test_throws ErrorException build_r5_strategic_benders_master(
        c;
        complementarity_pattern = Dict("bad"=>0),
    )
    @test_throws ErrorException build_r5_strategic_benders_master(c; critical = [1])
end

@testset "R5-SB 条件割与完整候选费用" begin
    c = r5_strategic_fixture()
    for route in (:cuts, :critical, :paper_critical)
        r = solve_r5_strategic_benders(
            c;
            optimizer = highs,
            subproblem_optimizer = highs,
            oracle_optimizer = clarabel,
            spec = rule(route),
            complementarity_pattern = pattern(c),
            budget_sec = 60,
        )
        runs[route] = r
        println(
            "strategy hand ",
            route,
            ": ",
            r["status"],
            " n=",
            length(r["iterations"]),
            " upper=",
            r["validation"]["upper_bound"],
            " error=",
            get(r, "error", ""),
        )
        @test r["validation"]["evidence_pass"]
        @test r["validation"]["model_pass"] && r["validation"]["risk_pass"]
        @test r["validation"]["upper_bound"] ≈ 2.085 atol=1e-5
        @test r["validation"]["independent_market_kkt_pass"]
        @test !r["cost_optimization_complete"] # 固定互补分支不是整个MPEC的证书
        @test !r["validation"]["optimality_pass"]
        @test isempty(first(r["iterations"])["master"]["cut_source_ids"])
        @test isempty(first(r["iterations"])["master"]["critical"])
        @test r["source_unchanged"]
        @test validate_r5_strategic_benders(c, TOML.parse(PaperRebuild.r5_market_text(r)))["model_pass"]
        if route != :paper_critical
            @test r["declared_branch_cost_complete"] && r["validation"]["stopping_pass"]
            @test r["validation"]["lower_bound"] <= 2.085+1e-6
        else
            @test r["validation"]["restricted_stopping_pass"] || r["validation"]["stopping_pass"]
        end
        for step in r["iterations"]
            m = step["master"]
            if m["has_candidate"]
                @test !haskey(m["selected_market"], "raw_duals")
                @test !m["validation"]["risk_master"]["bound_valid"]
                @test m["validation"]["objective_recomputed"] ≈
                      m["validation"]["payment_USD"]+m["validation"]["recourse_epigraph_USD"] atol=1e-6
            end
        end
    end
end

@testset "R5-SB 风险时间尺度和私人支付" begin
    for (label, expected) in (("quarter", 0.52125), ("thermal_e030_r005", 1.36648))
        c = r5_strategic_fixture(label)
        r = solve_r5_strategic_benders(
            c;
            optimizer = highs,
            oracle_optimizer = clarabel,
            spec = rule(:critical),
            complementarity_pattern = pattern(c),
            budget_sec = 60,
        )
        @test r["declared_branch_cost_complete"]
        @test r["validation"]["upper_bound"] ≈ expected atol=1e-5
    end
    for fixed_bid in (false, true)
        c = r5_strategic_merit_fixture(; fixed_bid)
        pat = pattern(c)
        for k in keys(pat)
            occursin("lower/R_", k) && (pat[k]=1)
        end
        pat["g_cap_up/1/1"] = 1
        pat["lower/P_G/2/1"] = fixed_bid ? 0 : 1
        r = solve_r5_strategic_benders(
            c;
            optimizer = highs,
            oracle_optimizer = clarabel,
            spec = rule(:critical),
            complementarity_pattern = pat,
            budget_sec = 60,
        )
        @test r["declared_branch_cost_complete"]
        @test r["validation"]["upper_bound"] ≈ (fixed_bid ? 14.2 : 7.46) atol=1e-5
        v = r["validation"]["selected_validation"]
        @test v["worst_total_cost_USD"] ≈ v["selected_payment_USD"]+v["worst_recourse_USD"] atol=1e-6
        # 参考只在分解完成之后另求，不向其传入报价、成交或条件割。
        ref = solve_r5_strategic(
            c;
            optimizer = highs,
            oracle_optimizer = clarabel,
            complementarity_pattern = pat,
            budget_sec = 60,
        )
        @test ref["cost_optimization_complete"]
        @test abs(v["worst_total_cost_USD"]-ref["validation"]["worst_total_cost_USD"]) /
              max(1.0, abs(v["worst_total_cost_USD"])) <= 1e-4
    end
end

@testset "R5-SB 证据重读与失败传播" begin
    c = r5_strategic_fixture()
    r = runs[:cuts]
    for mutate in (
        x->(x["iterations"][1]["master"]["bound_scope"]="full_optimistic_MPEC"),
        x->(x["iterations"][end]["master"]["solver_objective"]+=1),
        x->(x["iterations"][1]["master"]["selected_market"]["raw_duals"]=Dict()),
        x->(x["cuts"][first(x["cut_order"])]["constant"]+=1),
        x->(x["selected_iteration"]=0),
        x->(x["iterations"][end]["gap"]["relative"]=0.7),
        x->(x["iterations"][1]["master"]["cut_source_ids"]=copy(x["cut_order"])),
        x->(x["status"]="declared_domain_infeasible"),
        x->(x["selection"]="minimum_norm_execution"),
        x->(x["objective_type"]="system_resource_cost"),
        x->delete!(x["subproblem_source_hashes"], first(keys(x["subproblem_source_hashes"]))),
    )
        bad = deepcopy(r)
        mutate(bad)
        @test_throws ErrorException validate_r5_strategic_benders(c, bad)
    end
    timed = solve_r5_strategic_benders(c; optimizer = highs, budget_sec = 1e-12)
    @test timed["status"] == "budget_exhausted"
    @test !timed["validation"]["model_pass"]
    unsupported = solve_r5_strategic_benders(c; optimizer = highs, budget_sec = 60)
    @test unsupported["status"] == "unsupported_solver"
    @test !unsupported["cost_optimization_complete"]
    no_license = ()->error("synthetic license unavailable")
    missing = solve_r5_strategic_benders(c; optimizer = no_license, budget_sec = 60)
    @test missing["status"] == "license_unavailable"
    @test !missing["validation"]["model_pass"]
    badcase = r5_strategic_fixture("physical_infeasible")
    ri = solve_r5_strategic_benders(
        badcase;
        optimizer = highs,
        oracle_optimizer = clarabel,
        spec = rule(:critical),
        complementarity_pattern = pattern(badcase),
        budget_sec = 60,
    )
    @test ri["status"] == "declared_domain_infeasible"
    @test ri["validation"]["infeasibility_scope"] == "fixed_complementarity_domain"
    @test !ri["validation"]["model_pass"]
    bad = deepcopy(ri)
    bad["status"] = "master_relaxation_DUAL_INFEASIBLE"
    @test_throws ErrorException validate_r5_strategic_benders(badcase, bad)
    mktempdir() do dir
        saved = save_r5_strategic_benders_run(c, r, joinpath(dir, "hand"))
        @test read_r5_strategic_benders_run(saved).validation["stopping_pass"]
        @test_throws ErrorException save_r5_strategic_benders_run(c, r, saved)
        changed = deepcopy(r)
        changed["cost_optimization_complete"] = true
        @test_throws ErrorException save_r5_strategic_benders_run(
            c,
            changed,
            joinpath(dir, "false-global"),
        )
        ref = solve_r5_strategic(
            c;
            optimizer = highs,
            oracle_optimizer = clarabel,
            complementarity_pattern = pattern(c),
            budget_sec = 60,
        )
        refdir = save_r5_strategic_run(c, ref, joinpath(dir, "direct"))
        pair = compare_r5_strategic_benders_runs(saved, refdir)
        @test pair["a2_pass"] && !pair["full_model_a2_pass"]
        open(joinpath(saved, "result.toml"), "a") do io
            write(io, "\n# tampered")
        end
        @test_throws ErrorException read_r5_strategic_benders_run(saved)
    end
end
end
