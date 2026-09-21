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
include("core/r6_methods.jl")
include("algorithms/r6_methods.jl")
export R6PhysicalCase, load_r6_physical_case, R6MethodSpec, r6_dispatch_day
export r6_training_case, build_r6_model, solve_r6_training
include("core/r6_evaluation.jl")
include("formulations/r6_evaluation.jl")
include("verification/r6_evaluation.jl")
include("algorithms/r6_evaluation.jl")
include("algorithms/r6_support_evaluation.jl")
include("reporting/r6_evaluation.jl")
export R6EvaluationSpec, R6Policy, r6_policy_from_training, r6_evaluation_day
export build_r6_recourse, evaluate_r6_day, validate_r6_evaluation
export save_r6_evaluation, read_r6_evaluation
export r6_support_label, evaluate_r6_policy_day, validate_r6_policy_day
export save_r6_policy_day, read_r6_policy_day
include("core/r6_study.jl")
include("verification/r6_study.jl")
export R6StudySpec, load_r6_study, r6_study_candidates, r6_summarize_days, select_r6_methods
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

include("core/r7_recovery.jl")
include("formulations/r7_recovery.jl")
include("verification/r7_recovery.jl")
include("algorithms/r7_recovery.jl")
include("reporting/r7_recovery.jl")
export R7RecoveryCase, load_r7_recovery_case, r7_faults, build_r7_recovery, solve_r7_recovery
export with_r7_battery_rule, r7_battery_cycle_effect
export validate_r7_recovery,
    enumerate_r7_recovery, audit_r7_faults, save_r7_recovery, read_r7_recovery

include("core/r7_adversary.jl")
include("formulations/r7_adversary.jl")
include("verification/r7_adversary.jl")
include("algorithms/r7_adversary.jl")
include("reporting/r7_adversary.jl")
export R7RecourseLP, r7_recovery_lp, r7_recovery_loss_cap
export build_r7_recourse_dual, build_r7_adversary, validate_r7_dual
export solve_r7_adversary, validate_r7_adversary, save_r7_adversary, read_r7_adversary

include("core/r7_commitment.jl")
include("components/r7_commitment.jl")
include("verification/r7_commitment.jl")
export R7CHPSpec, add_r7_chp_commitment!, validate_r7_chp, r7_chp_event_boundary

include("networks/r7_pipe_state.jl")
export R7PipeState, r7_pipe_state, r7_pipe_temperature, r7_pipe_inventory, r7_pipe_step
export with_r7_port_temperature_bounds, r7_port_temperature_bounds, r7_island_heat_bound

include("core/r7_thermal.jl")
include("formulations/r7_thermal.jl")
include("verification/r7_thermal.jl")
include("algorithms/r7_thermal.jl")
include("reporting/r7_thermal.jl")
export r7_thermal_spec, r7_thermal_port_witness, build_r7_thermal_reconstruction
export solve_r7_thermal_reconstruction, validate_r7_thermal_reconstruction
export save_r7_thermal_reconstruction, read_r7_thermal_reconstruction

include("core/r7_transport.jl")
include("formulations/r7_transport.jl")
include("verification/r7_transport.jl")
include("algorithms/r7_transport.jl")
include("reporting/r7_transport.jl")
export r7_transport_spec, r7_transport_port_witness, build_r7_transport_recovery
export solve_r7_transport_recovery, validate_r7_transport_recovery
export save_r7_transport_recovery, read_r7_transport_recovery
export r7_reconstruct_battery_cycles

include("core/r7_normal.jl")
include("networks/r7_normal_transport.jl")
include("formulations/r7_normal.jl")
include("verification/r7_normal.jl")
include("algorithms/r7_normal.jl")
include("reporting/r7_normal.jl")
export R7NormalCase, load_r7_normal_case, build_r7_normal, solve_r7_normal
export validate_r7_normal, r7_normal_event, save_r7_normal, read_r7_normal

include("core/r7_planning.jl")
include("formulations/r7_planning.jl")
include("verification/r7_planning.jl")
include("algorithms/r7_planning.jl")
include("reporting/r7_planning.jl")
export R7PlanningCase, load_r7_planning_case, build_r7_planning
export solve_r7_planning, validate_r7_planning, save_r7_planning, read_r7_planning

