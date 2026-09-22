# region eq-ch02-047
"""
    fixed_flow_kernel(m, ρ_w, A, L, Δt, ε; c_w=4.2)

式（2-47）—（2-54）的恒定正向质量流率特例。输入 kg/s、kg/m³、m²、m、h、W/(m K)。
输出两个时间滞后、精确质量重叠权重及作者 J 衰减因子。Δt 转秒、c_w 转 J/(kg K)。
非整步延迟采用两段加权，不四舍五入。J 保留作者 χ+1/2 形式，不等同连续 PDE 的解析衰减。
"""
function fixed_flow_kernel(m, ρ_w, A, L, Δt, ε; c_w = 4.2)
    all(x -> isfinite(x) && x > 0, (m, ρ_w, A, L, Δt, c_w)) && isfinite(ε) && ε >= 0 ||
        throw(ArgumentError("仅支持恒定正向流量与正管道容积"))
    ΔT = 3600 * Δt
    d = ρ_w * A * L / (m * ΔT)
    a = ceil(Int, d)
    return (
        lags = (a, a - 1),
        weights = (1 - a + d, a - d),
        J = exp(-ε * ΔT / (1000 * c_w * ρ_w * A) * (a - 0.5)),
        delay_steps = d,
    )
end

"""
    pipe_outlet(τ_in, history, kernel, τ_AM)

从入口时段平均温度 K 计算出口 K（式 2-47、2-48）。历史按最早到 t=0 排列。
历史至少覆盖最大滞后；即使温度在窗口之前已进入管道，也不能补零。环境为恒定 K。
支持 JuMP 仿射表达式；不启动求解。
"""
function pipe_outlet(τ_in, history, kernel, τ_AM)
    length(history) >= maximum(kernel.lags) || throw(ArgumentError("管道入口历史不足"))
    return [
        τ_AM +
        kernel.J * (
            sum(
                w * (t - lag > 0 ? τ_in[t-lag] : history[end+t-lag]) for
                (lag, w) in zip(kernel.lags, kernel.weights)
            ) - τ_AM
        ) for t in eachindex(τ_in)
    ]
end
# endregion eq-ch02-047

# region eq-ch02-042
"""
    mix_temperature(m_in, τ_in)

式（2-42）—（2-43）的正向入流混合特例，kg/s 与 K，返回 K。
所有参与混合的流必须按流入方向列出；总流量为零时温度无定义，拒绝求值。
"""
function mix_temperature(m_in, τ_in)
    length(m_in) == length(τ_in) && all(>=(0), m_in) && sum(m_in) > 0 ||
        throw(ArgumentError("混合需要非负入流和正总流量"))
    return sum(m_in .* τ_in) / sum(m_in)
end
# endregion eq-ch02-042
