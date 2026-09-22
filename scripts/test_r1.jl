using Test, PaperRebuild

VERSION == v"1.12.6" || error("Use Julia 1.12.6")
isempty(ARGS) || error("Usage: scripts/test_r1.jl")

# 入门任务只复用现有R1测试；完整隔离回归仍由scripts/test.jl负责。
include(joinpath(@__DIR__, "..", "test", "r1.jl"))
include(joinpath(@__DIR__, "..", "test", "r1_entry.jl"))
@test !any(p -> p.name == "Gurobi", keys(Base.loaded_modules))
println("R1 beginner tests passed without loading Gurobi.")
