# 只读检查公开数值、配对身份与图源；完整逐式重验另用seal_r9_seeded.jl check。
using Test, TOML, CSV, SHA
include("report_r9_compact.jl")
const R=R9CompactReport
const E=R.E
const S=R.S
length(ARGS)==3 || error("usage: COMPACT_EVIDENCE COMPARISON FIGURES")
evidence, report, figures=abspath.(ARGS)
root=dirname(@__DIR__)
common=joinpath(root, "results/summaries/r9-common-input-20260921-v2")
oldfreeze=joinpath(root, "results/summaries/r9-seeded-input-20260921-v1")
frozen=joinpath(root, "results/summaries/r9-compact-input-20260921-v1")
old=joinpath(root, "results/summaries/r9-seeded-evidence-20260921-v1")
@testset "R9 compact paired evidence and figure original values" begin
    @test E.check(common, frozen, evidence; replay = false)
    @test E.check(common, oldfreeze, old; replay = false)
    a=TOML.parsefile(joinpath(oldfreeze, "manifest.toml"))
    b=TOML.parsefile(joinpath(frozen, "manifest.toml"))
    @test R.check_protocol(a, b)
    m=TOML.parsefile(joinpath(report, "comparison-source.toml"))
    @test m["origin"]=="synthetic" && !m["optimization_performed"]
    for (key, path) in (
        ("old_freeze_sha256", joinpath(oldfreeze, "manifest.toml")),
        ("new_freeze_sha256", joinpath(frozen, "manifest.toml")),
        ("old_evidence_sha256", joinpath(old, "delivery.toml")),
        ("new_evidence_sha256", joinpath(evidence, "delivery.toml")),
        ("common_sha256", joinpath(common, "manifest.toml")),
    )
        @test m[key]==E.hashfile(path)
    end
    @test Set(E.files(report))==union(Set(keys(m["files"])), Set(["comparison-source.toml"]))
    for (p, h) in m["files"]
        @test E.hashfile(E.safe(report, p))==h
        @test filesize(E.safe(report, p))<=5*1024^2
    end
    bundle=S.loadfreeze(common, frozen)
    rows=collect(CSV.File(joinpath(report, "summary.csv")))
    residuals=collect(CSV.File(joinpath(report, "residuals.csv")))
    commitments=collect(CSV.File(joinpath(report, "commitments.csv")))
    @test length(rows)==6
    @test [r.run_id for r in rows]==m["run_ids"]
    @test Set((r.scheme, r.representation) for r in rows)==Set(
        (s, p) for s in ("3A", "3B", "3C") for p in ("original", "r9_compact_v1")
    )
    for row in rows
        dir=joinpath(row.representation=="original" ? old : evidence, row.scheme)
        status=TOML.parsefile(joinpath(dir, "status.toml"))
        @test row.status==status["status"]
        @test row.elapsed_sec==status["elapsed_sec"] && row.budget_pass==status["budget_pass"]
        if !isdir(joinpath(dir, "run"))
            @test !row.checked && !row.has_candidate
            continue
        end
        raw=S.read_numeric(joinpath(dir, "run"))
        r, v=raw.result, raw.validation
        @test row.has_candidate==r["has_candidate"]
        @test row.run_id==r["run_id"]
        @test row.checked==all(v[k] for k in ("model_pass", "risk_pass", "cost_pass"))
        @test row.optimality_pass==v["optimality_pass"]
        @test isequal(row.lower_CNY, get(r, "solver_objective_bound", NaN))
        @test isequal(row.cost_CNY, row.checked ? v["worst_net_cost"] : NaN)
        rc=filter(x->x.scheme==row.scheme && x.representation==row.representation, commitments)
        if row.has_candidate
            c=S.C.riskcase(bundle.state, row.scheme)
            @test row.PV_empirical_energy_MWh≈R.pv_energy(c.data["commitment"]["scenarios"], r) atol=1e-12 rtol=1e-12
            @test length(rc)==length(r["first_stage"]["P_DA_MW"])
            for x in rc, k in ("P_DA_MW", "R_up_MW", "R_down_MW")
                @test getproperty(x, Symbol(k))==r["first_stage"][k][x.hour]
            end
        else
            @test isempty(rc) && isnan(row.PV_empirical_energy_MWh)
        end
        rr=filter(x->x.scheme==row.scheme && x.representation==row.representation, residuals)
        @test Set(x.group for x in rr)==Set(keys(get(v, "groups", Dict())))
        for x in rr
            g=v["groups"][x.group]
            @test x.count==g["count"] && x.failed==g["failed"] && x.normalized==g["max_normalized"]
        end
    end
    f=TOML.parsefile(joinpath(figures, "figure-source.toml"))
    @test f["origin"]=="synthetic" && !f["optimization_performed"]
    @test f["report_sha256"]==E.hashfile(joinpath(report, "comparison-source.toml"))
    @test f["run_ids"]==m["run_ids"]
    @test Set(E.files(figures))==union(
        Set(keys(f["files"])),
        Set(["figure-source.toml", "visual-review.toml"]),
    )
    for (p, h) in f["files"]
        @test E.hashfile(E.safe(figures, p))==h
        @test filesize(E.safe(figures, p))<=5*1024^2
    end
    for name in ("summary.csv", "timings.csv", "commitments.csv", "residuals.csv")
        @test E.hashfile(joinpath(report, name))==E.hashfile(joinpath(figures, name))
    end
    review=TOML.parsefile(joinpath(figures, "visual-review.toml"))
    @test review["status"]=="passed"
    @test review["viewed_png_sha256"]==E.hashfile(joinpath(figures, "F46-compact-comparison.png"))
end
