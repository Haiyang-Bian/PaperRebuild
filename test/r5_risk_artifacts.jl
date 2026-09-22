module R5RiskArtifactTests
using Test, TOML
include(joinpath(@__DIR__, "..", "scripts", "r5_risk_artifact_paths.jl"))

@testset "R5 risk artifact path provenance" begin
    # 原样保留求解器诊断；序列化换行不得使普通单词末尾被识别为盘符。
    message = "Getting the attribute cannot be performed because:\nClarabel does not support it."
    io = IOBuffer()
    TOML.print(io, Dict("bound_unavailable" => message))
    @test !r5_risk_has_host_path(String(take!(io)))
    @test !r5_risk_has_host_path(message)
    @test !r5_risk_has_host_path("src/core/r5_risk.jl")
    @test r5_risk_has_host_path(raw"path = 'D:\\Work\\private.toml'")
    @test r5_risk_has_host_path("path = 'd:/Work/private.toml'")
    @test r5_risk_has_host_path("/Users/example/private.toml")
    @test r5_risk_has_host_path("/home/example/private.toml")
end
end
