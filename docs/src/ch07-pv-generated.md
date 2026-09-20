# R9固定模式采用式与符号索引

<!-- generated from docs/reading/ch07/pv-adoption.toml; edit that ledger -->

推导和边界见[固定模式基准](ch07-pv.md)，结果见[数值边界报告](ch07-pv-results.md)。

| ID | 含义 | 解释类别 | Julia API |
|---|---|---|---|
| R9-P1 | 视在功率与有功/无功；合成节点与时间分配 | `project_input_conversion` | [`r9_pv_case`](@ref) |
| R9-P2 | 线路电阻按电压基准折算；固定额定变比的理想变压器 | `project_equivalent_network` | [`audit_r9_pv_input`](@ref) |
| R9-P3 | 由参考质量流量与速度确定截面积；圆筒导热和固定Darcy系数 | `project_pipe_design` | [`r9_pv_case`](@ref) |
| R9-P4 | 固定流量源/荷端口供回温差与热功率 | `source_heat_relation_with_declared_units` | [`audit_r9_pv_input`](@ref) |
| R9-P5 | 给定CF-CT日曲线按树计算周期WMM参考历史，不求解优化 | `project_periodic_reference_boundary` | [`audit_r9_pv_input`](@ref) |
| R9-P6 | 最终入口序列等于冻结初始历史；以最小流量所需记忆长度约束 | `project_terminal_memory` | [`build_r9_pv_model`](@ref) |

## 符号

| 稳定ID | 原形 | 含义 | 单位 | Julia/配置映射 |
|---|---|---|---|---|
| `r9.power_factor` | ``\cos\varphi`` | 功率因数，项目替代值0.9 | 1 | `electric.power_factor` |
| `r9.pipe_conductance` | ``\epsilon_p`` | 单位管长传热系数，仅采用圆筒绝热层导热 | W/(m K) | `heat.pipes[p].epsilon_W_mK` |
| `r9.pipe_friction` | ``\mu_p`` | 压降二次系数；2000包含动压的2和Pa转kPa的1000 | kPa s^2/kg^2 | `heat.pipes[p].mu_kPa_s2_kg2` |
| `r9.memory_length` | ``L_p^h`` | 保守离散热记忆长度，与管道长度L分开 | time steps | `build_r9_pv_model: L` |

测试：`test/r9_pv.jl` / **R9-P1:P6 44/38 periodic input and fixed-mode model**。冻结重读及求解验证另见`scripts/test_r9_pv_evidence.jl`。
