include(joinpath(@__DIR__, "..", "test", "r4_heat_compatibility.jl"))
if "--gurobi" in ARGS
    include("r4_setup.jl")
    c, p, _=heat_handcase()
    @testset "R4-HC nonlinear solver witness" begin
        r=Base.invokelatest(
            reconstruct_r4_heat,
            c,
            p;
            optimizer = r4_optimizer(:gurobi),
            budget_sec = 60.0,
        )
        haskey(r, "error") && println(r["error"])
        @test r["status"]=="compatible_candidate"
        @test r["validation"]["pass"]
        @test r["validation"]["temperature_checked"]
    end
end
