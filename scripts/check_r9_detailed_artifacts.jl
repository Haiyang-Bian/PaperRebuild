# 已冻结原值的轻量交付检查；数值回放使用独立 --replay 入口，不重复优化。
using CSV, TOML, SHA, Test
include("r9_handoff_evidence.jl")
include("r9_detailed_preplan_evidence.jl")
root = dirname(@__DIR__)
handoff = joinpath(root, "results/summaries/r9-handoff-evidence-20260922-v1")
detailed = joinpath(root, "results/summaries/r9-detailed-preplan-evidence-20260922-v1")
input = joinpath(root, "results/summaries/r9-detailed-preplan-input-20260922-v1")
figure = joinpath(root, "docs/src/assets/r9-handoff-v2")
hashfile(p) = bytes2hex(sha256(read(p)))
safe_path(p) = !isabspath(p) && !occursin('\\', p) && !occursin(':', p) && !(".." in split(p, '/'))
function checked_manifest(dir, filename)
    m = TOML.parsefile(joinpath(dir, filename))["files"]
    actual = R9DetailedPreplanEvidence.files(dir)
    delete!(actual, filename)
    @test actual == m
    for (p, hash) in m
        @test safe_path(p)
        @test occursin(r"^[0-9a-f]{64}$", hash)
        @test filesize(joinpath(dir, p)) <= 5 * 1024^2
    end
    m
end
@testset "R9 detailed evidence, negative statuses and F49 sources" begin
    @test R9HandoffEvidence.check(handoff)
    @test R9DetailedPreplanEvidence.check(detailed)
    for (dir, file) in (
        (handoff, "artifacts.toml"),
        (detailed, "artifacts.toml"),
        (input, "files.toml"),
        (figure, "artifacts.toml"),
    )
        checked_manifest(dir, file)
    end
    @test hashfile(joinpath(input, "files.toml")) ==
          "10f9a4a8362eae11426a8fef1ce85b4576250bb3010f8ab62f37dae1b5217258"
    rows = collect(CSV.File(joinpath(detailed, "summary.csv")))
    @test length(rows) == 8
    primary = only(filter(r -> r.mode == "penalty" && r.stage == "primary", rows))
    @test primary.model_pass && primary.conditional_gap_pass && !primary.threshold_pass
    @test isapprox(
        primary.solver_objective,
        primary.normal_cost_CNY + primary.penalty_CNY;
        atol = 1e-6,
    )
    fixed = filter(r -> r.mode == "penalty" && r.stage != "primary", rows)
    @test length(fixed) == 3
    @test all(r -> r.model_pass && r.handoff_necessary_pass && r.conditional_gap_pass, fixed)
    @test all(r -> r.critical_loss_MWh > 2 && !r.threshold_pass, fixed)
    @test all(r -> r.budget_pass && r.whole_method_sec <= 600, rows)
    blocked = filter(r -> r.mode == "threshold", rows)
    @test only(filter(r -> r.stage == "primary", blocked)).status == "infeasible_certified"
    @test all(r -> !r.model_pass && isnan(r.critical_loss_MWh), blocked)
    @test all(
        r -> r.status == "primary_candidate_unavailable" && r.run_id == "",
        filter(r -> r.stage != "primary", blocked),
    )
    comparison = collect(CSV.File(joinpath(detailed, "comparison.csv")))
    @test length(comparison) == 3 && all(r -> r.fixed_inputs_shared, comparison)
    @test count(r -> r.loss_reduction_MWh > 0, comparison) == 1
    @test count(r -> r.loss_reduction_MWh < 0, comparison) == 2
    for r in comparison
        @test isapprox(
            r.loss_reduction_MWh,
            r.old_detailed_loss_MWh - r.new_detailed_loss_MWh;
            atol = 1e-12,
        )
        @test isapprox(r.new_normal_cost_CNY - r.old_normal_cost_CNY, 715.508569742; atol = 1e-6)
    end
    fc = TOML.parsefile(joinpath(figure, "figure-config.toml"))
    @test fc["source_artifacts_sha256"] == hashfile(joinpath(handoff, "artifacts.toml"))
    @test fc["synthetic_replacement_inputs"] && !fc["optimization_performed"]
    data = collect(CSV.File(joinpath(figure, "source.csv")))
    @test length(data) == 8 && Set(r.parent_run_id for r in data) == Set(fc["run_ids"])
    @test all(r -> r.tolerance_K == 1e-4 && r.pipe == 37 && r.inlet_independent, data)
    candidate = filter(r -> r.label == "candidate", data)
    @test isapprox(sum(r.outlet_low_K for r in candidate) / 4, 343.15; atol = 1e-10)
    @test isapprox(
        343.15 - minimum(r.outlet_low_K for r in candidate),
        0.08848988586544237;
        atol = 1e-10,
    )
    # 只在新的临时副本制造篡改，原始证据保持字节不变。
    mktempdir() do scratch
        copydir = joinpath(scratch, "evidence")
        cp(detailed, copydir)
        @test R9DetailedPreplanEvidence.check(copydir)
        write(joinpath(copydir, "summary.csv"), "altered\n")
        @test_throws ErrorException R9DetailedPreplanEvidence.check(copydir)
    end
end
