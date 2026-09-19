module PaperRebuild

using JuMP
using TOML, SHA, Dates, UUIDs, CSV, Random

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
include("core/r4_reconfiguration.jl")
include("core/r4_tspa.jl")
include("formulations/r4.jl")
include("formulations/r4_reconfiguration.jl")
include("verification/r4.jl")
include("verification/r4_baseline.jl")
include("reporting/r4_runs.jl")
include("algorithms/r4_bargaining.jl")
include("verification/r4_bargaining.jl")
include("algorithms/r4_tspa.jl")
include("verification/r4_tspa.jl")
include("reporting/r4_tspa.jl")
include("core/r4_distributed.jl")
include("formulations/r4_distributed.jl")
include("algorithms/r4_distributed.jl")
include("verification/r4_distributed.jl")
include("reporting/r4_distributed.jl")
include("algorithms/r4_discrete.jl")
include("verification/r4_discrete.jl")
include("reporting/r4_discrete.jl")
include("verification/r4_reconfiguration.jl")
include("algorithms/r4_reconfiguration.jl")
include("reporting/r4_reconfiguration.jl")
include("core/r4_heat_compatibility.jl")
include("formulations/r4_heat_compatibility.jl")
include("verification/r4_heat_compatibility.jl")
include("algorithms/r4_heat_compatibility.jl")
include("reporting/r4_heat_compatibility.jl")
include("core/r4_thermal.jl")
include("formulations/r4_thermal.jl")
include("verification/r4_thermal.jl")
include("algorithms/r4_thermal.jl")
include("core/r5_market.jl")
include("formulations/r5_market.jl")
include("verification/r5_market.jl")
include("algorithms/r5_market.jl")
include("reporting/r5_market.jl")
include("verification/r5_market_payment.jl")
include("core/r5_dispatch.jl")
include("formulations/r5_dispatch.jl")
include("verification/r5_dispatch.jl")
include("algorithms/r5_dispatch.jl")
include("reporting/r5_dispatch.jl")
include("verification/r5_dispatch_duality.jl")
include("formulations/r5_dispatch_dual.jl")
include("core/r5_commitment.jl")
include("formulations/r5_commitment.jl")
include("verification/r5_commitment.jl")
include("algorithms/r5_commitment.jl")
include("reporting/r5_commitment.jl")
include("core/r5_risk.jl")
include("formulations/r5_risk.jl")
include("verification/r5_risk.jl")
include("algorithms/r5_risk.jl")
include("reporting/r5_risk.jl")
include("core/r5_benders.jl")
include("formulations/r5_benders.jl")
include("verification/r5_benders.jl")
include("algorithms/r5_benders.jl")
include("reporting/r5_benders.jl")
include("core/r5_strategic.jl")
include("formulations/r5_strategic.jl")
include("verification/r5_strategic.jl")
include("algorithms/r5_strategic.jl")
include("reporting/r5_strategic.jl")
include("core/r5_strategic_benders.jl")
include("formulations/r5_strategic_benders.jl")
include("verification/r5_strategic_benders.jl")
include("algorithms/r5_strategic_benders.jl")
include("reporting/r5_strategic_benders.jl")
export build_r5_strategic_benders_master, solve_r5_strategic_benders
export validate_r5_strategic_benders, save_r5_strategic_benders_run, read_r5_strategic_benders_run
export compare_r5_strategic_benders_runs
include("core/r6_protocol.jl")
include("algorithms/r6_data.jl")
include("verification/r6_statistics.jl")
include("reporting/r6_data.jl")
export R6Protocol, load_r6_protocol, R6TrajectorySet, r6_generate_trajectories
export r6_fit_representatives, r6_support_distance, save_r6_dataset, read_r6_dataset
export r6_binomial_bounds, r6_risk_evidence, r6_paired_costs
include("algorithms/r5_market_selection.jl")
include("core/r5_execution.jl")
include("formulations/r5_execution.jl")
include("verification/r5_execution.jl")
include("algorithms/r5_execution.jl")
include("reporting/r5_execution.jl")
export R5MarketExecutionSpec, build_r5_execution_selector, solve_r5_market_execution
export validate_r5_market_execution, evaluate_r5_execution_delivery, validate_r5_execution_delivery
export save_r5_execution_run, read_r5_execution_run
export R5StrategicCase, load_r5_strategic_case, build_r5_strategic
export solve_r5_strategic, validate_r5_strategic
export save_r5_strategic_run, read_r5_strategic_run
export r5_market_settlement_range
export R5BendersSpec, r5_benders_bounds, build_r5_benders_subproblem
export solve_r5_benders_subproblem, validate_r5_benders_subproblem, r5_benders_cut
export build_r5_benders_master, solve_r5_benders, validate_r5_benders
export save_r5_benders_run, read_r5_benders_run, compare_r5_benders_runs
export R5RiskCase, load_r5_risk_case, build_r5_risk, solve_r5_risk
export r5_worst_distribution, validate_r5_transport, validate_r5_risk
export save_r5_risk_run, read_r5_risk_run
export R5CommitmentCase, load_r5_commitment_case, build_r5_commitment, solve_r5_commitment
export validate_r5_commitment, save_r5_commitment_run, read_r5_commitment_run
export validate_r5_dispatch_duals, r5_dispatch_sensitivity, build_r5_dispatch_dual
export r5_building_coefficients, r5_building_temperature, R5DispatchCase, load_r5_dispatch_case
export r5_award_from_market, build_r5_dispatch, solve_r5_dispatch, validate_r5_dispatch
export save_r5_dispatch_run, read_r5_dispatch_run
export R5MarketCase, load_r5_market_case, build_r5_market, build_r5_market_dual
export r5_market_payment_identity
export solve_r5_market,
    validate_r5_market, save_r5_market_run, read_r5_market_run, compare_r5_market_runs
export R4ThermalSpec, r4_steady_pipe, r4_thermal_min_flow
export build_r4_thermal, solve_r4_thermal, validate_r4_thermal
export R4HeatCompatibilitySpec, build_r4_heat_reconstruction, reconstruct_r4_heat
export validate_r4_heat_reconstruction, save_r4_heat_run, read_r4_heat_run
export R4ReconfigurationSpec, r4_is_tree, r4_network_states
export build_r4_reconfiguration, solve_r4_reconfiguration, validate_r4_reconfiguration
export enumerate_r4_reconfiguration
export validate_r4_network_enumeration, read_r4_network_enumeration
export r4_battery_patterns, reconstruct_r4_cost, solve_r4_discrete
export validate_r4_discrete, save_r4_discrete_run, read_r4_discrete_run
export R4DistributedSpec, build_r4_distributed_block, solve_r4_distributed
export validate_r4_distributed, save_r4_distributed_run, read_r4_distributed_run
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
