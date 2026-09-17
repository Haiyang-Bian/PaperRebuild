using Test
using PaperRebuild

@testset "Package scaffold (not thesis validation)" begin
    @test PaperRebuild.hello("Julia") == "Hello, Julia"
    @test PaperRebuild.domath(2) == 7
    @test PaperRebuild.domath(1.5) == 6.5
end

include("r1.jl")
include("r2.jl")
include("r3.jl")
include("r3_pg.jl")
include("r3_duals.jl")
include("r3_v2.jl")
