using Test
include("freeze_r6_physical.jl")
include("pilot_r6_training.jl")
include("r6_pilot_report.jl")

@testset "R6 workflow immutable physical construction" begin
    root=normpath(joinpath(@__DIR__, ".."))
    frozen=load_r6_physical_case(joinpath(root, "configs", "r6", "daily-small.toml"))
    mktempdir() do dir
        path=joinpath(dir, "中文 物理配置.toml")
        r6_freeze_physical(path)
        @test load_r6_physical_case(path).sha256==frozen.sha256
        original=read(path)
        @test_throws ErrorException r6_freeze_physical(path)
        @test read(path)==original
        # 现存目录必须在读取数据和创建求解器之前拒绝，防止重跑覆盖证据。
        @test_throws ErrorException r6_training_pilot(dir)
    end
end
