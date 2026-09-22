"""
    r9_preplan_spec(case; mode, pairs, penalty_MWh, limits_MWh=nothing)

第7.5节给定正常流量下的三目标对照规格。mode为economic、penalty或threshold；
pairs显式列出事件与故障子集。罚值单位为输入币种/MWh，必须显式给出，允许零罚值退化测试。
同一事件取所选故障期望失供的最大值，再按事件求和，不把故障罚项求和或当作事件概率。
正常物理输入不变；子集覆盖、原门槛和载体门槛分别登记，不声称作者原始方案的等价实现。
"""
function r9_preplan_spec(c::R7PlanningCase; mode, pairs, penalty_MWh, limits_MWh = nothing)
    r7_planning_assert(c)
    limits=limits_MWh===nothing ? [e["loss_limit_MWh"] for e in c.specification["events"]] :
           collect(limits_MWh)
    s=Dict{String,Any}(
        "schema"=>"r9-preplan-spec-v1",
        "version"=>"r9_prescribed_preplan_v1",
        "case_sha256"=>c.sha256,
        "normal_sha256"=>c.normal.sha256,
        "currency"=>r7_currency(c.normal.data),
        "service_objective"=>r7_service_objective(c.normal.data),
        "mode"=>String(mode),
        "pairs"=>[Dict("event"=>p.event, "fault"=>collect(p.fault)) for p in pairs],
        "penalty_MWh"=>Float64(penalty_MWh),
        "limits_MWh"=>Float64.(limits),
        "event_rule"=>"sum_of_selected_event_worst_expected_loss",
        "normal_model"=>"unchanged_prescribed_plug_flow_reference_v1",
        "evaluation_rule"=>"independent_recovery_does_not_change_preplan",
    )
    r9_preplan_check(c, s)
    s
end

function r9_preplan_pairs(s)
    [(event = p["event"], fault = p["fault"]) for p in s["pairs"]]
end

function r9_preplan_check(c, s)
    r7_planning_assert(c)
    s["schema"]=="r9-preplan-spec-v1" &&
    s["version"]=="r9_prescribed_preplan_v1" &&
    s["case_sha256"]==c.sha256 &&
    s["normal_sha256"]==c.normal.sha256 &&
    s["currency"]==r7_currency(c.normal.data) &&
    s["service_objective"]==r7_service_objective(c.normal.data) &&
    s["mode"] in ("economic", "penalty", "threshold") &&
    s["event_rule"]=="sum_of_selected_event_worst_expected_loss" &&
    s["normal_model"]=="unchanged_prescribed_plug_flow_reference_v1" &&
    s["evaluation_rule"]=="independent_recovery_does_not_change_preplan" ||
        error("灾前对照规格身份或控制域错误")
    isfinite(s["penalty_MWh"]) && s["penalty_MWh"]>=0 || error("显式罚值须非负且有限")
    S=length(c.specification["events"])
    length(s["limits_MWh"])==S && all(x->isfinite(x)&&x>=0, s["limits_MWh"]) ||
        error("事件门槛缺失或非法")
    allowed=Set(r7_planning_pair_key(p) for p in r7_planning_pairs(c))
    selected=r9_preplan_pairs(s)
    all(
        p->p.event isa Integer &&
           !(p.event isa Bool) &&
           all(x->x isa Integer && !(x isa Bool), p.fault),
        selected,
    ) || error("事件序号和故障必须为整数，不能使用布尔值")
    keys=r7_planning_pair_key.(selected)
    !isempty(keys) && length(unique(keys))==length(keys) && all(k->k in allowed, keys) ||
        error("故障子集为空、重复或不属于原集合")
    Set(p.event for p in selected)==Set(1:S) || error("每个事件须声明至少一个比较故障")
    nothing
end

# 4B只放开策略门槛；总需求有限上界沿已有R8定义，不改变物理约束和正常输入。
function r9_preplan_carrier(c, s)
    r9_preplan_check(c, s)
    rules=deepcopy(c.specification)
    limits=s["mode"]=="threshold" ? s["limits_MWh"] : r8_loss_caps(c)
    for (e, limit) in zip(rules["events"], limits)
        e["loss_limit_MWh"]=limit
    end
    R7PlanningCase(c.normal, rules)
end

r9_preplan_objective(s) =
    s["mode"]=="penalty" ? "normal_cost_plus_selected_event_worst_loss_penalty" : "normal_cost"
