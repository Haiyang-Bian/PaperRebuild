push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Gurobi
include("r8_energy_study.jl")
length(ARGS)==1 || error("usage: run_r8_energy_gurobi.jl FROZEN_BATCH")
r8_energy_run_group(abspath(only(ARGS)), "Gurobi")
