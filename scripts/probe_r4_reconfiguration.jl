include("r4_setup.jl")
using Test
c=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "reconfiguration", "oracle.toml"))
opt=r4_optimizer(:gurobi)
reference=enumerate_r4_reconfiguration(c; optimizer = r4_optimizer(:clarabel), budget_sec = 60)
@testset "R4 network Gurobi cross-check" begin
    @test reference["certificate_A2"]
    for electric in (:socp, :exact)
        r=solve_r4_reconfiguration(
            c;
            optimizer = opt,
            spec = R4ReconfigurationSpec(; electric),
            budget_sec = 60,
        )
        println(
            electric,
            " | ",
            r["status"],
            " | ",
            get(r, "operating_cost", NaN),
            " | bound=",
            get(r, "objective_bound", NaN),
            " | original=",
            r["validation"]["electric_original_pass"],
        )
        @test r["validation"]["model_pass"]
        @test r["cost_optimization_complete"]
        @test all(haskey(x, "raw_status") for x in r["solves"])
        if electric==:socp
            @test abs(r["operating_cost"]-reference["best_model_cost"])/max(
                1,
                abs(reference["best_model_cost"]),
            )<=1e-4
        else
            @test r["validation"]["electric_original_pass"]
        end
    end
end
