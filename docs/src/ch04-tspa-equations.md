# 第4章两阶段公式与符号

<!-- GENERATED: scripts/r4_tspa_docs.jl -->

登记（4-95）—（4-102）的原式结构和采用范围；项目松弛定义见[推导](ch04-tspa.md)。

## [（4-95）忽略网络的聚合商Nash交易](@id ch04-095)

```math
\max \prod_{i\in\mathcal M}(U_i^{\mathrm{P2P}}-\widehat U_i^0)^{\Lambda_i}
\tag{4-95}
```

PDF 73；状态：adopted_aggregate_optimization_then_allocation。

API：[solve_r4_tspa](@ref PaperRebuild.solve_r4_tspa)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-96）第一阶段相对原AG0的个体理性](@id ch04-096)

```math
U_i^{\mathrm{P2P}}\ge\widehat U_i^0,\quad i\in\mathcal M
\tag{4-96}
```

PDF 73；状态：checked_positive_zero_negative_surplus。

API：[validate_r4_tspa](@ref PaperRebuild.validate_r4_tspa)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-97）AGNB只包含局部设备和交易约束，原文未包含网络](@id ch04-097)

```math
\text{式}(4\!-\!7)\text{--}(4\!-\!13),\ (4\!-\!15)\text{--}(4\!-\!18)
\tag{4-97}
```

PDF 73；状态：adopted_existing_R4_devices_and_explicit_contracts。

API：[build_r4_model](@ref PaperRebuild.build_r4_model)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-98）第二阶段分歧点；原式时间求和及有向收费口径需说明](@id ch04-098)

```math
\widehat{\mathcal W}_i^D=\widehat U_i^{\mathrm{P2P}},\quad \widehat{\mathcal W}_0^D=-\widehat C^{\mathrm{DHSO}}+\sum_{i\in\mathcal M}\widehat C_i^{\mathrm{Retail}}+\sum_{i\in\mathcal M}\sum_j\kappa_{ij}\widehat P_{ij,t}+\sum_{i\in\mathcal M}\sum_j\varphi_{ij}\widehat H_{ij,t}
\tag{4-98}
```

PDF 73；状态：two_penalty_interpretations_and_once_per_trade_fee。

API：[solve_r4_tspa](@ref PaperRebuild.solve_r4_tspa)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-99）单阶段按全体权重分配总增益](@id ch04-099)

```math
\delta_i^{\mathrm{SSPA}}=\frac{\Lambda_i}{\sum_{j\in\mathcal A}\Lambda_j}(\mathrm{SW}^{\mathrm{P2P\&NetCo}}-\mathrm{SW}^0)
\tag{4-99}
```

PDF 74；状态：explained_and_previous_batch_implemented。

API：[r4_nash_allocation](@ref PaperRebuild.r4_nash_allocation)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-100）聚合商两个阶段的增益相加](@id ch04-100)

```math
\delta_i^{\mathrm{TSPA}}=\frac{\Lambda_i}{\sum_{j\in\mathcal M}\Lambda_j}\left(\sum_{j\in\mathcal M}\widehat U_j^{\mathrm{P2P}}-\sum_{j\in\mathcal M}\widehat U_j^0\right)+\frac{\Lambda_i}{\sum_{j\in\mathcal A}\Lambda_j}(\mathrm{SW}^{\mathrm{P2P\&NetCo}}-\mathrm{SW}^{\mathrm{P2P}})
\tag{4-100}
```

PDF 74；状态：adopted_when_each_allocation_exists。

API：[validate_r4_tspa](@ref PaperRebuild.validate_r4_tspa)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-101）单阶段所得可能低于指定聚合商联盟的外部选择](@id ch04-101)

```math
\frac{\Lambda_i}{\sum_{j\in\mathcal A}\Lambda_j}(\mathrm{SW}^{\mathrm{P2P\&NetCo}}-\mathrm{SW}^0)<\frac{\Lambda_i}{\sum_{j\in\mathcal M}\Lambda_j}\left(\sum_{j\in\mathcal M}\widehat U_j^{\mathrm{P2P}}-\sum_{j\in\mathcal M}\widehat U_j^0\right)
\tag{4-101}
```

PDF 74；状态：explained_not_all_coalitions_certified。

API：[r4_nash_allocation](@ref PaperRebuild.r4_nash_allocation)；测试：`R4 TSPA network disagreement and penalty accounting`。

## [（4-102）依赖第二阶段总剩余非负的指定外部选择比较](@id ch04-102)

```math
\delta_i^{\mathrm{TSPA}}\ge\frac{\Lambda_i}{\sum_{j\in\mathcal M}\Lambda_j}\left(\sum_{j\in\mathcal M}\widehat U_j^{\mathrm{P2P}}-\sum_{j\in\mathcal M}\widehat U_j^0\right)
\tag{4-102}
```

PDF 74；状态：premise_audited_not_assumed。

API：[validate_r4_tspa](@ref PaperRebuild.validate_r4_tspa)；测试：`R4 TSPA network disagreement and penalty accounting`。

## 符号权威表

| ID / Julia | 符号 | 含义 | 单位 | 域 / 来源 |
|---|---|---|---|---|
| r4-tspa-ag-utility / `stage1.utility_after[i]` | ``U_i^{\mathrm{P2P}}`` | 第一阶段聚合商结算后效用 | USD_synthetic | finite real / PDF73 (4-95)/(4-98) |
| r4-tspa-slack / `slack_P_pos[i,t] and other carrier/side arrays` | ``s_b;\ s_b^+,s_b^-`` | 原文网络松弛；项目用有符号节点平衡的两个非负分量 | MW / Mvar / kg/s | nonnegative; node x time / PDF73 unnumbered; project R4-T2 |
| r4-tspa-penalty / `R4TSPASpec.penalty` | ``\delta_b;\ \delta`` | 原文逐约束罚系数；项目统一归一化系数 | USD_synthetic/h/normalized violation | positive finite scalar / PDF73 unnumbered; project R4-T2 |
| r4-tspa-scale / `r4_tspa_scales(case)` | ``\sigma_P,\sigma_Q,\sigma_H,\sigma_m`` | 按输入容量预先确定的归一化尺度，不改变A1 | MW / Mvar / kg/s | positive per carrier / project R4-T2 |
| r4-tspa-peer / `P_peer[t], H_peer[t]` | ``P_{AB,t},H_{AB,t}`` | A向B出售为正的合同；不指定物理线路 | MW | bounded real; time / adopted (4-17)/(4-18); project R4-T1 |

## 疑点及采用解释

### R4-T01 网络松弛位置

原文未列逐约束松弛。本批仅四类节点平衡双向松弛，其余全部硬约束。严格网络和弹性网络独立保存，不把弹性解称为物理成功。

### R4-T02 罚项与分歧效用

原式(4-98)未明确C_DHSO是否含罚项，两种解释并列，实际资源成本和人工罚金分别记录。固定同一AGNB计划对照100/10000罚系数。

### R4-T03 总福利比较及稳定性

只有相同物理可行域嵌入或独立数值证据才能支持SW协调>=SW_P2P。松弛分歧点不保证此关系；(4-102)不认证所有子联盟或博弈核非空。

### R4-T04 候选、交易、费用与支付

保留AG0嵌入和求解候选，按独立重算成本选择；负剩余不裁零。第二阶段总支付替代全部旧内部账单，不能再叠加第一阶段转移。服务费卖方每笔一次，双边能量乘Δt。
