# R9采用式与符号索引

<!-- generated from docs/reading/ch07/{pv-adoption,numerics,flow}.toml; edit those ledgers -->

推导和边界见[固定模式基准](ch07-pv.md)，结果见[数值边界报告](ch07-pv-results.md)。

| ID | 含义 | 解释类别 | Julia API |
|---|---|---|---|
| R9-P1 | 视在功率与有功/无功；合成节点与时间分配 | `project_input_conversion` | [`r9_pv_case`](@ref) |
| R9-P2 | 线路电阻按电压基准折算；固定额定变比的理想变压器 | `project_equivalent_network` | [`audit_r9_pv_input`](@ref) |
| R9-P3 | 由参考质量流量与速度确定截面积；圆筒导热和固定Darcy系数 | `project_pipe_design` | [`r9_pv_case`](@ref) |
| R9-P4 | 固定流量源/荷端口供回温差与热功率 | `source_heat_relation_with_declared_units` | [`audit_r9_pv_input`](@ref) |
| R9-P5 | 给定CF-CT日曲线按树计算周期WMM参考历史，不求解优化 | `project_periodic_reference_boundary` | [`audit_r9_pv_input`](@ref) |
| R9-P6 | 最终入口序列等于冻结初始历史；以最小流量所需记忆长度约束 | `project_terminal_memory` | [`build_r9_pv_model`](@ref) |
| R9-N1 | 固定流量端口热功率与质量加权混合的前向关系 | `derived_fixed_positive_flow` | [`build_r9_reduced_model`](@ref) |
| R9-N2 | 相对温度与浮点权重和的平移修正 | `numerical_coordinate_transformation` | [`build_r9_reduced_model`](@ref) |
| R9-N3 | 无泵目标树水压辅助变量的存在性与构造 | `derived_for_declared_tree_model` | [`build_r9_reduced_model`](@ref) |
| R9-N4 | 源、荷与管道净热差的整日恒等式；沿用R9-A1 | `independent_energy_accounting` | [`r9_daily_heat_balance`](@ref) |
| R9-N5 | 冻结二进制系数的精确线性不相容证书 | `exact_binary_certificate_not_physical_infeasibility` | [`build_r9_pv_model`](@ref) |
| R9-N6 | 参考锚定、完整零空间与有界基底转换；显式项目数值解释 | `project_terminal_interpretation` | [`validate_r9_reduced_solution`](@ref) |
| R9-V1 | 当本步与前步质量覆盖均大于管存量时，解析消去alpha、beta；完整盒先行核验 | `derived_from_checked_WMM` | [`r9_transport_coefficients`](@ref) |
| R9-V2 | 保留本步与前步入口温度的连续流量热输运；不取整时延 | `derived_from_checked_WMM` | [`build_r9_flow_model`](@ref) |
| R9-V3 | 损耗衰减对本步和前步流量的依赖及解析导数 | `derived_from_checked_WMM` | [`r9_transport_coefficients`](@ref) |
| R9-V4 | 同时恢复入口温度与管流记忆；只认证采用WMM离散状态 | `project_periodic_boundary` | [`r9_flow_terminal_rows`](@ref) |
| R9-V5 | 管道净热量=输运损耗+入口温度记忆变化；不把离散代理当连续管内库存 | `derived_single_step_WMM_identity` | [`r9_heat_memory_balance`](@ref) |

## 符号

