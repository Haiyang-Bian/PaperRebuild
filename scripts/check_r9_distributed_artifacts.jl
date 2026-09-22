# 产物检查不求解；完整数值重放另用 r9_distributed_evidence.jl check。
using CSV, TOML, SHA, Test
length(ARGS) in (2, 3) ||
    error("usage: check_r9_distributed_artifacts.jl EVIDENCE FIGURES [DOC_ASSETS]")
report, figures=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
meta=TOML.parsefile(joinpath(report, "evidence.toml"))
config=TOML.parsefile(joinpath(figures, "figure-config.toml"))
summary=collect(CSV.File(joinpath(report, "summary.csv")))
trajectory=collect(CSV.File(joinpath(report, "iterations.csv")))
comparisons=collect(CSV.File(joinpath(report, "comparisons.csv")))
quality_path=joinpath(report, "objective_reports.csv")
quality=isfile(quality_path) ? collect(CSV.File(quality_path)) : []
@testset "R9 distributed figure provenance and result boundaries" begin
    @test meta["origin"]==config["origin"]=="synthetic"
    @test !meta["solver_used_for_replay"] && !config["optimization_performed"]
    @test !meta["complete_thermal_certification"] && !meta["bargaining"]
    @test config["input_manifest_sha256"]==meta["study_manifest_sha256"]
    @test config["runs"]==[s.method for s in summary]
    @test length(unique(config["runs"]))==length(summary)
    for (rel, digest) in meta["derived_files"]
        @test hashfile(joinpath(report, rel))==digest
    end
    for (rel, digest) in config["files"]
        @test hashfile(joinpath(figures, rel))==digest
        if endswith(rel, ".csv")
            @test read(joinpath(figures, rel))==read(joinpath(report, rel))
        end
        if length(ARGS)==3
            @test read(joinpath(figures, rel))==read(joinpath(ARGS[3], rel))
        end
    end
    if length(ARGS)==3
        @test read(joinpath(figures, "figure-config.toml"))==read(
            joinpath(ARGS[3], "figure-config.toml"),
        )
    end
    for s in summary
        if s.algorithm=="admm"
            rows=filter(x->x.method==s.method, trajectory)
            if ismissing(s.iterations)
                @test !s.record_pass && isempty(rows)
            else
                @test length(rows)==s.iterations
                @test [x.iteration for x in rows]==collect(1:s.iterations)
                @test s.model_candidate==any(x->x.model_pass, rows)
                @test s.original_candidate==any(x->x.original_pass, rows)
            end
        end
        @test s.process_budget_pass==(s.process_elapsed_sec<=600.0)
        @test s.model_candidate || isnan(s.best_model_cost_CNY)
        @test s.original_candidate || isnan(s.best_original_cost_CNY)
    end
    for pair in comparisons
        central=only(s for s in summary if s.method==pair.central)
        distributed=only(s for s in summary if s.method==pair.distributed)
        @test pair.candidate_comparison_available==(
            central.model_candidate && distributed.model_candidate
        )
        @test pair.candidate_difference_is_not_optimality_gap
        if !pair.candidate_comparison_available
            @test isnan(pair.distributed_minus_central_CNY) && isnan(pair.reference_relative_gap)
        end
    end
    for q in quality
        @test !q.subproblem_accuracy_certified
        if !ismissing(q.checked_blocks) && q.checked_blocks>0
            @test q.reported_scalar_pass==(q.mismatch_blocks==0)
            @test 0<=q.mismatch_blocks<=q.checked_blocks
        else
            @test ismissing(q.reported_scalar_pass)
        end
    end
end
