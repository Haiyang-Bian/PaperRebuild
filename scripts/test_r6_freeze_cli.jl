using Test
include("freeze_r6_data.jl")

@testset "R6 freeze CLI Julia command construction" begin
    root = normpath(joinpath(@__DIR__, ".."))
    @test samefile(readchomp(r6_git_cmd(root, "rev-parse", "--show-toplevel")), root)
    @test length(readchomp(r6_git_cmd(root, "rev-parse", "HEAD"))) == 40
    mktempdir(; prefix = "r6 路径 ") do tmp
        @test startswith(readchomp(r6_git_cmd(tmp, "--version")), "git version ")
    end
end
