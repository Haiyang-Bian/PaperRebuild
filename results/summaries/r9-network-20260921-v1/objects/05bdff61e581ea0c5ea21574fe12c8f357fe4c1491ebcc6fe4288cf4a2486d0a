"""
    r9_transport_coefficients(m, m_previous, mass_kg, dt_s; loss_rate=0.0)

第3章WMM在当前和上一时段输送质量都严格大于管内质量时的解析消元（R9-V1—V3）。
流量为kg/s，管内质量为kg，步长为s，loss_rate为1/s。
返回α、β、温度权重、停留时间、衰减及对两项流量的导数；Jacobian列按当前、上一时段排列。
权重不依赖上一时段流量，但损耗依赖；历史流量的导数不自动成为决策变量。
等于分段边界或不在此分段时拒绝，不通过取整时延或截断权重代替通用WMM。
该函数不求解、不写文件，不能独立证明网络或周期状态可行。
"""
function r9_transport_coefficients(m, m_previous, mass_kg, dt_s; loss_rate = 0.0)
    all(isfinite, (m, m_previous, mass_kg, dt_s, loss_rate)) &&
    min(m, m_previous, mass_kg, dt_s) > 0 &&
    loss_rate >= 0 || throw(ArgumentError("需要有限正流量、质量、步长和非负损耗率"))
    q = mass_kg / dt_s
    q < min(m, m_previous) || throw(ArgumentError("不在严格单步WMM分段内"))
    alpha = [q / m, 0.0]
    beta = [1.0, q / m_previous]
    weights = [1 - q / m, q / m]
    Jweights = [q / m^2 0.0; -q / m^2 0.0]
    residence_s = mass_kg / 2 * (1 / m + 1 / m_previous)
    Jresidence = -mass_kg / 2 .* [1 / m^2, 1 / m_previous^2]
    attenuation = exp(-loss_rate * residence_s)
    Jattenuation = -loss_rate * attenuation .* Jresidence
    return (; alpha, beta, weights, Jweights, residence_s, Jresidence, attenuation, Jattenuation)
end

"""
    audit_r9_flow_domain(case)

只读核验R9每根管道的整个输入流量盒和历史是否属于R9-V1的严格单步分段。
返回逐管质量、流量下界、质量覆盖比和通过状态；通过仅证明消元适用，不证明调度可行。
保留输入原边界，不缩小流量域，不重新锚定温度或修改历史。
"""
function audit_r9_flow_domain(c::R2Case)
    h, dt = c.data["heat"], 3600c.data["dt_h"]
    rows = NamedTuple[]
    for (p, pipe) in enumerate(h["pipes"])
        history = pipe["flow_history"]
        isempty(history) && throw(ArgumentError("管道$(p)缺少流量历史"))
        all(isfinite, history) && all(>(0), history) || throw(ArgumentError("管道$(p)历史流量非法"))
        mass = h["rho_kg_m3"] * pipe["area_m2"] * pipe["length_m"]
        lower = min(pipe["flow_min"], minimum(history))
        ratio = mass / (dt * lower)
        pass = isfinite(ratio) && 0 < ratio < 1
        push!(
            rows,
            (;
                pipe = p,
                mass_kg = mass,
                dt_s = dt,
                lower_flow_kg_s = lower,
                mass_coverage_ratio = ratio,
                pass,
            ),
        )
    end
    return (; pass = !isempty(rows) && all(x.pass for x in rows), rows)
end
