# 原式、作者近似和项目单位恢复分别命名；不要在函数中静默修正文献疑点。
# region eq-ch02-004
"""
    chp_efficiency(P_CHP, P_CHP_max, α)

式（2-4）的三次发电效率，输入功率 MW、四个无量纲系数，返回效率比值。
仅求值；不据此推断非凸问题的最优性。式（2-1）分母缺少时间下标仍待澄清。
"""
function chp_efficiency(P_CHP, P_CHP_max, α)
    P_CHP_max > 0 && length(α) == 4 || throw(ArgumentError("CHP 额定值或系数不合法"))
    x = P_CHP / P_CHP_max
    return α[1] + α[2] * x + α[3] * x^2 + α[4] * x^3
end
# endregion eq-ch02-004

# region eq-ch02-001
"""
    chp_heat(P_CHP, η_G, η_loss)

作者在式（2-1）后采用的常效率近似，功率 MW，效率为比值，返回热功率 MW。
固定热电比 `(1-η_G-η_loss)/η_G`；不是变效率原式的完整实现。
"""
function chp_heat(P_CHP, η_G, η_loss)
    0 < η_G <= 1 && 0 <= η_loss < 1 && η_G + η_loss <= 1 ||
        throw(ArgumentError("CHP 效率与损耗不合法"))
    return P_CHP * (1 - η_G - η_loss) / η_G
end
# endregion eq-ch02-001

# region eq-ch02-005
"""
    pv_available(P_rated, f_PV, A_real, A_STC, α_power, τ, τ_STC)

式（2-5）的可用光伏功率 MW；辐照度必须同单位，温差 K，温度系数 1/K。
百分数系数由调用方除以 100。负出力表明公式超出适用范围，显式报错，不截零。
式（2-6）的实际调度功率可以小于本函数结果（弃光）。
"""
function pv_available(P_rated, f_PV, A_real, A_STC, α_power, τ, τ_STC)
    P_rated >= 0 && 0 <= f_PV <= 1 && A_real >= 0 && A_STC > 0 ||
        throw(ArgumentError("PV 输入不合法"))
    P = f_PV * P_rated * A_real / A_STC * (1 + α_power * (τ - τ_STC))
    P >= 0 || throw(DomainError(P, "PV 原式产生负可用功率"))
    return P
end
# endregion eq-ch02-005

# region eq-ch02-007
"""
    wind_ramp_paper(v, v_ci, v_r, v_co, P_rated)

忠实求值 PDF 31 式（2-7）中间段：速度 m/s，功率 MW。
原页使用 `v_co`，在区间内部可产生负值。本函数用于反例检查；禁止作为调度可用出力。
切入/切出端点分段重叠尚未澄清，因此这里只接收严格内部速度。
"""
function wind_ramp_paper(v, v_ci, v_r, v_co, P_rated)
    0 <= v_ci < v < v_r < v_co && P_rated >= 0 || throw(ArgumentError("风速必须在爬升段内部"))
    return P_rated * (v^3 - v_co^3) / (v_co^3 - v_ci^3)
end
# endregion eq-ch02-007

# region eq-ch02-012
"""
    battery_step(E_BS, P_BS_ch, P_BS_dis, η_BS_ch, η_BS_dis, Δt)

式（2-12）的电池一步状态：能量 MWh、功率 MW、时间 h、效率比值。
原式未写时间步长；这里显式恢复 Δt，Δt=1 h 与原式数值一致。E 不是 SOC。
互斥、容量和周期边界由建模层约束，本函数只计算状态。
"""
function battery_step(E_BS, P_BS_ch, P_BS_dis, η_BS_ch, η_BS_dis, Δt)
    0 < η_BS_ch <= 1 && 0 < η_BS_dis <= 1 && Δt > 0 || throw(ArgumentError("电池效率或步长错误"))
    return E_BS + Δt * (η_BS_ch * P_BS_ch - P_BS_dis / η_BS_dis)
end
# endregion eq-ch02-012

# region eq-ch02-016
"""
    heat_storage_step_paper(E_HS, H_HS_ch, H_HS_dis, η_HS_ch, η_HS_dis, η_HS_loss, Δt)

忠实保留式（2-16）的充热除效率、放热乘效率；单位 MWh、MW、h。
η_HS_loss 按每步存留率解释，Δt 是项目显式单位恢复。
效率小于 1 时原式可能违反被动储能能量关系；返回值不能当作物理正确性的保证。
"""
function heat_storage_step_paper(E_HS, H_HS_ch, H_HS_dis, η_HS_ch, η_HS_dis, η_HS_loss, Δt)
    0 < η_HS_ch <= 1 && 0 < η_HS_dis <= 1 && 0 <= η_HS_loss <= 1 && Δt > 0 ||
        throw(ArgumentError("热储能效率或步长错误"))
    return η_HS_loss * E_HS + Δt * (H_HS_ch / η_HS_ch - η_HS_dis * H_HS_dis)
end
# endregion eq-ch02-016

# region eq-ch02-072
"""
    building_step(τ_previous, H_D_hat, τ_AM, η_H, U)

式（2-72）的隐式温度递推等价改写，返回 K；热需求 MW，η_H 单位 K/MW，U 无量纲。
两系数已包含标定步长，不能跨步长复用。原式不是直接给出热容和传热系数的连续 RC 模型。
"""
function building_step(τ_previous, H_D_hat, τ_AM, η_H, U)
    η_H > 0 && U >= 0 || throw(ArgumentError("建筑离散系数不合法"))
    return (τ_previous + η_H * H_D_hat + U * τ_AM) / (1 + U)
end
# endregion eq-ch02-072

# region eq-ch02-029
"""
    heat_power(m, τ_S, τ_R; c_w=4.2)

式（2-29）/（2-32）的热功率换算：质量流率 kg/s、温度 K、比热 kJ/(kg K)，返回 MW。
负荷使用流入用热器的正流量；作者网络节点注入在负荷处为负，应先取其相反数。
"""
heat_power(m, τ_S, τ_R; c_w = 4.2) = c_w * m * (τ_S - τ_R) / 1000
# endregion eq-ch02-029

"""
    electrical_bases(S_base_MVA, V_base_kV)

三相平衡标幺基值换算，输入总三相 MVA 和线电压 kV，返回阻抗 Ω 与电流 kA 基值。
对应式（2-22）—（2-28）的项目单位约定；幅值需平方后才能对应 v/l。
"""
function electrical_bases(S_base_MVA, V_base_kV)
    S_base_MVA > 0 && V_base_kV > 0 || throw(ArgumentError("电气基值必须为正"))
    return (Z_ohm = V_base_kV^2 / S_base_MVA, I_kA = S_base_MVA / (sqrt(3) * V_base_kV))
end
