"""
    r8_spec(case, flow; mode, limits_MWh=nothing, penalty_USD_MWh=nothing, penalty_MWh=nothing,
            topology=:reconfigure, heat_preparation=:free)

R8-T1至T4：第6.5节三种比较口径。mode为economic（仅正常成本）、threshold
（每事件最坏期望失供上限）或penalty（正常成本加逐事件最坏失供罚项）。
v1省略罚值时使用500 USD/MWh（PDF122）；v2必须显式给出penalty_MWh，单位为输入币种/MWh。
两种关键字不能混用，不做汇率换算。事件之和不是事件发生概率，新能源仍按原概率加权。
retain_surviving只保留未故障的原闭合边；no_net_charge禁止正常期各管库存超过初值，
这是项目“禁止净预充热”对照，不等于作者的稳态能量流或移除热惯性。输入和旧R7结果不变。
"""
function r8_spec(
    c::R7PlanningCase,
    flow;
    mode,
    limits_MWh = nothing,
    penalty_USD_MWh = nothing,
    penalty_MWh = nothing,
    topology = :reconfigure,
    heat_preparation = :free,
)
    r7_flow_planning_check(c, flow)
    limits=limits_MWh===nothing ? [e["loss_limit_MWh"] for e in c.specification["events"]] :
           Float64.(limits_MWh)
    s=Dict{String,Any}(
        "schema"=>r7_money_schema(c.normal.data, "r8-tradeoff-spec-v1"),
        "version"=>"r8_detailed_tradeoff_v1",
        "case_sha256"=>c.sha256,
        "flow_sha256"=>r7_digest(flow),
        "mode"=>String(mode),
        "limits_MWh"=>limits,
        r7_money_key(c.normal.data, "penalty_USD_MWh")=>r8_penalty_value(
            c.normal.data,
            penalty_USD_MWh,
            penalty_MWh,
        ),
        "recovery_topology"=>String(topology),
        "heat_preparation"=>String(heat_preparation),
        "event_rule"=>"sum_of_event_worst_expected_unserved_energy",
        "economic_rule"=>"normal_only_then_independent_recourse",
        "bound_scope"=>"declared_control_and_thermal_model",
    )
    r7_currency_record!(s, c.normal.data)
    r7_record_service!(s, c.normal.data)
    r8_check(c, flow, s)
    s
end

function r8_check(c, flow, s)
    r7_check_service_record(c.normal.data, s)
    r7_check_currency_record(c.normal.data, s)
    r7_check_money_fields(c.normal.data, s, ("penalty_USD_MWh",))
    r7_flow_planning_check(c, flow)
    s["schema"]==r7_money_schema(c.normal.data, "r8-tradeoff-spec-v1") &&
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
    isfinite(s[r7_money_key(c.normal.data, "penalty_USD_MWh")]) &&
    s[r7_money_key(c.normal.data, "penalty_USD_MWh")]>0 || error("失供价格必须为正且有限")
    nothing
end

# 总需求是可交付电热失供的显式有限上界；不是可行恢复存在性的假设。
function r8_loss_caps(c)
    d=c.normal.data
    if r7_critical_service(d)
        return [
            d["dt_h"]*sum(
                sum(row[t] for row in d["load_service"]["critical_load_MW"]) for
                t in e["event_start"]:(e["event_start"]+e["periods"]-1)
            ) for e in c.specification["events"]
        ]
    end
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
    if get(s, "service_objective", nothing)=="critical_electric_v1"
        evaluation && return "sum_event_worst_expected_critical_electric_unserved_energy_MWh"
        return s["mode"]=="penalty" ?
               "normal_cost_plus_event_critical_electric_unserved_penalty_"*r7_currency(s) :
               r7_normal_objective_kind(s)
    end
    evaluation && return "sum_event_worst_expected_unserved_energy_MWh"
    s["mode"]=="penalty" ? "normal_cost_plus_event_unserved_penalty_"*r7_currency(s) :
    r7_normal_objective_kind(s)
end

# 新版不沿用旧美元罚值；调用者必须从已声明币种的来源提供数值。
function r8_penalty_value(d, legacy, explicit)
    if r7_currency_v2(d)
        legacy===nothing && explicit!==nothing || error("v2须显式penalty_MWh，不能混用USD关键字")
        value=Float64(explicit)
    else
        explicit===nothing || error("v1使用penalty_USD_MWh；新版字段须先声明v2输入")
        value=legacy===nothing ? 500.0 : Float64(legacy)
    end
    isfinite(value) && value>0 || error("失供罚值须为正且有限")
    value
end
