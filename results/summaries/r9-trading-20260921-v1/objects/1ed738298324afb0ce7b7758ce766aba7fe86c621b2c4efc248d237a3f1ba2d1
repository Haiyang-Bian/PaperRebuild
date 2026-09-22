"""
    R4TSPASpec(; penalty=10000.0, weight_rule=:capacity_load_v1)

第4章两阶段结构的项目解释。penalty单位为合成美元/h/单位归一化违反；
仅松弛节点P/Q/H/质量平衡，边界、设备及支路关系保持硬约束。
原文PDF73未说明逐项松弛和罚项是否进入分歧效用，因此后者同时输出两种口径。
无限额转移、静态热能流仍是本批边界，不把反事实分歧点称为可执行调度。
"""
struct R4TSPASpec
    penalty::Float64
    weight_rule::Symbol
    function R4TSPASpec(; penalty = 10000.0, weight_rule = :capacity_load_v1)
        isfinite(penalty) && penalty>0 || error("罚系数须为有限正数")
        weight_rule in (:capacity_load_v1, :equal_v1) || error("未知权重")
        new(Float64(penalty), weight_rule)
    end
end

"""
    r4_tspa_scales(case)

仅从输入冻结节点平衡松弛的单位尺度。电功率/无功用至少1的接网容量，
热功率用至少1MW的总设备额定供热能力，质量流率用至少1kg/s的最大管道容量。
所有松弛乘Δt_h后计罚；这些尺度不修改物理验收A1。
"""
function r4_tspa_scales(c::R4Case)
    d=c.data
    return Dict(
        "P"=>max(1.0, d["electric"]["grid_max"]),
        "Q"=>max(1.0, d["electric"]["Q_grid_max"]),
        "H"=>max(
            1.0,
            sum(
                a["heat_ratio"]*a["CHP_max"]+a["COP_HP"]*a["HP_max"]+a["COP_EB"]*a["EB_max"] for
                a in d["actors"]
            ),
        ),
        "m"=>max(1.0, maximum(p["flow_max"] for p in d["heat"]["pipes"])),
    )
end

const R4_CONTROL_KEYS=(
    "P_CHP",
    "P_PV",
    "P_HP",
    "P_EB",
    "P_ch",
    "P_dis",
    "P_D",
    "H_D",
    "H_src",
    "w_P",
    "w_H",
    "E",
)

function r4_tspa_spec(s::R4TSPASpec)
    return Dict(
        "model"=>"r4_tspa_checked_v1",
        "penalty"=>s.penalty,
        "penalty_unit"=>"USD_synthetic_per_h_per_normalized_violation",
        "weight_rule"=>String(s.weight_rule),
        "elastic_scope"=>"nodal_balance_elastic_v1",
        "disagreement_variants"=>["penalty_excluded", "penalty_included"],
    )
end
