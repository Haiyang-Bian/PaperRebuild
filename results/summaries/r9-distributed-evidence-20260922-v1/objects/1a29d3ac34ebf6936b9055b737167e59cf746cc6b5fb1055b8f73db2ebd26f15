"""
    reconstruct_r3_pressure(case, result)

在已核查的 WMM 模型中重构 κ=μm²（式3-25）。当前 κ 只满足 0≤κ≤压力上界、
ΔΦ≥κ≥μm²，且不进入目标；降低 κ 不改变控制量、成本和其他约束。
返回独立副本，不修改原始解。仅接受已通过模型A1的 exact/WMM 调度结果；
重构后仍须独立检查电网及所有热关系，不能据此宣布全文物理正确。
"""
function reconstruct_r3_pressure(c::R2Case, result)
    spec = r2_spec_from_dict(result["spec"])
    spec == R2Spec() || throw(ArgumentError("压力重构仅支持已核查的WMM解释"))
    get(result, "objective_kind", "operating_cost") == "operating_cost" ||
        throw(ArgumentError("诊断/修正目标不得沿用调度重构前提"))
    validate_r2_solution(c, result).model_pass ||
        throw(ArgumentError("原解未通过模型A1，不满足重构前提"))
    out = deepcopy(result)
    for side in ("S", "R"), (p, pipe) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"]
        out["values"]["kappa_"*side][p][t] = pipe["mu_kPa_s2_kg2"] * out["values"]["m_pipe"][p][t]^2
    end
    out["transformation"] = "kappa_equal_mu_m2_v1"
    return out
end

function r3_operating_cost(c, v)
    d = c.data
    return d["dt_h"] * (
        sum(d["grid_price"] .* v["P_grid"]) +
        sum(g["cost_per_MWh"] * sum(v["P_device"][i]) for (i, g) in enumerate(d["devices"]))
    )
end

function r3_distance(c, flow, initial)
    return sum(
        abs(flow[p, t]-initial[p, t])/(pipe["flow_max"]-pipe["flow_min"]) for
        (p, pipe) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"] if
        pipe["flow_max"] > pipe["flow_min"];
        init = 0.0,
    )
end
