# 固定流量子问题：台账索引

由 `docs/reading/ch07/fixed.toml` 生成。

| 编号 | 含义 | 状态 | Julia API |
|---|---|---|---|
| R9-F1 | 显式给定流量后的前向热关系及终端源温系统 | derived_positive_fixed_flow | [`build_r9_reduced_model`](@ref) |
| R9-F2 | 输入盒中心正则常数点与完整核空间；16.44 K反例限制其用途 | diagnostic_not_control_preserving | [`r9_terminal_coordinates`](@ref) |
| R9-F3 | 保留全部源温变量的显式终端舍入区间，独立于原A1 | declared_numerical_interpretation_not_exact_equivalence | [`validate_r9_fixed_solution`](@ref) |

| ID | 符号 | 含义 | 单位 | Julia |
|---|---|---|---|---|
| r9.fixed_flow | ``\bar m`` | 固定子问题的管道×时段流量参数；不作为PG初值 | kg/s | `flow_schedule` |
| r9.terminal_band | ``\epsilon_T=2^{-34}`` | 每条终端仿射等式的预先固定半宽；不改变原A1 | K | `terminal_certificate.radius_K` |
| r9.terminal_regularization | ``\lambda=(10^{-10}/(4\max(1,R)))^2`` | 仅用于诊断常数点的输入盒正则权重 | 1 | `terminal_certificate.regularization_weight` |
