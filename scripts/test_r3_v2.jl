include("r3_setup.jl")
using Test
include(joinpath(@__DIR__, "..", "test", "r3_duals.jl"))
include(joinpath(@__DIR__, "..", "test", "r3_v2.jl"))
include(joinpath(@__DIR__, "..", "test", "r3_optional_attributes.jl"))
