# R9固定模式采用式与符号索引

<!-- generated from docs/reading/ch07/{pv-adoption,numerics}.toml; edit those ledgers -->

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

测试：`test/r9_pv.jl` / **R9-P1:P6 44/38 periodic input and fixed-mode model**。冻结重读及求解验证另见`scripts/test_r9_pv_evidence.jl`。

数值推导见[前向与终端解释](ch07-numerics.md)。R9-N1–N6对应`test/r9_reduced.jl`、`scripts/check_r9_affine_certificate.jl`及`scripts/check_r9_numerics_results.jl`。
