"""
    r9_detailed_preplan_spec(case; mode, pairs, penalty_MWh, flows,
                            substeps=4, limits_MWh=nothing)

R9-DP1：声明给定正常/恢复流量的详细灾前对照。正常费用及物理输入保持原R9定义，
恢复改用R7-L1完整历史和子步/空间温区；该变更是显式项目模型版本，不是原式笔误修正。
flows覆盖原事件故障全集，pairs明确本次建模子集；kg/s、K、h及输入币种/MWh。
mode为economic、penalty或threshold。economic只建立原正常基准，不承诺详细恢复可行。
"""
function r9_detailed_preplan_spec(
    c::R7PlanningCase;
    mode,
    pairs,
    penalty_MWh,
    flows,
    substeps = 4,
    limits_MWh = nothing,
)
    base = r9_preplan_spec(c; mode, pairs, penalty_MWh, limits_MWh)
    carrier = r9_preplan_carrier(c, base)
    substeps isa Integer && !(substeps isa Bool) && 1 <= substeps <= 64 ||
        error("详细灾前子步必须为1至64的整数")
    linked = r7_linked_planning_spec(carrier; flows, substeps)
    s = Dict{String,Any}(
        "schema" => "r9-detailed-preplan-spec-v1",
        "version" => "r9_prescribed_detailed_preplan_v1",
        "case_sha256" => c.sha256,
        "base_spec" => base,
        "linked_spec" => linked,
        "thermal_rule" => "shared_spatial_history_substep_ports_and_spatial_bounds",
        "normal_domain_unchanged" => true,
        "full_variable_flow_claim" => false,
    )
    r9_detailed_preplan_check(c, s)
    s
end

function r9_detailed_preplan_check(c, s)
    s["schema"] == "r9-detailed-preplan-spec-v1" &&
    s["version"] == "r9_prescribed_detailed_preplan_v1" &&
    s["case_sha256"] == c.sha256 &&
    s["thermal_rule"] == "shared_spatial_history_substep_ports_and_spatial_bounds" &&
    s["normal_domain_unchanged"] === true &&
    s["full_variable_flow_claim"] === false || error("详细灾前规格或声明范围错误")
    r9_preplan_check(c, s["base_spec"])
    carrier = r9_preplan_carrier(c, s["base_spec"])
    s["linked_spec"]["substeps"] isa Bool && error("详细灾前子步不能为布尔值")
    r7_linked_spec_check(carrier, s["linked_spec"])
    carrier
end
