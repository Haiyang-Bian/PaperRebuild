# 只核对冻结数值和图源，不重新优化；完整物理重验有独立入口。
using Test, TOML, SHA, CSV
include("seal_r9_seeded.jl")
const E=R9SeededEvidence
root=dirname(@__DIR__)
common=joinpath(root, "results/summaries/r9-common-input-20260921-v2")
prior=joinpath(root, "results/summaries/r9-common-evidence-20260921-v1")
frozen=joinpath(root, "results/summaries/r9-seeded-input-20260921-v1")
evidence=joinpath(root, "results/summaries/r9-seeded-evidence-20260921-v1")
structure=joinpath(root, "results/summaries/r9-seeded-structure-20260921-v1")
hashfile(p) = bytes2hex(sha256(read(p)))
@testset "R9 seeded negative results, original values and F45 evidence" begin
    @test E.check(common, frozen, evidence; replay = false)
    m=TOML.parsefile(joinpath(frozen, "manifest.toml"))
    @test hashfile(joinpath(frozen, "manifest.toml"))==strip(
        read(joinpath(frozen, "manifest.sha256"), String),
    )
    @test Set(E.files(frozen))==union(
        Set(keys(m["files"])),
        Set(["manifest.toml", "manifest.sha256"]),
    )
    for (rel, h) in m["files"]
        @test hashfile(E.safe(frozen, rel))==h
    end
    sm=TOML.parsefile(joinpath(structure, "files.toml"))
    @test Set(E.files(structure))==union(Set(keys(sm)), Set(["files.toml"]))
    for (rel, h) in sm
        @test hashfile(E.safe(structure, rel))==h
    end
    a=TOML.parsefile(joinpath(structure, "structure.toml"))
    r=TOML.parsefile(joinpath(evidence, "3A/run/result.toml"))
    @test a["variables"]==r["initial_point_audit"]["variables"]
    @test a["constraints"]==sum(g["count"] for g in values(r["initial_point_audit"]["groups"]))
    @test a["original_result_sha256"]==hashfile(joinpath(evidence, "3A/run/result.toml"))
    @test !a["performance_cause_proved"] && !a["optimization_performed"]
    @test a["common_sha256"]==hashfile(joinpath(common, "manifest.toml"))
    @test a["declared_bound_rows"]==sum(e["declared_bound_rows"] for e in values(a["entries"]))
    @test a["explicit_cost_row_terms"]==a["scenarios"]*sum(
        e["nonzero_cost_terms"] for e in values(a["entries"])
    )
    for version in ("v1", "v2")
        fig=joinpath(root, "results/summaries/r9-seeded-figures-20260921-"*version)
        f=TOML.parsefile(joinpath(fig, "figure-source.toml"))
        @test f["origin"]=="synthetic" && !f["optimization_performed"]
        @test f["evidence_sha256"]==hashfile(joinpath(evidence, "delivery.toml"))
        @test f["common_sha256"]==hashfile(joinpath(prior, "delivery.toml"))
        @test Set(E.files(fig))==union(
            Set(keys(f["files"])),
            Set(["figure-source.toml", "visual-review.toml"]),
        )
        for (rel, h) in f["files"]
            @test hashfile(E.safe(fig, rel))==h
        end
        rows=collect(CSV.File(joinpath(fig, "summary.csv")))
        @test [x.scheme for x in rows]==["3A", "3B", "3C"]
        @test [x.run_id for x in rows]==f["run_ids"]
        for row in rows
            s=TOML.parsefile(joinpath(evidence, row.scheme, "status.toml"))
            r=TOML.parsefile(joinpath(evidence, row.scheme, "run/result.toml"))
            v=TOML.parsefile(joinpath(evidence, row.scheme, "run/validation.toml"))
            @test row.status==s["status"]==r["status"]
            @test row.has_candidate==s["has_candidate"]==r["has_candidate"]
            @test row.elapsed_sec==s["elapsed_sec"] && row.budget_pass==s["budget_pass"]
            @test row.checked==(v["model_pass"] && v["risk_pass"] && v["cost_pass"])
            @test row.optimality_pass==v["optimality_pass"]
            @test row.solver_lower_CNY==get(r, "solver_objective_bound", NaN)
            if row.has_candidate
                @test row.feasible_cost_CNY==v["worst_net_cost"]
                @test row.relative_gap==v["relative_gap"] && row.valid_bound==v["valid_bound"]
            else
                @test isnan(row.feasible_cost_CNY) && !row.checked && !row.valid_bound
            end
        end
        commitments=collect(CSV.File(joinpath(fig, "commitments.csv")))
        @test length(commitments)==48
        for scheme in ("3B", "3C")
            r=TOML.parsefile(joinpath(evidence, scheme, "run/result.toml"))
            rows=filter(x->x.scheme==scheme, commitments)
            @test [x.hour for x in rows]==1:24
            for row in rows, key in ("P_DA_MW", "R_up_MW", "R_down_MW")
                @test getproperty(row, Symbol(key))==r["first_stage"][key][row.hour]
            end
        end
        residuals=collect(CSV.File(joinpath(fig, "residuals.csv")))
        @test all(x.scheme!="3A" for x in residuals)
        for scheme in ("3B", "3C")
            v=TOML.parsefile(joinpath(evidence, scheme, "run/validation.toml"))
            rows=filter(x->x.scheme==scheme, residuals)
            @test Set(x.group for x in rows)==Set(keys(v["groups"]))
            for row in rows
                g=v["groups"][row.group]
                @test row.count==g["count"] && row.failed==g["failed"]
                @test row.normalized==g["max_normalized"]
            end
        end
        review=TOML.parsefile(joinpath(fig, "visual-review.toml"))
        if version=="v1"
            @test review["status"]=="needs_layout_fix"
        else
            @test review["status"]=="passed"
            png=hashfile(joinpath(fig, "F45-seeded-risk.png"))
            @test review["viewed_png_sha256"]==png
            @test hashfile(
                joinpath(root, "docs/src/assets/r9-seeded-20260921-v2/F45-seeded-risk.png"),
            )==png
        end
    end
end
