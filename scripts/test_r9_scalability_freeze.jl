using Test, TOML
include("r9_scalability_study.jl")
const STUDY=R9ScalabilityStudy
VERSION==v"1.12.6" || error("Use Julia 1.12.6")
length(ARGS)==1 || error("Usage: test_r9_scalability_freeze.jl FROZEN_STUDY")
source=abspath(only(ARGS))
meta=STUDY.check(source)
@testset "F13 relocated frozen input and zero-budget records, without optimization" begin
    mktempdir() do temp
        relocated=joinpath(temp, "relocated")
        cp(source, relocated)
        # 测试目录只包含未求解快照；过期外层时钟故意用于验证无求解记录路径。
        @test !ispath(joinpath(relocated, "runs"))
        lib=STUDY.library(joinpath(relocated, "code"))
        @test STUDY.check(relocated; lib)==meta
        for id in ("ag8-fixed-central", "ag8-fixed-admm")
            receipt=STUDY.run_method(relocated, id; process_start = STUDY.clock()-421)
            @test receipt["status"]=="record_saved"
            r=STUDY.read_method(relocated, id; lib, meta)
            if id=="ag8-fixed-admm"
                @test r.result["built_block_count"]==0 && isempty(r.result["trace"])
                @test r.validation["record_pass"] && !r.validation["best_model_found"]
            else
                @test only(r.result["stages"])["solver"]=="not_started"
                @test !haskey(only(r.result["stages"]), "values")
            end
        end
        bad=deepcopy(meta)
        delete!(bad["files"], "inputs/ag16-mapping.toml")
        STUDY.toml(joinpath(relocated, "manifest.toml"), bad)
        @test_throws ErrorException STUDY.check(relocated; lib)
        STUDY.toml(joinpath(relocated, "manifest.toml"), meta)
        path=joinpath(relocated, "inputs/ag16.toml")
        original=read(path)
        open(io->write(io, "\n# altered input bytes\n"), path, "a")
        @test_throws ErrorException STUDY.check(relocated; lib)
        # 更新外层清单哈希仍不能伪装成原准备包中的输入。
        bad=deepcopy(meta)
        bad["files"]["inputs/ag16.toml"]=STUDY.hashfile(path)
        STUDY.toml(joinpath(relocated, "manifest.toml"), bad)
        @test_throws ErrorException STUDY.check(relocated; lib)
        write(path, original)
    end
end
