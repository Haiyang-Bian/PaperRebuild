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
include("core/r3_operation.jl")
include("formulations/r2.jl")
include("reporting/r2_runs.jl")
include("verification/r2.jl")
include("core/r3.jl")
include("formulations/r3.jl")
include("verification/r3.jl")
include("reporting/r3_runs.jl")
include("algorithms/r3_sensitivity.jl")
include("algorithms/r3_projection.jl")
include("algorithms/r3_pg.jl")
include("algorithms/r3_local.jl")
include("algorithms/r3_v2.jl")
include("reporting/r3_modes.jl")
include("reporting/r3_audit.jl")
include("algorithms/r3_physical.jl")
include("algorithms/r3_v3.jl")
include("verification/r3_v3_kkt.jl")
include("algorithms/r3_baseline.jl")
include("verification/r3_baseline.jl")
include("reporting/r3_baseline.jl")
include("core/r4.jl")
include("core/r4_tspa.jl")
include("formulations/r4.jl")
include("verification/r4.jl")
include("verification/r4_baseline.jl")
include("reporting/r4_runs.jl")
include("algorithms/r4_bargaining.jl")
include("verification/r4_bargaining.jl")
include("algorithms/r4_tspa.jl")
include("verification/r4_tspa.jl")
include("reporting/r4_tspa.jl")
export R4TSPASpec, r4_tspa_scales, solve_r4_tspa
export validate_r4_trading, validate_r4_elastic, validate_r4_tspa
export save_r4_tspa_run, read_r4_tspa_run
export R4Case, R4Spec, load_r4_case, build_r4_model, solve_r4_case
export r4_preferred_demand, r4_coordination_surplus
export r4_nash_allocation, r4_bargaining_weights, r4_allocate_coordination
export validate_r4_allocation
export validate_r4_solution, r4_ledger, save_r4_run, read_r4_run, compare_r4_runs, plot_r4_run

export R3BaselineSpec, solve_r3_baseline, compare_r3_baselines

export audit_r3_failure, r3_stopping_evidence
export build_r3_physical_step

export R3OperationSpec, build_r3_local_step
export r3_boundary_case
export solve_r3_reference, compare_r3_modes

export r3_transport_jacobian, r3_value_sensitivity
export build_r3_projection, solve_r3_projected_gradient, validate_r3_iteration

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
