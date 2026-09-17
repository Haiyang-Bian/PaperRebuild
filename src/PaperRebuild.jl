module PaperRebuild

using JuMP
using TOML, SHA, Dates, UUIDs, CSV

include("components/devices.jl")
include("networks/fixed_flow_heat.jl")
include("core/case.jl")
include("formulations/r1.jl")
include("verification/r1.jl")
include("reporting/runs.jl")
include("networks/water_mass.jl")
include("core/r2_case.jl")
include("formulations/r2.jl")
include("reporting/r2_runs.jl")
include("verification/r2.jl")
include("core/r3.jl")
include("formulations/r3.jl")
include("verification/r3.jl")
include("reporting/r3_runs.jl")

export reconstruct_r3_pressure
export build_r3_subproblem, repair_r3_flow, solve_r3_feasibility, validate_r3_solution
export save_r3_run, read_r3_run, plot_r3_run

export R2Case, R2Spec, load_r2_case, water_mass_weights, replay_water_mass, mccormick_bounds
export build_r2_model, r2_model_class
export solve_r2_case, save_r2_run, read_r2_run, compare_r2_runs, plot_r2_run
export validate_r2_solution

export chp_efficiency,
    chp_heat,
    pv_available,
    wind_ramp_paper,
    battery_step,
    heat_storage_step_paper,
    building_step,
    heat_power,
    fixed_flow_kernel,
    pipe_outlet,
    mix_temperature,
    electrical_bases,
    R1Case,
    load_case,
    build_r1_model,
    solve_r1_case,
    validate_r1_solution,
    save_r1_run,
    read_r1_run,
    plot_r1_run

"""
    hello(who::String)

Return "Hello, `who`".
"""
hello(who::String) = "Hello, $who"

"""
    domath(x::Number)

Return `x + 5`.
"""
domath(x::Number) = x + 5

end # module PaperRebuild
