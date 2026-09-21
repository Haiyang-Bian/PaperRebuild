# 冻结与来源验证，不执行规模优化。
using Test, TOML
include(joinpath(@__DIR__, "r9_trading_study.jl"))
isempty(ARGS) || error("usage: test_r9_trading_study.jl")
@testset "R9 four-method freeze and source identity" begin
    protocol=TOML.parsefile(joinpath(@__DIR__, "../configs/r9/trading-study.toml"))
    @test R9TradingStudy.validate_protocol(protocol)
    for edit in (
        p->(p["budget_sec"]=601),
        p->pop!(p["methods"]),
        p->(p["gurobi"]["MIPGap"]=0.1),
        p->(p["integer_rule"]="relaxed"),
    )
        changed=deepcopy(protocol)
        edit(changed)
        @test_throws ErrorException R9TradingStudy.validate_protocol(changed)
    end
    for rel in ("../other", "code//file", "/absolute")
        @test_throws ErrorException R9TradingStudy.safe("study", rel)
    end
    mktempdir() do temporary
        path=joinpath(temporary, "study")
        meta=R9TradingStudy.freeze(path)
        @test R9TradingStudy.check_inputs(path)==meta
        @test meta["input_sha256"]==protocol["expected_input_sha256"]
        @test !meta["optimization_performed_at_freeze"]
        @test !ispath(joinpath(path, "runs"))
        @test_throws ErrorException R9TradingStudy.freeze(path)
        manifest=joinpath(path, "manifest.toml")
        original=read(manifest)
        firstpath=first(sort(collect(keys(meta["source_hashes"]))))
        changed=deepcopy(meta)
        changed["source_hashes"][firstpath]="0"^64
        R9TradingStudy.toml(manifest, changed)
        @test_throws ErrorException R9TradingStudy.check_inputs(path)
        write(manifest, original)
        unexpected=joinpath(path, "code", "unexpected-test.txt")
        write(unexpected, "not a source")
        @test_throws ErrorException R9TradingStudy.check_inputs(path)
        rm(unexpected)
        input=joinpath(path, "input.toml")
        open(io->write(io, "\n# changed\n"), input, "a")
        @test_throws ErrorException R9TradingStudy.check_inputs(path)
    end
end
