# 第4章分布协调公式与符号

<!-- GENERATED: scripts/r4_distributed_docs.jl -->

原式结构转录及改写边界见[推导](ch04-distributed.md)，未实现条目不得改记为已执行。

## [（4-60）网络运营商目标协调子问题](@id ch04-060)

```math
\min C^{\mathrm{DHSO}}+\sum_n\{(\alpha_n^{PN})^\mathsf T(\widehat P_n^{net}-P_n^{net*})+(\beta_n^{PN})^\mathsf T\|\widehat P_n^{net}-P_n^{net*}\|_2^2\}+\text{对应热项}
\tag{4-60}
```

PDF 68；状态：structure_adopted_sign_and_penalty_derived。

API：[build_r4_distributed_block](@ref PaperRebuild.build_r4_distributed_block)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-61）运营商原网络约束](@id ch04-061)

```math
\text{式}(4\!-\!25)\text{--}(4\!-\!57)
\tag{4-61}
```

PDF 68；状态：fixed_topology_socp_subset。

API：[build_r4_distributed_block](@ref PaperRebuild.build_r4_distributed_block)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-62）聚合商目标协调子问题](@id ch04-062)

```math
\min C_i^{AG}+(\alpha_n^{PN})^\mathsf T(P_n^{net}-\widehat P_n^{net*})+(\beta_n^{PN})^\mathsf T\|P_n^{net}-\widehat P_n^{net*}\|_2^2+\text{对应热项}
\tag{4-62}
```

PDF 68；状态：structure_adopted_opposite_multiplier_sign。

API：[build_r4_distributed_block](@ref PaperRebuild.build_r4_distributed_block)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-63）聚合商设备和交易可行域](@id ch04-063)

```math
\text{式}(4\!-\!7)\text{--}(4\!-\!13),\ (4\!-\!16)\text{--}(4\!-\!18)
\tag{4-63}
```

PDF 68；状态：adopted_fixed_battery_modes。

API：[build_r4_distributed_block](@ref PaperRebuild.build_r4_distributed_block)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-64）电力罚乘子更新；原页电式中β上标写为HN](@id ch04-064)

```math
\alpha_n^{PN,(k+1)}=\alpha_n^{PN,(k)}+2(\beta_n^{HN,(k)})^2(\widehat P_n^{net*,(k)}-\widehat P_n^{net,(k)})
\tag{4-64}
```

PDF 68；状态：original_ambiguity_preserved_consistent_residual_update_adopted。

API：[solve_r4_distributed](@ref PaperRebuild.solve_r4_distributed)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-65）热力罚乘子更新](@id ch04-065)

```math
\alpha_k^{HN,(k+1)}=\alpha_k^{HN,(k)}+2(\beta_k^{HN,(k)})^2(\widehat H_k^{net*,(k)}-\widehat H_k^{net,(k)})
\tag{4-65}
```

PDF 68；状态：original_index_collision_preserved_consistent_update_adopted。

API：[solve_r4_distributed](@ref PaperRebuild.solve_r4_distributed)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-66）电罚系数递增](@id ch04-066)

```math
\beta_n^{PN,(k+1)}=(1+\zeta)\beta_n^{PN,(k)},\quad \zeta\in[1,2]
\tag{4-66}
```

PDF 68；状态：explained_not_executed_fixed_rho_project_variant。

API：[R4DistributedSpec](@ref PaperRebuild.R4DistributedSpec)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-67）热罚系数递增](@id ch04-067)

```math
\beta_k^{HN,(k+1)}=(1+\zeta)\beta_k^{HN,(k)}
\tag{4-67}
```

PDF 68；状态：explained_not_executed_fixed_rho_project_variant。

API：[R4DistributedSpec](@ref PaperRebuild.R4DistributedSpec)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-68）聚合商双边交易ADMM；末项原页范数未平方](@id ch04-068)