include("core/r7_linked_planning.jl")
include("networks/r7_linked_state.jl")
include("formulations/r7_linked_planning.jl")
include("verification/r7_linked_planning.jl")
include("algorithms/r7_linked_planning.jl")
include("reporting/r7_linked_planning.jl")
export r7_linked_planning_spec, r7_linked_pipe_replay, r7_linked_pipe_map
export build_r7_linked_planning, solve_r7_linked_planning, validate_r7_linked_planning
export save_r7_linked_planning, read_r7_linked_planning

include("core/r7_normal_flow.jl")
include("networks/r7_mass_overlap.jl")
include("networks/r7_lossy_mass.jl")
export add_r7_lossy_mass_transport!, r7_loss_quadrature_bound
include("formulations/r7_normal_flow.jl")
include("verification/r7_normal_flow.jl")
include("algorithms/r7_normal_flow.jl")
include("reporting/r7_normal_flow.jl")
export r7_normal_flow_spec, add_r7_mass_transport!, build_r7_normal_flow, solve_r7_normal_flow
export validate_r7_normal_flow, save_r7_normal_flow, read_r7_normal_flow

include("core/r7_flow_planning.jl")
include("formulations/r7_flow_planning.jl")
include("verification/r7_flow_planning.jl")
include("algorithms/r7_flow_planning.jl")
include("reporting/r7_flow_planning.jl")
export r7_flow_planning_spec, build_r7_flow_planning, solve_r7_flow_planning
export validate_r7_flow_planning, save_r7_flow_planning, read_r7_flow_planning

include("core/r8_tradeoff.jl")
include("formulations/r8_tradeoff.jl")
include("verification/r8_tradeoff.jl")
include("algorithms/r8_tradeoff.jl")
include("reporting/r8_tradeoff.jl")
export r8_spec, build_r8_model, solve_r8_case, validate_r8_solution, save_r8_run, read_r8_run

include("core/r8_energy_flow.jl")
include("formulations/r8_energy_flow.jl")
include("verification/r8_energy_flow.jl")
include("algorithms/r8_energy_flow.jl")
include("reporting/r8_energy_flow.jl")
export r8_energy_spec, build_r8_energy_model, solve_r8_energy_case, validate_r8_energy_solution
export save_r8_energy_run, read_r8_energy_run

include("core/r9_inputs.jl")
include("verification/r9_sources.jl")
export load_r9_sources, r9_tariff, r9_original_input_gate, audit_r9_sources
include("core/r9_pv.jl")
include("verification/r9_pv.jl")
include("formulations/r9_pv.jl")
include("reporting/r9_pv.jl")
export r9_pv_case, load_r9_pv_case, audit_r9_pv_input
export build_r9_pv_model, solve_r9_pv_case, validate_r9_pv_solution
include("formulations/r9_reduced.jl")
include("reporting/r9_reduced.jl")
include("verification/r9_reduced.jl")
export build_r9_reduced_model, solve_r9_reduced_case, r9_daily_heat_balance
export validate_r9_reduced_solution

include("networks/r9_short_pipe.jl")
include("formulations/r9_flow.jl")
include("verification/r9_flow.jl")
include("formulations/r9_terminal.jl")
include("verification/r9_fixed.jl")
include("reporting/r9_fixed.jl")
export r9_transport_coefficients, audit_r9_flow_domain, build_r9_flow_model
export r9_flow_terminal_rows, r9_heat_memory_balance
export r9_terminal_coordinates
export solve_r9_fixed_case, validate_r9_fixed_solution

include("core/r9_trading.jl")
include("formulations/r9_trading.jl")
include("verification/r9_trading.jl")
export R9TradingCase, load_r9_trading_case, r9_trading_case, build_r9_trading_model
export validate_r9_trading_solution, r9_trading_ledger
include("algorithms/r9_trading.jl")
include("verification/r9_trading_runs.jl")
include("reporting/r9_trading.jl")
export solve_r9_trading_case, validate_r9_trading_run, save_r9_trading_run
export read_r9_trading_run, compare_r9_trading_runs
include("verification/r9_trading_capacity.jl")
export audit_r9_trading_capacity
export r9_trading_heat_cut

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
