module FrozenR7
using JuMP,TOML,SHA,Dates,UUIDs
const MOI=JuMP.MOI
include("src/core/r7_recovery.jl")
include("src/formulations/r7_recovery.jl")
include("src/verification/r7_recovery.jl")
include("src/algorithms/r7_recovery.jl")
include("src/reporting/r7_recovery.jl")
end
x=FrozenR7.read_r7_recovery(joinpath(@__DIR__,".."))
println(x.result["status"], " model=", x.validation["model_pass"])
