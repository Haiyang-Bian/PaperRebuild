# region r2-transport
"""
    water_mass_weights(flows, volume_mass, dt_s)

式（3-27）—（3-33）的数值水质权重。`flows` 按当前、前一时段、…排列（kg/s），
`volume_mass` 为管内水质量 kg，`dt_s` 为秒。返回 α、β 与出口质量比例 w。
逐段填充固定质量，独立于优化模型；所有流量严格为正，历史不足报错。
"""
function water_mass_weights(flows, volume_mass, dt_s)
    all(isfinite, flows) &&
    all(>(0), flows) &&
    isfinite(volume_mass) &&
    volume_mass > 0 &&
    isfinite(dt_s) &&
    dt_s > 0 || throw(ArgumentError("水质法需要有限正流量、管内质量与时间步长"))
    function fill_mass(start)
        weights = zeros(length(flows))
        remaining = volume_mass
        for i in start:length(flows)
            weights[i] = min(1.0, remaining / (flows[i] * dt_s))
            remaining = max(0.0, remaining - flows[i] * dt_s)
        end
        remaining <= 1e-10 * max(1, volume_mass) || throw(ArgumentError("流量历史不足"))
        return weights
    end
    α, β = fill_mass(1), fill_mass(2)
    β[1] = 1.0
    w = (β - α) .* flows ./ first(flows)
    return (; α, β, w)
end

"""
    replay_water_mass(inlet, flow, inlet_history, flow_history; mass_kg, dt_h, ...)

独立回放式（3-27）—（3-34）：输入 K、kg/s，历史按最早到 t=0 排列。
热损耗采用补全版的负指数，`epsilon_W_mK`、`area_m2`、`rho_kg_m3`、`cp_J_kgK`
均为 SI。WMM 用 α 与 β[滞后≥1] 的和估计停留时间；不冒称与 R1 的有损核相同。
返回无损出口、出口温度、每时段权重和停留秒数；不求解或写文件。
"""
function replay_water_mass(
    inlet,
    flow,
    inlet_history,
    flow_history;
    mass_kg,
    dt_h,
    epsilon_W_mK = 0.0,
    area_m2 = 0.01,
    rho_kg_m3 = 1000.0,
    cp_J_kgK = 4200.0,
    ambient_K = 293.0,
)
    length(inlet) == length(flow) || throw(ArgumentError("入口与流量时序长度不一致"))
    length(inlet_history) == length(flow_history) || throw(ArgumentError("历史长度不一致"))
    all(isfinite, vcat(inlet, inlet_history)) || throw(ArgumentError("温度必须有限"))
    epsilon_W_mK >= 0 && area_m2 > 0 && rho_kg_m3 > 0 && cp_J_kgK > 0 ||
        throw(ArgumentError("非法传热参数"))
    values, flows = vcat(inlet_history, inlet), vcat(flow_history, flow)
    out, star, residence = Float64[], Float64[], Float64[]
    weights = NamedTuple[]
    for t in eachindex(flow)
        i = length(flow_history) + t
        w = water_mass_weights(reverse(flows[1:i]), mass_kg, 3600 * dt_h)
        τ_star = sum(w.w .* reverse(values[1:i]))
        seconds = dt_h * 3600 / 2 * (sum(w.α) + sum(w.β[2:end]))
        τ =
            ambient_K +
            (τ_star - ambient_K) * exp(-epsilon_W_mK * seconds / (rho_kg_m3 * cp_J_kgK * area_m2))
        push!(out, τ)
        push!(star, τ_star)
        push!(residence, seconds)
        push!(weights, w)
    end
    return (; outlet = out, lossless = star, residence_s = residence, weights)
end
# endregion r2-transport

# region r2-envelope
"""
    mccormick_bounds(x, y, xbounds, ybounds)

式（3-42）的乘积包络，返回 xy 的下、上界。先对无系数的乘积建包络，再乘比热和单位因子；
避免原式第二项缺少比热的问题。有限且有序的变量盒为必要条件，退化盒允许。
"""
function mccormick_bounds(x, y, xb, yb)
    all(isfinite, (xb..., yb...)) && xb[1] <= xb[2] && yb[1] <= yb[2] ||
        throw(ArgumentError("McCormick 需要有限有序边界"))
    l, u = xb
    a, b = yb
    return (
        lower = max(l * y + a * x - l * a, u * y + b * x - u * b),
        upper = min(u * y + a * x - u * a, l * y + b * x - l * b),
    )
end
# endregion r2-envelope
