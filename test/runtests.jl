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
include("r4_heat_compatibility.jl")
include("r4_thermal.jl")

include("r5_market.jl")
include("r5_dispatch.jl")
include("r5_dispatch_duality.jl")
include("r5_commitment.jl")
include("r5_risk.jl")
include("r5_risk_artifacts.jl")
include("r5_benders.jl")
include("r5_benders_loop.jl")
include("r5_market_payment.jl")
include("r5_strategic.jl")
include("r5_market_selection.jl")
include("r5_execution.jl")
include("r5_execution_scaling.jl")
include("r5_strategic_benders.jl")
include("r6.jl")
include("r6_methods.jl")
