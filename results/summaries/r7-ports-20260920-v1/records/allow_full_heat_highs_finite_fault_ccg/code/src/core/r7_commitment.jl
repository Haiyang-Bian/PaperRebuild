"""
    R7CHPSpec(data)

第6章灾前CHP约束块的显式输入，不是完整正常调度案例。功率MW/Mvar、时间h、
启机费USD/次、运行费USD/MWh。启停跨新能源场景共享，P/Q按时间、场景排列。
必须给出窗口前状态、已持续时间、各场景前一出力及末端规则；不默认冷启动或周期启停。
"""
struct R7CHPSpec
    data::Dict{String,Any}
    sha256::String
end

function R7CHPSpec(input::AbstractDict)
    d=TOML.parse(r7_text(input))
    d["schema"]=="r7-chp-component-v1" || error("CHP约束块输入版本错误")
    d["id"] isa String && !isempty(strip(d["id"])) || error("CHP身份缺失")
    d["periods"] isa Integer && d["periods"]>0 || error("CHP时域错误")
    isfinite(d["dt_h"]) && d["dt_h"]>0 || error("CHP时间步错误")
    d["previous_commitment"] in (0, 1) || error("窗口前启停不是二值")
    for key in (
        "previous_duration_h",
        "min_on_h",
        "min_off_h",
        "P_min_MW",
        "P_max_MW",
        "Q_min_Mvar",
        "Q_max_Mvar",
        "ramp_MW_h",
        "startup_MW",
        "shutdown_MW",
        "startup_cost_USD",
        "cost_P_USD_MWh",
    )
        isfinite(d[key]) && d[key]>=0 || error("CHP参数错误：$key")
    end
    d["P_min_MW"]<=d["P_max_MW"] && d["Q_min_Mvar"]<=d["Q_max_Mvar"] || error("CHP功率上下界倒置")
    isfinite(d["heat_ratio"]) && d["heat_ratio"]>0 || error("CHP热电比错误")
    d["cost_basis"]=="electric_equivalent" ||
        error("本约束块按可见6-1以电出力计综合CHP费用，不静默相加热成本")
    d["terminal_rule"] in ("carry_obligation", "complete_within_horizon") ||
        error("CHP末端启停规则必须显式给出")
    p=Float64.(d["probabilities"])
    !isempty(p) && all(isfinite, p) && all(>(0), p) && abs(sum(p)-1)<=1e-8 ||
        error("CHP场景概率错误")
    r7_numbers(
        d["previous_P_MW"],
        (length(p),),
        "窗口前CHP出力";
        lo = d["P_min_MW"]*d["previous_commitment"],
        hi = d["P_max_MW"]*d["previous_commitment"],
    )
    R7CHPSpec(d, r7_digest(d))
end

function r7_chp_assert(s::R7CHPSpec)
    r7_digest(s.data)==s.sha256 || error("CHP规格构造后改变")
end

# 离散开停动作只发生在区间起点；非整步最短时长需要向上取整，不能向下缩短。
r7_chp_steps(hours, dt) = ceil(Int, hours/dt)
