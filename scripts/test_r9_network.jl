using Test, PaperRebuild
VERSION==v"1.12.6" || error("Expected Julia 1.12.6")
isempty(ARGS) || error("usage: test_r9_network.jl")
include(joinpath(@__DIR__, "../test/r9_network.jl"))
