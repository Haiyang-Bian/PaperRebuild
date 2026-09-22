"""
    validate_r7_transport_recovery(case, spec, result)

分别独立重算共用设备/电网/流量方程和逐管水团回放，并核查给定流量身份、热交付与失供积分。
采用A1/A2；给定流量最优性、子步热模型、交流电网、水力及全故障安全分别记账。
验证不读取JuMP模型，缺少任何一个块都不能判联合调度通过。
"""
function validate_r7_transport_recovery(c, s, r)
    x=r7_transport_inputs(c, s)
    r["schema"]=="r7-transport-result-v1" &&
    r["version"]==s["version"] &&
    r["spec_sha256"]==r7_digest(s) &&
    r["case_sha256"]==c.sha256 &&
    r["objective_kind"]=="expected_unserved_energy_MWh" || error("逐管结果身份错误")
    r7_check_fault(c, r["fault"])
    r["status"]=="infeasible_certified" &&
        r["termination_status"]!="INFEASIBLE" &&
        error("不可行状态缺少证据")
    q=Dict{String,Any}(
        "model_pass"=>false,
        "conditional_optimality_pass"=>false,
        "full_variable_flow_optimized"=>false,
        "continuous_node_dynamics_verified"=>false,
        "hydraulic_verified"=>false,
        "ac_grid_validated"=>false,
        "whole_recovery_certified"=>false,
        "validation_version"=>"r7_transport_validation_v2",
        "thermal_flow_basis"=>"declared_schedule_with_raw_equality_check",
    )
    haskey(r, "values")==haskey(r, "thermal_values") || error("缺少共用或热状态数值块")
    haskey(r, "values") || return q
    # 仅借用旧验证器中未替换的物理行；该适配记录从不作为双水箱结果保存或认证。
    shared=Dict{String,Any}(
        "schema"=>"r7-recovery-result-v1",
        "version"=>r7_recovery_version(c),
        "case_sha256"=>c.sha256,
        "fault"=>r["fault"],
        "preplan_id"=>c.data["preplan_id"],
        "preplan_optimality_verified"=>false,
        "objective_kind"=>r["objective_kind"],
        "status"=>r["status"],
        "values"=>r["values"],
        "solver_objective_MWh"=>r["solver_objective_MWh"],
    )
    for key in ("fixed_z", "fixed_battery_modes")
        haskey(r, key) && (shared[key]=r[key])
    end
    a=validate_r7_recovery(c, shared; aggregate_heat = false)
    v=Dict(k=>r7_unpack(r["values"], k) for k in ("m_pipe", "m_source", "m_load", "H", "H_shed"))
    flow_residual=maximum(maximum(abs.(v[k] .- x.v[k])) for k in ("m_pipe", "m_source", "m_load"))
    # 热块的数值系数和停流分支由显式计划决定；冗余流量变量的尾差另由等式残差检查。
    # 不用正负舍入尾差激活一个原本不存在的端口，也不裁剪保存的原值。
    thermal_input=merge(v, x.v)
    y=r7_thermal_dispatch_context(x, thermal_input)
    thermal=Dict(
        "status"=>r["status"],
        "values"=>r["thermal_values"],
        "solver_objective_MWh"=>a["loss_heat_MWh"],
    )
    b=r7_validate_thermal_values(y, s, thermal)
    q["shared"]=a
    q["thermal"]=b
    q["flow_schedule_residual_kg_s"]=flow_residual
    q["model_pass"]=a["shared_block_pass"]&&b["same_dispatch_pass"]&&flow_residual<=1e-6
    for k in ("loss_MWh", "loss_electric_MWh", "loss_heat_MWh")
        q[k]=a[k]
    end
    if haskey(r, "lower_bound_MWh")
        lb=r["lower_bound_MWh"]
        isfinite(lb) || error("逐管目标界不是有限数")
        gap=(q["loss_MWh"]-lb)/max(1, abs(q["loss_MWh"]))
        q["relative_gap"]=gap
        q["conditional_optimality_pass"]=q["model_pass"]&&-1e-6<=gap<=1e-4
    end
    q
end
