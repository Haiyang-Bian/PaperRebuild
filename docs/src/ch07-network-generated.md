# 接入参数与重构：台账索引

由 `docs/reading/ch07/network.toml` 生成。

| 编号 | 含义 | Julia API |
|---|---|---|
| R9-RN1 | 候选图、可控边、全节点连通径向；虚拟流不限制物理输送方向 | [`build_r9_trading_model`](@ref) |
| R9-RN2 | 开路时潮流与电流平方归零，电压差只保留原电压边界；闭路恢复制约 | [`validate_r9_trading_solution`](@ref) |
| R9-RN3 | 精确动作异或、稳定窗口与最多动作次数；日阀门只相对初始状态计一次 | [`validate_r9_network`](@ref) |
| R9-RN4 | 正反热弧之和等于日阀门状态；关闭时两弧、质量流量与损耗均为零 | [`build_r9_trading_model`](@ref) |
| R9-RN5 | 资源成本加运营商动作成本，按CNY/次、不乘时间步；内部支付继续抵消 | [`r9_trading_ledger`](@ref) |

| ID | 原符号 | 含义 | Julia | 单位 |
|---|---|---|---|---|
| r9.network.uE | ``u^E_{e,t}`` | 电线路闭合状态；非开关位置保持初始值 | `u_E[e,t]` | 1 |
| r9.network.uH | ``u^H_p`` | 热管整日阀门状态，数组第二维长度为1 | `u_H[p,1]` | 1 |
| r9.network.aE | ``a^E_{e,t}`` | 电开关相邻状态之差的绝对值 | `a_E[e,t]` | 1 |
| r9.network.aH | ``a^H_p`` | 热阀门相对初始状态的一次动作 | `a_H[p,1]` | 1 |
| r9.network.flow | ``F^E_{e,t},F^H_p`` | 证明连通的虚拟商品流，无物理能量含义 | `F_E[e,t], F_H[p,1]` | 1 |
| r9.network.direction | ``y^+_{p,t},y^-_{p,t}`` | 双向热弧，二者之和为uH；旧v1的和为1仍保留 | `heat_direction[p,t], u_H[p,1]-heat_direction[p,t]` | 1 |
| r9.network.cost | ``c^{SA},c^{VA}`` | 电开关和热阀门动作资源费用；项目合成参数 | `electric_action_CNY, heat_action_CNY` | CNY/次 |

## 采用解释与边界

| ID | 状态 | 内容 |
|---|---|---|
| R9-RNC01 | explicit_project_design | 原文没有完整支路参数。legacy保留原额定值；equipment按所有新增设备及最大灵活负荷重建设计包络，阻抗、容量及损耗一起变化，不是仅增容的单因素因果实验。 |
| R9-RNC02 | source_switch_locations_with_project_operating_parameters | 图7-6辨识六条原电支路开关与四联络线、两条原热支路阀门与两联络管；其余支路不新增控制。动作费5CNY/次、两步稳定及每电线最多两次为项目设定。 |
| R9-RNC03 | construction_rule_corrected_before_optimization | 构造测试发现路径大管径UA求和与路径最小容量混配可使联络管损耗超过额定容量。正式冻结前改为路径总长、最小容量、按该容量设计自身截面及SI传热；不是根据运行收益改参。 |
| R9-RNC04 | same_design_comparison_only | 同一设计的fixed/joint具有相同候选支路参数、损耗、核心输入与动作费。fixed零动作计划可嵌入joint。新输入不能被旧固定树热割直接诊断，避免把关闭管道损耗当作必须承担。 |
| R9-RNC05 | bounded_scope | 热网仍是稳态质量/能量包络，缺少温度混合、水压、动态换向及启停暖管能量；尾端拓扑自由，不报告周期重构收益。继承的provenance记录父输入，实际拓扑域以v2 network_control为准。 |
