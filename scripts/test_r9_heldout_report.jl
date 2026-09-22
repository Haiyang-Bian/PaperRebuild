# 报告层数学和拒绝伪造声明的检查；不重新优化任何测试日。
using Test, TOML
include("report_r9_evaluation.jl")
include("check_r9_heldout_artifacts.jl")
const RH=R9HeldoutReport
const RC=R9HeldoutArtifactCheck
@testset "R9 CNY whole-day descriptive cost interval" begin
    statistics=Dict("bootstrap_seed"=>2026092104, "bootstrap_replicates"=>2000, "confidence"=>0.95)
    constant=RH.cost_mean_interval(fill(12.5, 10), statistics)
    @test constant["lower_CNY"]==constant["upper_CNY"]==constant["mean_CNY"]==12.5
    @test constant["currency"]=="CNY" && !constant["is_optimality_bound"]
    incomplete=RH.cost_mean_interval([12.5, NaN], statistics)
    @test incomplete["status"]=="missing_costs" && !haskey(incomplete, "mean_CNY")
    costs=[10.0, 40.0, -20.0, 5.0]
    base=RH.cost_mean_interval(costs, statistics)
    shifted=RH.cost_mean_interval(3.0 .* costs .+ 100.0, statistics)
    @test all(
        k->isapprox(shifted[k], 3base[k]+100; atol = 1e-12),
        ["lower_CNY", "upper_CNY", "mean_CNY"],
    )
    @test base==RH.cost_mean_interval(costs, statistics)
end
if !isempty(ARGS)
    length(ARGS)==2 || error("usage: test_r9_heldout_report.jl [FREEZE REPORT]")
    frozen, report=abspath.(ARGS)
    @testset "R9 report refuses false scientific scope and tampering" begin
        @test RC.check(frozen, report)
        original=TOML.parsefile(joinpath(report, "summary.toml"))
        for key in ("original_ac_power_flow_certified", "nonzero_reserve_service_certified")
            mktempdir() do scratch
                copy=joinpath(scratch, "report")
                cp(report, copy)
                changed=deepcopy(original)
                changed[key]=true
                RH.toml(joinpath(copy, "summary.toml"), changed)
                m=TOML.parsefile(joinpath(copy, "artifacts.toml"))
                m["files"]["summary.toml"]=RH.hashfile(joinpath(copy, "summary.toml"))
                RH.toml(joinpath(copy, "artifacts.toml"), m)
                @test_throws ErrorException RC.check(frozen, copy)
            end
        end
        mktempdir() do scratch
            copy=joinpath(scratch, "report")
            cp(report, copy)
            @test RC.check(frozen, copy)
            write(joinpath(copy, "daily.csv"), "altered\n")
            @test_throws ErrorException RC.check(frozen, copy)
        end
    end
end
