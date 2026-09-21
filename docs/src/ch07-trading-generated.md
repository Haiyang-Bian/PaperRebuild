# 八聚合商交易：台账索引

由 `docs/reading/ch07/trading.toml` 生成。

| 编号 | 含义 | 状态 | Julia API |
|---|---|---|---|
| R9-T1 | 主体净注入与电热节点分别聚合；共用H26不重复叠加背景负荷 | project_scale_mapping | [`r9_trading_case`](@ref) |
| R9-T2 | 原设备关系及项目凸负荷偏好；HP/EB按已知数值表解释 | adopted_with_explicit_replacements | [`build_r9_trading_model`](@ref) |
| R9-T3 | 电池/热储能逐时互斥、时间步长与周期能量 | project_boundary_and_missing_parameter_replacement | [`validate_r9_trading_solution`](@ref) |
| R9-T4 | 固定电网支路关系、锥松弛与原等式分开验收 | derived_from_ch04_030_033 | [`build_r9_trading_model`](@ref) |
| R9-T5 | 双向互斥热弧、每管对一次参考损耗及质量/能量包络 | project_steady_envelope_not_temperature_field | [`validate_r9_trading_solution`](@ref) |
| R9-T6 | 资源目标、确定性合同分解与内部现金抵消 | project_teaching_settlement_not_bargaining | [`r9_trading_ledger`](@ref) |
| R9-T7 | 忽略损耗和电热耦合的必要容量割；无违反不证明原模型可行 | project_independent_diagnostic | [`audit_r9_trading_capacity`](@ref) |
| R9-T8 | 计入强制参考损耗与末端馈线电锅炉上界的热区域必要容量割 | project_derived_and_exact_frozen_matrix_witness | [`r9_trading_heat_cut`](@ref) |

| ID | 符号 | 含义 | 单位 | Julia |
|---|---|---|---|---|
| r9.trading.actor | ``a`` | 主体；DSO编号1，A1至A8编号2至9 | 1 | `actors[a]` |
| r9.trading.device | ``g`` | 设备，归属与电/热节点分别登记 | 1 | `devices[g]` |
| r9.trading.power | ``P_{g,t}^{\rm gen},P_{g,t}^{\rm cons}`` | 设备电力注入与消耗；热量使用H | MW | `P_gen[g,t], P_cons[g,t]` |
| r9.trading.storage | ``E_{g,t}`` | 时段开始的电/热能量状态，末端另有T+1状态 | MWh | `E[g,t]` |
| r9.trading.heat_direction | ``y_{p,t}^{+},y_{p,t}^{-}`` | 一对管道的热传递方向，二者之和为1；仍是温热管网假设 | 1 | `heat_direction[p,t], 1-heat_direction[p,t]` |
| r9.trading.flow | ``m_{p,t}^{\sigma}`` | 按所选正向/反向弧定义的非负质量流量 | kg/s | `m_plus[p,t], m_minus[p,t]` |
| r9.trading.heat | ``H_{p,t}^{\sigma,\rm in},H_{p,t}^{\sigma,\rm out}`` | 管对入口和出口热功率；不同于完整供回水温度场 | MW | `H_plus_in[p,t], H_plus_out[p,t], H_minus_in[p,t], H_minus_out[p,t]` |
| r9.trading.preference | ``w_{a,t}^{P},w_{a,t}^{H}`` | 凸二次不满意度的每小时费用上图变量 | CNY/h | `w_P[a,t], w_H[a,t]` |
| r9.trading.cash | ``C_a^{\rm cash}`` | 主体内部结算净收入；正数为收入 | CNY | `internal_cash_CNY` |
| r9.trading.cut | ``A,\delta(A)`` | 诊断热节点集合及其边界管对；内部管对另计参考损耗 | 1 | `nodes, crossing_pipes, internal_pipes` |
| r9.trading.capacity_deficit | ``D_A^{H,\min}+L_A-\widehat H_A^{\max}-C_{\delta(A)}`` | 必要容量缺口；正值为容量矛盾，无正值不证明可行 | MW | `deficit_MW, exact_deficit` |

## 采用解释与缺口

| ID | 出处 | 状态 | 含义 |
|---|---|---|---|
| R9-TQ01 | PDF132 text and table7-9 | source_ambiguity; explicit_before_factor_interpretation | 表7-9是否已扩大1.5倍未说明；采用先分离背景、再只放大主体负荷一次。不能称作者原输入。 |
| R9-TQ02 | PDF132 tables7-7 and7-9 | source_ambiguity; numeric_EB_conversion_adopted | 资源栏HP与数值表EB身份不同；按表列热容量及0.94/0.92效率解释，不发明额外HP或COP。 |
| R9-TQ03 | PDF132 text; missing heat-store nameplates | explicit_synthetic_replacement | 两台储热各0.5MW/2MWh和储能效率/初末状态均为项目参数；电池50元/MWh按吞吐量解释。 |
| R9-TQ04 | project model boundary | full_thermal_compatibility_and_reconfiguration_pending | 双向稳态能量/质量包络不保证混合温度、水压或动态输运。温热管对即使负荷小仍承担参考散热。 |
| R9-TQ05 | PDF133-135 schemes2A/2B/2C | benchmark_not_equivalent_to_2B_2C | 集中资源目标与教学结算是迁移基准；分布式协调、重构、议价和原表绝对效用尚未由本入口复现。 |
| R9-TQ06 | project network sizing protocol; frozen scale input and literal capacity witness | legacy_synthetic_incompatibility_proved; separate_v2_network_design_tested | 基础7.1设备/未放大负荷的替代网络设计未覆盖7.3新增电锅炉接入与跨热区送出。第8时段精确正缺口0.080119MW证明该旧输入/采用模型冲突；不归因于作者原输入，不据此宣称单处增容足够。另立v2设备接入/重构16项见network.toml及ch07-network-results.md，不迁移旧判定。 |

## 运行与独立重验

| Julia API | 测试位置 |
|---|---|
| [`solve_r9_trading_case`](@ref) | `test/r9_trading_runs.jl` |
| [`validate_r9_trading_run`](@ref) | `test/r9_trading_runs.jl` |
| [`save_r9_trading_run`](@ref) | `test/r9_trading_runs.jl` |
| [`read_r9_trading_run`](@ref) | `test/r9_trading_runs.jl` |
| [`compare_r9_trading_runs`](@ref) | `test/r9_trading_runs.jl` |
