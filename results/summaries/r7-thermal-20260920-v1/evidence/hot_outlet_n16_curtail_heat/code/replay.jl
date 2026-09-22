module FrozenR7Thermal
using JuMP,TOML,SHA,Dates,UUIDs
const MOI=JuMP.MOI
include("src/core/r7_recovery.jl")
include("src/formulations/r7_recovery.jl")
include("src/verification/r7_recovery.jl")
include("src/algorithms/r7_recovery.jl")
include("src/reporting/r7_recovery.jl")
include("src/networks/r7_pipe_state.jl")
include("src/core/r7_thermal.jl")
include("src/formulations/r7_thermal.jl")
include("src/verification/r7_thermal.jl")
include("src/algorithms/r7_thermal.jl")
include("src/reporting/r7_thermal.jl")
end
x=FrozenR7Thermal.read_r7_thermal_reconstruction(joinpath(@__DIR__,".."))
println(x.result["status"])
