# 商用求解器使用既有独立环境，CSV等报告依赖从根锁定环境加载。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Gurobi
include("r9_pv_study.jl")
length(ARGS)==1 || error("usage: run_r9_gurobi.jl FROZEN_BATCH")
R9PVStudy.run(only(ARGS), "Gurobi")
