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
include("r3_optional_attributes.jl")
include("r3_audit.jl")
include("r3_v3.jl")
include("r3_boundary.jl")
include("r3_baseline.jl")
include("r4.jl")
include("r4_baseline.jl")
include("r4_bargaining.jl")
include("r4_tspa.jl")
include("r4_distributed.jl")
include("r4_discrete.jl")
include("r4_reconfiguration.jl")
