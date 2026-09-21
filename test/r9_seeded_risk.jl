module R9SeededRiskTests
using Test, PaperRebuild, JuMP, HiGHS, TOML
const PR=PaperRebuild
const ROOT=normpath(joinpath(@__DIR__, ".."))
const OPT=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1, "output_flag"=>false)
include(joinpath(ROOT, "scripts/r9_seeded_study.jl"))
const SS=R9SeededStudy
function start_values!(m, x; lp)
    for (v, a) in zip(all_variables(m), x)
        set_start_value(v, a)
    end
    Dict("variables"=>length(x), "test_adapter"=>true, "lp"=>lp)
end

@testset "R9 seeded original model, candidate and archive" begin
    c=R5RiskCase(TOML.parsefile(joinpath(ROOT, "configs/r5/risk/hard_zero.toml")))
    w=solve_r9_common_witness(c; optimizer = OPT, budget_sec = 30)
    @test w["has_candidate"]
    before=deepcopy(c.data)
    for pat in (nothing, zeros(Int, 3))
        r=solve_r9_seeded_risk(
            c,
            w;
            optimizer = OPT,
            seed! = start_values!,
            oracle_optimizer = OPT,
            pattern = pat,
            budget_sec = 60,
        )
        @test r["has_candidate"] && r["status"]=="solver_optimal"
        @test all(
            r["validation"][k] for k in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
        )
        @test r["initial_point_audit"]["pass"]
        @test r["cost_optimization_complete"]
        original=solve_r5_risk(
            c;
            optimizer = OPT,
            oracle_optimizer = OPT,
            pattern = pat,
            budget_sec = 30,
        )
        @test r["solver_objective"]≈original["solver_objective"] atol=1e-7
        @test r["solver_objective"]<r["initial_point_audit"]["objective"]-1e-3
        @test r["source_hashes_at_solve"]==PR.r5_risk_science_hashes()
        @test c.data==before
        mktempdir() do dir
            out=joinpath(dir, "run")
            SS.save_numeric(out, r)
            rr=SS.read_numeric(out)
            @test rr.result["first_stage"]==r["first_stage"]
            @test rr.result["scenarios"]==r["scenarios"]
            @test rr.validation==SS.compact_validation(validate_r5_risk(c, rr.result))
            @test_throws ErrorException SS.save_numeric(out, r)
            open(io->write(io, "# modified"), joinpath(out, "scenario-001.toml"), "a")
            @test_throws ErrorException SS.read_numeric(out)
        end
    end
    tiny=solve_r9_seeded_risk(
        c,
        w;
        optimizer = OPT,
        seed! = start_values!,
        oracle_optimizer = OPT,
        budget_sec = 1e-12,
    )
    @test tiny["status"]=="budget_exhausted_before_build"
    @test !tiny["has_candidate"] && !haskey(tiny, "first_stage")
    failseed(m, x; lp) = error("license unavailable")
    failed=solve_r9_seeded_risk(
        c,
        w;
        optimizer = OPT,
        seed! = failseed,
        oracle_optimizer = OPT,
        budget_sec = 30,
    )
    @test failed["status"]=="license_unavailable" && !failed["has_candidate"]
    @test !haskey(failed, "first_stage") && !failed["cost_optimization_complete"]
    @test_throws ErrorException solve_r9_seeded_risk(
        c,
        w;
        optimizer = OPT,
        seed! = start_values!,
        oracle_optimizer = OPT,
        budget_sec = -1,
    )
    @test_throws ErrorException solve_r9_seeded_risk(
        c,
        w;
        optimizer = OPT,
        seed! = start_values!,
        oracle_optimizer = OPT,
        process_start = time()+100,
    )
end
end
