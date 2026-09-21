"""
    R7PlanningCase(normal, specification)

第6章经济安全规划输入：同一正常案例与显式事件窗口/失供门槛。正常控制域沿normal声明，
本版仅支持已核查的给定正流连续输运参考；不把它称为完整变流量规划。
每个事件覆盖其全部允许内部断线；PCC在事件内断开，恢复控制不得跨事件或故障错误共用。
"""
struct R7PlanningCase
    normal::R7NormalCase
    specification::Dict{String,Any}
    sha256::String
end

function R7PlanningCase(normal::R7NormalCase, input::AbstractDict)
    r7_normal_assert(normal)
    normal.data["thermal_model"]=="plug_flow_reference_v1" || error("规划状态需与连续输运参考一致")
    d=TOML.parse(r7_text(input))
    d["schema"]=="r7-planning-spec-v1" || error("规划输入版本错误")
    d["normal_domain"]=="prescribed_positive_fixed_electric_topology" ||
        error("正常域未声明或未实现")
    d["recovery_model"] in ("r7_recovery_checked_v1", "r7_recovery_port_checked_v1") ||
        error("恢复版本未声明")
    !isempty(d["events"]) || error("规划事件集合为空")
    ids=String[]
    for e in d["events"]
        id=e["id"]
        id isa String && occursin(r"^[A-Za-z0-9_-]+$", id) || error("事件ID非法")
        id in ids && error("事件ID重复")
        push!(ids, id)
        at, T=e["event_start"], e["periods"]
        at isa Integer && T isa Integer && T>0 && 1<=at<=at+T-1<=normal.data["periods"] ||
            error("事件时域错误")
        isfinite(e["renewable_factor"]) && 0<=e["renewable_factor"]<=1 ||
            error("灾害新能源比例错误")
        isfinite(e["loss_limit_MWh"]) && e["loss_limit_MWh"]>=0 || error("失供门槛错误")
    end
    R7PlanningCase(normal, d, r7_digest(Dict("normal"=>normal.data, "specification"=>d)))
end

"""读取独立的正常案例与事件规则；不求解、不补缺省事件或改变容量。"""
load_r7_planning_case(normal_path::AbstractString, spec_path::AbstractString) =
    R7PlanningCase(load_r7_normal_case(normal_path), TOML.parsefile(spec_path))

function r7_planning_assert(c)
    r7_normal_assert(c.normal)
    r7_digest(Dict("normal"=>c.normal.data, "specification"=>c.specification))==c.sha256 ||
        error("规划输入构造后被修改")
end

# 结构模板只用于参数化建模；初始数值在主问题中全部替换成同一正常决策，不作为实际恢复来源。
function r7_event_template(c::R7PlanningCase, s)
    d=c.normal.data
    e=c.specification["events"][s]
    at=e["event_start"]
    T=e["periods"]
    win=at:(at+T-1)
    W=length(d["probabilities"])
    out=Dict{String,Any}(
        "schema"=>"r7-recovery-case-v1",
        "name"=>d["name"]*"_template_"*e["id"],
        "origin"=>d["origin"],
        "periods"=>T,
        "dt_h"=>d["dt_h"],
        "event_start"=>at,
        "probabilities"=>deepcopy(d["probabilities"]),
        "preplan_id"=>"unbound_template",
        "renewable_factor"=>e["renewable_factor"],
        "loss_limit_MWh"=>e["loss_limit_MWh"],
        "battery_rule"=>d["battery_rule"],
        "units"=>deepcopy(d["units"]),
        "electric"=>deepcopy(d["electric"]),
        "heat"=>deepcopy(d["heat"]),
        "devices"=>deepcopy(d["devices"]),
    )
    r7_currency_record!(out, d)
    out["electric"]["load_MW"]=[row[win] for row in d["electric"]["load_MW"]]
    pop!(out["electric"], r7_money_key(d, "price_USD_MWh"))
    h=out["heat"]
    h["load_MW"]=[row[win] for row in d["heat"]["load_MW"]]
    h["ambient_K"]=h["ambient_K"][win]
    h["reference_flow_kg_s"]=[sum(row[t] for row in d["heat"]["source_flow_kg_s"]) for t in win]
    pop!(h, "source_flow_kg_s")
    pop!(h, "load_flow_kg_s")
    for (p, old) in zip(h["pipes"], d["heat"]["pipes"])
        for side in ("S", "R")
            p["initial_$(side)_K"]=[
                sum(x["mass_kg"] .* x["temperature_K"])/sum(x["mass_kg"]) for
                x in old["initial_$(side)_profiles"]
            ]
            delete!(p, "initial_$(side)_profiles")
            pop!(p, "history_$(side)_K", nothing)
        end
        p["normal_flow_kg_s"]=p["normal_flow_kg_s"][win]
    end
    for g in out["devices"]
        g["kind"]=="CHP" && (g["commitment"]=ones(Int, T))
        g["kind"]=="PV" && (g["available_MW"]=g["available_MW"][win])
    end
    d=c.specification
    d["recovery_model"]=="r7_recovery_port_checked_v1" &&
        (out["recovery_model"]=d["recovery_model"])
    R7RecoveryCase(out)
end

function r7_planning_pairs(c)
    r7_planning_assert(c)
    [
        (event = s, fault = gamma) for s in eachindex(c.specification["events"]) for
        gamma in r7_faults(r7_event_template(c, s))
    ]
end

function r7_planning_pair_key(p)
    string(p.event)*":"*join(p.fault, ",")
end