```math
\mathcal L_i=C_i^{AG}+\text{ATC项}+\sum_{j\ne i}\{(\lambda_{ij}^{PN})^\mathsf T(\widehat P_{ij}-P_{ij})+(\lambda_{ij}^{HN})^\mathsf T(\widehat H_{ij}-H_{ij})+\frac{\rho}{2}(\|P_{ij}-\widehat P_{ij}\|+\|H_{ij}-\widehat H_{ij}\|)\}
\tag{4-68}
```

PDF 69；状态：squared_penalty_derived_from_reference_131。

API：[solve_r4_distributed](@ref PaperRebuild.solve_r4_distributed)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-69）反对称电合同辅助变量；原页乘子差未除ρ](@id ch04-069)

```math
\widehat P_{ij}^{(K+1)}=-\widehat P_{ji}^{(K+1)}=\frac{P_{ij}^{(K+1)}-P_{ji}^{(K+1)}}2+\frac{\lambda_{ji}^{PN,(K)}-\lambda_{ij}^{PN,(K)}}2
\tag{4-69}
```

PDF 69；状态：scaled_dual_projection_derived。

API：[solve_r4_distributed](@ref PaperRebuild.solve_r4_distributed)；测试：R4 distributed convex coordination and bilateral consensus。

## [（4-70）反对称热合同辅助变量](@id ch04-070)

```math
\widehat H_{ij}^{(K+1)}=-\widehat H_{ji}^{(K+1)}=\frac{H_{ij}^{(K+1)}-H_{ji}^{(K+1)}}2+\frac{\lambda_{ji}^{HN,(K)}-\lambda_{ij}^{HN,(K)}}2
\tag{4-70}
```

PDF 69；状态：scaled_dual_projection_derived。

API：[solve_r4_distributed](@ref PaperRebuild.solve_r4_distributed)；测试：R4 distributed convex coordination and bilateral consensus。

## 符号表

| ID / Julia | 符号 | 含义 | 单位 | 来源 |
|---|---|---|---|---|
| r4-d-message / `message` | ``b_i=(P_i^{net},Q_i^D,H_i^{src},H_i^D)`` | 聚合商边界消息；后两项相减为热净注入 | MW/Mvar | project R4-D1; extends thesis P/H exchange |
| r4-d-x / `x` | ``x_i=D^{-1}b_i`` | 聚合商无量纲边界 | 1 | project input-frozen scales |
| r4-d-z / `z` | ``z_i=D^{-1}\widehat b_i`` | 网络无量纲副本 | 1 | project R4-D2 |
| r4-d-u / `u` | ``u_i=\lambda_i/\rho`` | 无量纲目标下缩放乘子 | 1 | project R4-D3; not raw thesis lambda |
| r4-d-q / `peer` | ``q_{ij}`` | 对交易对手出售为正的合同；与支路潮流不同 | MW | adopted R4-P1 sign |
| r4-d-rho / `rho, peer_rho` | ``\rho,\rho_q`` | 外层和内层固定罚系数 | 1 | project numerical policy; no beta growth |

## 疑点与采用解释

### R4-D-C01 同一拉格朗日的方向和系数

统一r=x-z，AG线性项+λx、DSO线性项-λz，二次项ρ/2。原式β与β²及4-64的HN上标不直接执行。

### R4-D-C02 ADMM辅助量与乘子

平方罚项导出反对称投影；未缩放λ对应差项须除ρ，u=λ/ρ后无需再除。原文步骤2.a.b把辅助量更新称为乘子更新，另补真正的u递推。

### R4-D-C03 不足的边界通信

当前Q_D随可调P_D变化，热端口包络依赖H_src/H_D；增加这些边界量，不向DSO回传全部AG设备控制。程序保存全体结果用于离线独立审计，不宣称访问控制或密码学隐私。

### R4-D-C04 凸性和有限精度

固定离散模式及SOCP；实际MOI类型核查。固定ρ及有限内层容差是项目约定；不继承整数/非凸全局收敛，也不以A4代替物理A1。

### R4-D-C05 福利与合同的不同作用

SWM内部支付抵消，有限但足够宽零售通道使零P2P合同可嵌入所有物理计划；双边交易可能不唯一。AGNB另计零售与卖方一次费用，单独检验非零合同求解。
