include("r3_setup.jl")
using Test
include(joinpath(@__DIR__, "..", "test", "r3_boundary.jl"))
include(joinpath(@__DIR__, "..", "test", "r3_baseline.jl"))
