"""
    r9_flow_terminal_rows(case, stage)

独立重算单步WMM的末端入口温度和流量记忆（R9-V4），不读取求解器标志。
温度沿用A1的1e-4 K，流量沿用1e-6乘以一加输入全网流量上界；未提供数值时返回空表。
仅用于完整流量盒已核实为单步分段的R9输入；不能认证连续管内温度场或任意长管。
"""
function r9_flow_terminal_rows(c::R2Case, stage)
    audit_r9_flow_domain(c).pass || throw(ArgumentError("终端单步判据不适用"))
    rows = r9_terminal_rows(c, stage)
    haskey(stage, "values") || return rows
    h, T = c.data["heat"], c.data["T"]
    tolerance = 1e-6 * (1 + maximum(p["flow_max"] for p in h["pipes"]))
    for (p, pipe) in enumerate(h["pipes"])
        residual = abs(stage["values"]["m_pipe"][p][T] - last(pipe["flow_history"]))
        push!(
            rows,
            (;
                equation = "R9-V4-flow-memory",
                scope = "model",
                entity = string(p),
                t = T,
                residual,
                unit = "kg/s",
                tolerance,
                pass = isfinite(residual) && residual <= tolerance,
            ),
        )
    end
    return rows
end