| 稳定ID | 原形 | 含义 | 单位 | Julia/配置映射 |
|---|---|---|---|---|
| `r9.power_factor` | ``\cos\varphi`` | 功率因数，项目替代值0.9 | 1 | `electric.power_factor` |
| `r9.pipe_conductance` | ``\epsilon_p`` | 单位管长传热系数，仅采用圆筒绝热层导热 | W/(m K) | `heat.pipes[p].epsilon_W_mK` |
| `r9.pipe_friction` | ``\mu_p`` | 压降二次系数；2000包含动压的2和Pa转kPa的1000 | kPa s^2/kg^2 | `heat.pipes[p].mu_kPa_s2_kg2` |
| `r9.memory_length` | ``L_p^h`` | 保守离散热记忆长度，与管道长度L分开 | time steps | `build_r9_pv_model: L` |
| `r9.theta` | ``\theta=T-T_c`` | 相对温度，源坐标按热源节点再按时段排列 | K | `temperature_centre_K; tau_S_port` |
| `r9.terminal_matrix` | ``A`` | 源温到终端记忆的仿射系数矩阵 | 1 | `terminal_certificate.terminal_matrix` |
| `r9.terminal_basis` | ``U`` | 完整精确零空间的Float64正交表示 | 1 | `terminal_certificate.basis` |
| `r9.terminal_coordinates` | ``y`` | 源温偏移的零空间坐标，与证书乘子y按作用域区分 | K | `r9_terminal_coordinates` |
| `r9.daily_energy` | ``\Delta E`` | 整日供需及管道净热差核算残差 | MWh | `daily_heat.residual_MWh` |
| `r9.pipe_mass` | ``M_p=\rho A_pL_p`` | 管内水质量 | kg | `mass_kg` |
| `r9.mass_per_step` | ``q_p=M_p/\Delta t_s`` | 管内质量与时间步的比值，须小于本步与前步流量 | kg/s | `q` |
| `r9.loss_constant` | ``C_p=\epsilon_pL_p/(2c_p)`` | 单步WMM损耗指数的质量流量系数 | kg/s | `C` |
| `r9.inverse_relative` | ``u_{p,t}=m_p^{ref}/m_{p,t}`` | 无量纲相对倒数流量，仅作为精确等式辅助量 | 1 | `r9_inverse_relative` |
| `r9.attenuation` | ``a_{p,t}`` | 相对于环境温差的衰减系数 | 1 | `attenuation` |
| `r9.net_heat` | ``Q_p^{\mathrm{net}}`` | 单方向管道全时域入口减出口净热量 | MWh | `net_MWh` |
| `r9.attenuation_heat` | ``Q_p^{\mathrm{loss}}`` | 独立回放中间温度减实际出口温度的损耗项；须另外检查输运方程 | MWh | `attenuation_MWh` |
| `r9.memory_energy` | ``\Delta E_p^{\mathrm{mem}}`` | 入口温度末初差对应的单步WMM记忆能量变化，不是连续温度场库存 | MWh | `memory_change_MWh` |

测试：`test/r9_pv.jl` / **R9-P1:P6 44/38 periodic input and fixed-mode model**。冻结重读及求解验证另见`scripts/test_r9_pv_evidence.jl`。

数值推导见[前向与终端解释](ch07-numerics.md)。R9-N1–N6对应`test/r9_reduced.jl`、`scripts/check_r9_affine_certificate.jl`及`scripts/check_r9_numerics_results.jl`。

连续流量推导见[输运与周期记忆](ch07-flow.md)。R9-V1–V4对应`test/r9_flow.jl`，R9-V5对应`test/r9_heat_memory.jl`；[直接参考](ch07-flow-results.md)有三项合格候选，CF-VT字面版本仍失败，PG尚未迁移。

## 连续流量与记忆符号

| 稳定ID | 原形 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| `r9.pipe_mass` | ``M_p=\rho A_pL_p`` | 管内水质量 | kg | `mass_kg` |
| `r9.mass_per_step` | ``q_p=M_p/\Delta t_s`` | 管内质量与时间步的比值，须小于本步与前步流量 | kg/s | `q` |
| `r9.loss_constant` | ``C_p=\epsilon_pL_p/(2c_p)`` | 单步WMM损耗指数的质量流量系数 | kg/s | `C` |
| `r9.inverse_relative` | ``u_{p,t}=m_p^{ref}/m_{p,t}`` | 无量纲相对倒数流量，仅作为精确等式辅助量 | 1 | `r9_inverse_relative` |
| `r9.attenuation` | ``a_{p,t}`` | 相对于环境温差的衰减系数 | 1 | `attenuation` |
| `r9.net_heat` | ``Q_p^{\mathrm{net}}`` | 单方向管道全时域入口减出口净热量 | MWh | `net_MWh` |
| `r9.attenuation_heat` | ``Q_p^{\mathrm{loss}}`` | 独立回放中间温度减实际出口温度的损耗项；须另外检查输运方程 | MWh | `attenuation_MWh` |
| `r9.memory_energy` | ``\Delta E_p^{\mathrm{mem}}`` | 入口温度末初差对应的单步WMM记忆能量变化，不是连续温度场库存 | MWh | `memory_change_MWh` |
