using Test, TOML, SHA, CSV
length(ARGS)==1 || error("usage: test_r9_network_evidence.jl SUMMARY")
report=abspath(only(ARGS))
include(joinpath(report, "code/scripts/r9_network_evidence.jl"))
const E=R9NetworkEvidence
@testset "R9 network frozen sixteen-method evidence" begin
    @test E.check(report)
    meta=TOML.parsefile(joinpath(report, "evidence.toml"))
    rows=collect(CSV.File(joinpath(report, "summary.csv")))
    @test length(rows)==16 && allunique(x.method for x in rows)
    @test !meta["solver_used_for_replay"] && !meta["complete_thermal_certification"]
    @test all(x->!startswith(x, "logs/"), keys(meta["study_files"]))
    @test all(!r.model_pass || r.has_candidate for r in rows)
    @test all(r.model_pass || isnan(r.system_cost_CNY) for r in rows)
    @test all(
        !r.adopted_physical_pass ||
            r.model_pass&&r.electric_original_pass&&r.heat_pass&&r.ledger_pass for r in rows
    )
    @test all(
        filesize(joinpath(dir, name))<=5*1024^2 for (dir, _, names) in walkdir(report) for
        name in names
    )
    for rel in ("../bad", "/absolute", "C:/outside", "a\\b")
        @test_throws ErrorException E.S.safe(report, rel)
    end
    mktempdir() do dir
        target=joinpath(dir, "copy")
        cp(report, target)
        path=joinpath(target, "summary.csv")
        original=read(path)
        write(path, [original; 0x0a])
        @test_throws ErrorException E.check(target)
        # 即使更新载体哈希，也须从原值重新生成表；不接受篡改后的汇总。
        altered=deepcopy(meta)
        altered["derived_files"]["summary.csv"]=E.S.hashfile(path)
        E.S.toml(joinpath(target, "evidence.toml"), altered)
        @test_throws ErrorException E.check(target)
    end
end
