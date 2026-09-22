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

"""
    r9_heat_memory_balance(case, values)

按R9-V5将单步WMM管道净热量分为损耗与入口温度记忆变化，单位MWh。
先核查整个流量盒；输运中间温度由独立累计质量回放重算，不读取优化器权重或star值。
记忆项为c_p*M*(入口末温-入口历史末温)/3.6e9；它是本离散WMM的守恒代理，
不冒充连续管内温度场的真实库存。返回逐管、逐方向账本及其总和，不求解或写文件。
该恒等式的闭合不能替代设备、电网、温度边界、终端或既有A1验收。
"""
function r9_heat_memory_balance(c::R2Case, values)
    audit_r9_flow_domain(c).pass || throw(ArgumentError("记忆恒等式仅支持完整单步域"))
    d, h = c.data, c.data["heat"]
    E, T = length(h["pipes"]), d["T"]
    for key in ("m_pipe", "tau_S_in", "tau_R_in", "tau_S_out", "tau_R_out")
        haskey(values, key) || throw(ArgumentError("缺少记忆账本输入$(key)"))
        array = values[key]
        length(array) == E && all(length(row) == T for row in array) ||
            throw(ArgumentError("记忆账本输入维度错误$(key)"))
        all(all(isfinite, row) for row in array) ||
            throw(ArgumentError("记忆账本输入含非有限值$(key)"))
    end
    all(
        p["flow_min"] <= values["m_pipe"][i][t] <= p["flow_max"] for
        (i, p) in enumerate(h["pipes"]), t in 1:T
    ) || throw(ArgumentError("记忆账本流量越出已核查域"))
    rows = NamedTuple[]
    for (p, pipe) in enumerate(h["pipes"]), side in ("S", "R")
        inlet, outlet = values["tau_"*side*"_in"][p], values["tau_"*side*"_out"][p]
        m = values["m_pipe"][p]
        mass = h["rho_kg_m3"] * pipe["area_m2"] * pipe["length_m"]
        factor = h["cp_J_kgK"] * d["dt_h"] / 1e6
        star = [r3_mass_replay(c, values, p, t, side).star for t in 1:T]
        net = factor * sum(m .* (inlet .- outlet))
        loss = factor * sum(m .* (star .- outlet))
        memory = h["cp_J_kgK"] * mass / 3.6e9 * (inlet[end]-last(pipe[side*"_history_K"]))
        push!(
            rows,
            (;
                pipe = p,
                side,
                net_MWh = net,
                attenuation_MWh = loss,
                memory_change_MWh = memory,
                residual_MWh = net-loss-memory,
            ),
        )
    end
    return (;
        rows,
        net_MWh = sum(r.net_MWh for r in rows),
        attenuation_MWh = sum(r.attenuation_MWh for r in rows),
        memory_change_MWh = sum(r.memory_change_MWh for r in rows),
        residual_MWh = sum(r.residual_MWh for r in rows),
    )
end
