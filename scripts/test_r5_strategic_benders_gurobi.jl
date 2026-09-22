# 本机完整市场SOS1对照；保留失败原值，不给开放固定分支测试冒充全域证书。
using Test, PaperRebuild, TOML
include("r5_strategic_setup.jl")
include("r5_strategic_cases.jl")
length(ARGS) == 1 || error("用法：test_r5_strategic_benders_gurobi.jl NEW_OUTPUT_DIRECTORY")
root = abspath(only(ARGS))
ispath(root) && error("不得覆盖已有开发对照")
mkpath(root)
gurobi = r5_strategic_optimizer(:gurobi)
items = [
    ("hand_cuts", r5_strategic_fixture(), :cuts),
    ("hand_critical", r5_strategic_fixture(), :critical),
    ("hand_paper", r5_strategic_fixture(), :paper_critical),
    ("thermal", r5_strategic_fixture("thermal_e030_r005"), :critical),
    ("future", r5_strategic_fixture("future_e030_r005"), :critical),
    ("merit", r5_strategic_merit_fixture(), :critical),
    ("fixed", r5_strategic_merit_fixture(; fixed_bid = true), :critical),
    ("capacity", r5_strategic_fixture("physical_infeasible"), :critical),
    ("scarcity", r5_strategic_scarcity_fixture(), :critical),
]
records = Dict{String,Any}[]
@testset "R5-SB 本机完整SOS1与独立直接对照" begin
    for (name, c, route) in items
        println("BEGIN ", name)
        flush(stdout)
        r = solve_r5_strategic_benders(
            c;
            optimizer = gurobi,
            subproblem_optimizer = r5_risk_optimizer(:highs),
            oracle_optimizer = r5_risk_optimizer(:highs),
            spec = R5BendersSpec(
                feasibility = route,
                cut_arithmetic = :rational_box,
                diagnostic_scale = 1024.0,
            ),
            budget_sec = 600,
        )
        path = save_r5_strategic_benders_run(c, r, joinpath(root, name))
        row = Dict{String,Any}(
            "name"=>name,
            "status"=>r["status"],
            "run_id"=>r["run_id"],
            "upper"=>r["validation"]["upper_bound"],
            "iterations"=>length(r["iterations"]),
        )
        println("END ", name, " ", row)
        flush(stdout)
        @test r["source_unchanged"]
        @test read_r5_strategic_benders_run(path).validation["evidence_pass"]
        if name == "capacity"
            @test r["status"] == "declared_domain_infeasible"
            @test !r["validation"]["model_pass"]
        elseif name == "scarcity"
            @test startswith(r["status"], "master_relaxation_")
            @test r["validation"]["unboundedness_scope"] ==
                  "master_relaxation_only_not_original_strategy"
        elseif route == :paper_critical
            @test r["validation"]["restricted_stopping_pass"] || r["validation"]["stopping_pass"]
            @test r["validation"]["model_pass"]
        else
            @test r["cost_optimization_complete"]
            ref = solve_r5_strategic(
                c;
                optimizer = gurobi,
                oracle_optimizer = r5_risk_optimizer(:highs),
                budget_sec = 600,
            )
            refdir = save_r5_strategic_run(c, ref, joinpath(root, name*"-direct"))
            row["comparison"] = compare_r5_strategic_benders_runs(path, refdir)
            @test row["comparison"]["full_model_a2_pass"]
        end
        push!(records, row)
        write(
            joinpath(root, "development.toml"),
            PaperRebuild.r5_market_text(
                Dict("scope"=>"development_not_formal_study", "record"=>records),
            ),
        )
    end
end
