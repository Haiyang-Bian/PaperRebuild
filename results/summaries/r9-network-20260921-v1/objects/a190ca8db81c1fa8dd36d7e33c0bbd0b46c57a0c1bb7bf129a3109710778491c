"""
    r8_spec(case, flow; mode, limits_MWh=nothing, penalty_USD_MWh=500.0,
            topology=:reconfigure, heat_preparation=:free)

R8-T1至T4：第6.5节三种比较口径。mode为economic（仅正常成本）、threshold
（每事件最坏期望失供上限）或penalty（正常成本加逐事件最坏失供罚项）。
500 USD/MWh见PDF122；事件之和不是事件发生概率，新能源仍按原概率加权。
retain_surviving只保留未故障的原闭合边；no_net_charge禁止正常期各管库存超过初值，
这是项目“禁止净预充热”对照，不等于作者的稳态能量流或移除热惯性。输入和旧R7结果不变。
"""
function r8_spec(
    c::R7PlanningCase,
    flow;
    mode,
    limits_MWh = nothing,
    penalty_USD_MWh = 500.0,
    topology = :reconfigure,
    heat_preparation = :free,
)
    r7_flow_planning_check(c, flow)
    limits=limits_MWh===nothing ? [e["loss_limit_MWh"] for e in c.specification["events"]] :
           Float64.(limits_MWh)
    s=Dict{String,Any}(
        "schema"=>"r8-tradeoff-spec-v1",
        "version"=>"r8_detailed_tradeoff_v1",
        "case_sha256"=>c.sha256,
        "flow_sha256"=>r7_digest(flow),
        "mode"=>String(mode),
        "limits_MWh"=>limits,
        "penalty_USD_MWh"=>Float64(penalty_USD_MWh),
        "recovery_topology"=>String(topology),
        "heat_preparation"=>String(heat_preparation),
        "event_rule"=>"sum_of_event_worst_expected_unserved_energy",
        "economic_rule"=>"normal_only_then_independent_recourse",
        "bound_scope"=>"declared_control_and_thermal_model",
    )
    r8_check(c, flow, s)
    s
end

function r8_check(c, flow, s)
    r7_flow_planning_check(c, flow)
    s["schema"]=="r8-tradeoff-spec-v1" &&
    s["version"]=="r8_detailed_tradeoff_v1" &&
    s["case_sha256"]==c.sha256 &&
    s["flow_sha256"]==r7_digest(flow) &&
    s["mode"] in ("economic", "threshold", "penalty") &&
    s["recovery_topology"] in ("reconfigure", "retain_surviving") &&
    s["heat_preparation"] in ("free", "no_net_charge") &&
    s["event_rule"]=="sum_of_event_worst_expected_unserved_energy" &&
    s["economic_rule"]=="normal_only_then_independent_recourse" &&
    s["bound_scope"]=="declared_control_and_thermal_model" || error("R8规格身份/口径错误")
    length(s["limits_MWh"])==length(c.specification["events"]) &&
    all(x->isfinite(x)&&x>=0, s["limits_MWh"]) || error("R8事件门槛错误")
    isfinite(s["penalty_USD_MWh"]) && s["penalty_USD_MWh"]>0 || error("失供价格必须为正且有限")
    nothing
end

# 总需求是可交付电热失供的显式有限上界；不是可行恢复存在性的假设。
function r8_loss_caps(c)
    d=c.normal.data
    [
        d["dt_h"]*sum(
            sum(row[t] for row in d[k]["load_MW"]) for k in ("electric", "heat") for
            t in e["event_start"]:(e["event_start"]+e["periods"]-1)
        ) for e in c.specification["events"]
    ]
end

function r8_carrier(c, flow)
    rules=deepcopy(c.specification)
    for (e, cap) in zip(rules["events"], r8_loss_caps(c))
        e["loss_limit_MWh"]=cap
    end
    rc=R7PlanningCase(c.normal, rules)
    f=deepcopy(flow)
    f["case_sha256"]=rc.sha256
    r7_flow_planning_check(rc, f)
    rc, f
end

function r8_objective_kind(s; evaluation = false)
    evaluation && return "sum_event_worst_expected_unserved_energy_MWh"
    s["mode"]=="penalty" ? "normal_cost_plus_event_unserved_penalty_USD" :
    "expected_normal_cost_USD"
end
