# 交付检查只读已有数值；完整物理重读由封存audit-source.jl执行。
using Test, TOML, SHA, CSV
include("seal_r9_common_witness.jl")
const E=R9CommonEvidence
root=dirname(@__DIR__)
input=joinpath(root, "results/summaries/r9-common-input-20260921-v2")
evidence=joinpath(root, "results/summaries/r9-common-evidence-20260921-v1")
start=joinpath(root, "results/summaries/r9-common-start-20260921-v1")
fig=joinpath(root, "results/summaries/r9-common-figures-20260921-v1")
hashfile(p) = bytes2hex(sha256(read(p)))
@testset "R9 common frozen inputs, start audit and F44 original values" begin
    @test E.check(input, evidence; replay = false)
    for version in ("v1", "v2")
        p=joinpath(root, "results/summaries/r9-common-input-20260921-"*version)
        m=TOML.parsefile(joinpath(p, "manifest.toml"))
        @test hashfile(joinpath(p, "manifest.toml"))==strip(
            read(joinpath(p, "manifest.sha256"), String),
        )
        @test Set(E.files(p))==union(
            Set(keys(m["files"])),
            Set(["manifest.toml", "manifest.sha256"]),
        )
        for (rel, h) in m["files"]
            @test hashfile(E.safe(p, rel))==h
        end
    end
    old=TOML.parsefile(joinpath(evidence, "construction-status.toml"))
    @test old["status"]=="execution_error"
    @test old["freeze_sha256"]==hashfile(
        joinpath(root, "results/summaries/r9-common-input-20260921-v1/manifest.toml"),
    )
    entries=TOML.parsefile(joinpath(start, "files.toml"))
    @test Set(E.files(start))==union(Set(keys(entries)), Set(["files.toml"]))
    for (rel, h) in entries
        @test hashfile(E.safe(start, rel))==h
    end
    s=TOML.parsefile(joinpath(start, "status.toml"))
    a=TOML.parsefile(joinpath(start, "linear-audit.toml"))
    @test s["status"]=="original_model_start_checked"
    @test s["linear_start_pass"] && a["pass"] && s["budget_pass"]
    @test !s["optimization_performed"] && !a["physical_A1_substitute"]
    @test s["variables"]==a["variables"]==1061074
    @test s["constraints"]==sum(g["count"] for g in values(a["groups"]))==2735895
    @test s["parent_witness_sha256"]==hashfile(joinpath(evidence, "run/witness.toml"))
    @test s["parent_run_status_sha256"]==hashfile(joinpath(evidence, "run/status.toml"))
    @test s["parent_freeze_sha256"]==hashfile(joinpath(input, "manifest.toml"))
    @test a["tolerance"]==1e-8 &&
          all(g["max_normalized"]<=a["tolerance"] for g in values(a["groups"]))
    @test s["elapsed_sec"]<=s["budget_sec"]==600.0
    f=TOML.parsefile(joinpath(fig, "figure-source.toml"))
    @test !f["optimization_performed"] && f["origin"]=="synthetic"
    @test f["evidence_sha256"]==hashfile(joinpath(evidence, "delivery.toml"))
    @test f["input_sha256"]==hashfile(joinpath(input, "manifest.toml"))
    for (rel, h) in f["files"]
        @test hashfile(E.safe(fig, rel))==h
    end
    w=TOML.parsefile(joinpath(evidence, "run/witness.toml"))
    v=TOML.parsefile(joinpath(evidence, "run/validation-3A.toml"))
    traj=collect(CSV.File(joinpath(fig, "trajectories.csv")))
    @test length(traj)==24
    for (t, row) in enumerate(traj)
        @test row.hour==t
        @test row.P_PCC_MW==only(w["values"]["P_PCC"])[t]
        @test row.R_up_MW==w["first_stage"]["R_up_MW"][t]
        @test row.R_down_MW==w["first_stage"]["R_down_MW"][t]
        @test row.T_min_K==minimum(b[t] for b in w["values"]["τ_IN"])
        @test row.T_max_K==maximum(b[t] for b in w["values"]["τ_IN"])
    end
    rr=collect(CSV.File(joinpath(fig, "residuals.csv")))
    @test length(rr)==length(v["groups"])
    for row in rr
        g=v["groups"][row.group]
        @test row.normalized==g["max_normalized"]
        @test row.count==g["count"] && row.failed==g["failed"]
        @test row.display==max(row.normalized, f["residual_display_floor"])
    end
    png=hashfile(joinpath(fig, "F44-common-witness.png"))
    review=TOML.parsefile(joinpath(fig, "visual-review.toml"))
    @test review["viewed_png_sha256"]==png
    @test hashfile(joinpath(root, "docs/src/assets/r9-common-20260921-v1/F44-common-witness.png"))==png
    @test f["run_id"]==w["run_id"]
end
