module FrozenR7Transport
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
include("src/core/r7_transport.jl")
include("src/formulations/r7_transport.jl")
include("src/verification/r7_transport.jl")
include("src/algorithms/r7_transport.jl")
include("src/reporting/r7_transport.jl")
end
x=FrozenR7Transport.read_r7_transport_recovery(joinpath(@__DIR__,".."))
println(x.result["status"]," model=",x.validation["model_pass"])
