using Test, JuMP
root=dirname(@__DIR__)
push!(LOAD_PATH, joinpath(root, "tools/solvers"))
pushfirst!(DEPOT_PATH, joinpath(root, ".julia"))
include("r9_gurobi_start.jl")
using .R9GurobiStart: Gurobi
env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
@testset "R9 native LP/MIP initial point coordinates and attributes" begin
    for lp in (true, false)
        m=Model(()->Gurobi.Optimizer(env))
        set_silent(m)
        @variable(m, x>=0)
        @variable(m, y>=0)
        lp || set_binary(x)
        @constraint(m, x+y>=1)
        @objective(m, Min, x+2y)
        if lp
            set_attribute(m, "Method", 0)
            set_attribute(m, "LPWarmStart", 2)
        end
        report=R9GurobiStart.set_native_start!(m, [0.0, 1.0]; lp)
        @test report["exact_readback"]
        @test report["attribute"]==(lp ? "PStart" : "Start")
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test objective_value(m)≈1.0 atol=1e-9
        @test value(x)≈1.0 atol=1e-9
        @test value(y)≈0.0 atol=1e-9
        @test_throws ErrorException R9GurobiStart.set_native_start!(m, [0.0]; lp)
        @test_throws ErrorException R9GurobiStart.set_native_start!(m, [NaN, 0.0]; lp)
        lp || @test_throws ErrorException R9GurobiStart.set_native_start!(m, [0.0, 1.0]; lp = true)
    end
end
