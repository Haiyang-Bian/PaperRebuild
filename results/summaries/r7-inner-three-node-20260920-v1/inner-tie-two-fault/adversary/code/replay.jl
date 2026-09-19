module FrozenR7Inner
using JuMP,TOML,SHA,Dates,UUIDs
const MOI=JuMP.MOI
include("src/core/r7_recovery.jl")
include("src/formulations/r7_recovery.jl")
include("src/verification/r7_recovery.jl")
include("src/algorithms/r7_recovery.jl")
include("src/reporting/r7_recovery.jl")
include("src/core/r7_adversary.jl")
include("src/formulations/r7_adversary.jl")
include("src/verification/r7_adversary.jl")
include("src/algorithms/r7_adversary.jl")
include("src/reporting/r7_adversary.jl")
end
x=FrozenR7Inner.read_r7_adversary(joinpath(@__DIR__,".."))
println(x.result["status"])
