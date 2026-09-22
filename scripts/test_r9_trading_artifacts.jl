using Test, TOML, SHA, CSV
length(ARGS)==1 || error("usage: test_r9_trading_artifacts.jl SUMMARY")
report=abspath(only(ARGS))
include(joinpath(report, "code/scripts/r9_trading_evidence.jl"))
const E=R9TradingEvidence
@testset "R9 frozen four-method evidence and exact capacity contradiction" begin
    @test E.check(report)
    meta=TOML.parsefile(joinpath(report, "evidence.toml"))
    summary=collect(CSV.File(joinpath(report, "summary.csv")))
    stages=collect(CSV.File(joinpath(report, "stages.csv")))
    @test length(summary)==4 && allunique(x.method for x in summary)
    @test all(
        !x.model_pass && !x.electric_original_pass && isnan(x.system_cost_CNY) for x in summary
    )
    @test all(x.process_budget_pass && x.method_budget_pass for x in summary)
    @test length(stages)==20
    local_rows=filter(x->x.stage=="local", stages)
    @test length(local_rows)==16 && all(x.model_pass for x in local_rows)
    @test TOML.parsefile(joinpath(report, "capacity.toml"))["violations"]==0
    proof=TOML.parsefile(joinpath(report, "literal-proof.toml"))
    @test proof["positive_deficit"] && !proof["solver_used"]
    @test proof["deficit_MW"]≈0.08011921641428904 atol=1e-12
    @test proof["exact_deficit"]==TOML.parsefile(joinpath(report, "heat-cut-proof.toml"))["exact_deficit"]
    @test length(meta["diagnostics"])==2
    @test all(
        filesize(joinpath(dir, name))<=5*1024^2 for (dir, _, names) in walkdir(report) for
        name in names
    )
    for rel in ("../bad", "/absolute", "C:/outside", "a\\b")
        @test_throws ErrorException E.S.safe(report, rel)
    end
    mktempdir() do dir
        copy=joinpath(dir, "evidence")
        cp(report, copy)
        path=joinpath(copy, "summary.csv")
        original=read(path)
        write(path, [original; 0x0a])
        @test_throws ErrorException E.check(copy)
        write(path, original)
        object=meta["study_files"]["runs/central-socp/raw-result.toml"]
        path=joinpath(copy, "objects", object)
        original=read(path)
        altered=Base.copy(original)
        altered[1]=xor(altered[1], 0x01)
        write(path, altered)
        @test_throws ErrorException E.check(copy)
        write(path, original)
        # 更新载体哈希也不能把已保存的正缺口改成零。
        path=joinpath(copy, "literal-proof.toml")
        changed=TOML.parsefile(path)
        changed["deficit_MW"]=0.0
        E.S.toml(path, changed)
        newmeta=deepcopy(meta)
        newmeta["derived_files"]["literal-proof.toml"]=E.S.hashfile(path)
        E.S.toml(joinpath(copy, "evidence.toml"), newmeta)
        @test_throws ErrorException E.check(copy)
    end
end
