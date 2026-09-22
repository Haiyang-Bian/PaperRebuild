push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Gurobi
include("r9_numerics_study.jl")
length(ARGS) == 1 || error("usage: run_r9_numerics_gurobi.jl FROZEN_BATCH")
R9NumericsStudy.run(only(ARGS), "Gurobi")
