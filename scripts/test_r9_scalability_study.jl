using Test, PaperRebuild
VERSION==v"1.12.6" || error("Use Julia 1.12.6")
isempty(ARGS) || error("Usage: scripts/test_r9_scalability_study.jl")
include(joinpath(@__DIR__, "../test/r9_scalability_study.jl"))
