include("r3_setup.jl")
using Test
include(joinpath(@__DIR__, "..", "test", "r3_audit.jl"))
include(joinpath(@__DIR__, "..", "test", "r3_v3.jl"))
