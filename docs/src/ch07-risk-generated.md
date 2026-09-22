# 第7.4节风险比较台账

由`docs/reading/ch07/risk-study.toml`生成；仅保证声明有限支持，未完成样本外验收。

| 公式 | 含义 | Julia API |
|---|---|---|
| R9-RK1 | 合成PV/正上调完整轨迹到MW出力与互斥调用比例的映射 | [`r9_reserve_risk_case`](@ref) |
| R9-RK2 | 三方案共同严格交付，delta=0；不同于联合室温风险epsilon | [`R9ReserveStudySpec`](@ref) |
| R9-RK3 | 固定支持概率运输集合；费用与联合事件分别取各自最坏分布 | [`r9_reserve_risk_case`](@ref) |
| R9-RK4 | 3A支持最坏/硬舒适、3B经验概率/机会约束、3C运输球/机会约束 | [`r9_reserve_risk_case`](@ref) |

| 符号ID | 原记号 | 含义 | 单位 | 代码 |
|---|---|---|---|---|
| r9.risk.a | ``a_{s,t}`` | 完整日有符号调用，正为上调；每小时仅允许一个方向 | 1 | `training.values[2,t,s]` |
| r9.risk.pv | ``p_{s,t}^{PV}`` | 所有PV共用的额定出力比例；共同天气是项目合成假设 | 1 | `training.values[1,t,s]` |
| r9.risk.delta | ``\delta`` | 交付误差预算系数；本批三方案均为0，不继承模板0.1 | 1 | `delivery_delta` |
| r9.risk.epsilon | ``\epsilon`` | 任一楼宇时段舒适越界的联合事件上限；3A为0、3B/3C为0.05 | 1 | `epsilon` |
| r9.risk.rho | ``\rho`` | 归一化完整轨迹RMS距离上的质量运输预算；非统计置信半径 | normalized_trajectory | `ambiguity.radius` |
| r9.risk.z | ``z_s`` | 整条情景允许退到声明物理温度界；实际越界事件另行重算 | 1 | `z[s]` |
