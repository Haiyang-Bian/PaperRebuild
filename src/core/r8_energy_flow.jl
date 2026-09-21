"""
    r8_energy_spec(case; pipe_capacity_MW, mode=:threshold, limits_MWh=nothing,
                   loss_rule=:reference_UA, penalty_USD_MWh=nothing, penalty_MWh=nothing,
                   topology=:reconfigure)

R8-E1至E3：作者PDF123方案3.1的项目采用版，仅保留逐时热能流节点平衡。
管道容量必须显式给出（MW）；reference_UA用输入参考供回温及环境计算固定散热，
lossless仅接受UA均为零的共同输入。没有温度、质量流、水压、空间状态或管网末端库存约束。
这些舍弃项属于对照模型差异，不是原热模型的等价变换，也不认证作者未公开的具体损耗规则。
经济、逐事件门槛和罚项的目标语义与R8详细模型一致。输入不改写。
v2显式传penalty_MWh，单位为正常输入币种/MWh；v1省略旧USD关键字时仍使用500 USD/MWh。
"""
function r8_energy_spec(
    c::R7PlanningCase;
    pipe_capacity_MW,
    mode = :threshold,
    limits_MWh = nothing,
    loss_rule = :reference_UA,
    penalty_USD_MWh = nothing,
    penalty_MWh = nothing,
    topology = :reconfigure,
)
    s=Dict{String,Any}(
        "schema"=>r7_money_schema(c.normal.data, "r8-energy-spec-v1"),
        "version"=>"r8_energy_flow_checked_v1",
        "case_sha256"=>c.sha256,
        "mode"=>String(mode),
        "loss_rule"=>String(loss_rule),
        "pipe_capacity_MW"=>Float64.(pipe_capacity_MW),
        "limits_MWh"=>limits_MWh===nothing ?
                      [e["loss_limit_MWh"] for e in c.specification["events"]] :
                      Float64.(limits_MWh),
        r7_money_key(c.normal.data, "penalty_USD_MWh")=>r8_penalty_value(
            c.normal.data,
            penalty_USD_MWh,
            penalty_MWh,
        ),
        "recovery_topology"=>String(topology),
        "event_rule"=>"sum_of_event_worst_expected_unserved_energy",
        "economic_rule"=>"normal_only_then_independent_recourse",
        "heat_domain"=>"directed_energy_balance_without_storage_or_temperature",
    )
    r7_currency_record!(s, c.normal.data)
    r8_energy_check(c, s)
    s
end

function r8_energy_check(c, s)
    r7_check_currency_record(c.normal.data, s)
    r7_check_money_fields(c.normal.data, s, ("penalty_USD_MWh",))
    r7_planning_assert(c)
    s["schema"]==r7_money_schema(c.normal.data, "r8-energy-spec-v1") &&
    s["version"]=="r8_energy_flow_checked_v1" &&
    s["case_sha256"]==c.sha256 &&
    s["mode"] in ("economic", "threshold", "penalty") &&
    s["loss_rule"] in ("lossless", "reference_UA") &&
    s["recovery_topology"] in ("reconfigure", "retain_surviving") &&
    s["heat_domain"]=="directed_energy_balance_without_storage_or_temperature" &&
    s["event_rule"]=="sum_of_event_worst_expected_unserved_energy" &&
    s["economic_rule"]=="normal_only_then_independent_recourse" || error("稳态能流规格错误")
    ps=c.normal.data["heat"]["pipes"]
    length(s["pipe_capacity_MW"])==length(ps) && all(x->isfinite(x)&&x>=0, s["pipe_capacity_MW"]) ||
        error("管道能流容量缺失或非有限")
    length(s["limits_MWh"])==length(c.specification["events"]) &&
    all(x->isfinite(x)&&x>=0, s["limits_MWh"]) || error("事件门槛错误")
    isfinite(s[r7_money_key(c.normal.data, "penalty_USD_MWh")]) &&
    s[r7_money_key(c.normal.data, "penalty_USD_MWh")]>0 || error("罚项价格错误")
    s["loss_rule"]=="lossless" &&
        any(p["UA_$(side)_W_K"]!=0 for p in ps for side in ("S", "R")) &&
        error("lossless要求共同输入UA=0，不能静默取消损耗")
    all(x->isfinite(x)&&x>=0, r8_energy_losses(c.normal.data, s)) || error("参考热损耗为负或非有限")
    nothing
end

function r8_energy_losses(d, s)
    h=d["heat"]
    [
        s["loss_rule"]=="lossless" ? 0.0 :
        sum(
            p["UA_$(side)_W_K"]*(h["$(side)_reference_K"]-h["ambient_K"][t]) for side in ("S", "R")
        )/1e6 for p in h["pipes"], t in 1:d["periods"]
    ]
end

const R8_ENERGY_NORMAL_REMOVED=(
    "τ_S",
    "τ_R",
    "τ_source",
    "τ_load",
    "τ_pipe_S",
    "τ_pipe_R",
    "E_pipe_S",
    "E_pipe_R",
    "Φ_S",
    "Φ_R",
    "Φ_val_S",
    "Φ_val_R",
)
const R8_ENERGY_RECOVERY_REMOVED=("m_pipe", "m_source", "m_load", R7_TRANSPORT_PROXY_VARIABLES...)
