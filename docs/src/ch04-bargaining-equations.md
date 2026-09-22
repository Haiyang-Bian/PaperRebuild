# 第4章议价公式与符号

<!-- GENERATED: scripts/r4_bargaining_docs.jl -->

本页仅登记已用于本批实现的8条原式；没有宣称(4-60)至(4-102)全部实现。

## [（4-71）固定物理效用时的加权Nash乘积](@id ch04-071)

```math
\max \prod_i(u_i+p_i-d_i)^{\alpha_i}
\tag{4-71}
```

PDF 70；状态：adopted_positive_weights_and_surplus。

API：[r4_nash_allocation](@ref PaperRebuild.r4_nash_allocation)；测试：`R4 Nash allocation and participation`。

## [（4-72）相对指定分歧点的个体理性](@id ch04-072)

```math
u_i+p_i\ge d_i
\tag{4-72}
```

PDF 70；状态：implemented。

API：[validate_r4_allocation](@ref PaperRebuild.validate_r4_allocation)；测试：`R4 Nash allocation and participation`。

## [（4-73）内部转移预算平衡](@id ch04-073)

```math
\sum_i p_i=0
\tag{4-73}
```

PDF 70；状态：implemented。

API：[validate_r4_allocation](@ref PaperRebuild.validate_r4_allocation)；测试：`R4 Nash allocation and participation`。

## [（4-78）正增益下的对数等价目标](@id ch04-078)

```math
\max \sum_i\alpha_i\log(u_i+p_i-d_i)
\tag{4-78}
```

PDF 71；状态：implemented_positive_surplus_only。

API：[r4_nash_allocation](@ref PaperRebuild.r4_nash_allocation)；测试：`R4 Nash allocation and participation`。

## [（4-80）内点分配的一阶条件](@id ch04-080)

```math
p_i^*=d_i-u_i^*-\alpha_i/\lambda
\tag{4-80}
```

PDF 71；状态：independently_checked。

API：[validate_r4_allocation](@ref PaperRebuild.validate_r4_allocation)；测试：`R4 Nash allocation and participation`。

## [（4-82）无限额预算平衡转移的解析解](@id ch04-082)

```math
p_i=d_i-u_i^*+\frac{\alpha_i}{\sum_j\alpha_j}\left(\sum_j u_j^*-\sum_jd_j\right)
\tag{4-82}
```

PDF 71；状态：adopted_fixed_dispatch。

API：[r4_nash_allocation](@ref PaperRebuild.r4_nash_allocation)；测试：`R4 Nash allocation and participation`。

## [（4-87）包含网络运营商的个体理性及预算平衡](@id ch04-087)

```math
\mathcal W_i\ge\mathcal W_i^D,\qquad \sum_{i\in\mathcal A}\phi_i=0
\tag{4-87}
```

PDF 72；状态：adopted_scope。

API：[r4_allocate_coordination](@ref PaperRebuild.r4_allocate_coordination)；测试：`R4 Nash allocation and participation`。

## [（4-94）分配前效用加总支付；不能重复叠加旧零售收支](@id ch04-094)

```math
\phi_i=\frac{\Lambda_i}{\sum_{j\in\mathcal A}\Lambda_j}\left(\sum_{j\in\mathcal A}\widehat{\mathcal W}^{\prime}_j-\sum_{j\in\mathcal A}\widehat{\mathcal W}_j^D\right)+\widehat{\mathcal W}_i^D-\widehat{\mathcal W}^{\prime}_i
\tag{4-94}
```

PDF 72；状态：adopted_fixed_dispatch。

API：[r4_allocate_coordination](@ref PaperRebuild.r4_allocate_coordination)；测试：`R4 Nash allocation and participation`。

## 符号权威表

| ID / Julia | 原符号 | 含义 | 单位 | 域 / 维度 | 来源 |
|---|---|---|---|---|---|
| r4-nash-prepayment / `prepayment_utility[i]` | ``u_i`` | 不含内部支付的固定物理计划效用，采用负资源及不满意度成本 | USD_synthetic | finite real / actor | PDF70/72; (4-71), (4-94); project ledger mapping |
| r4-nash-disagreement / `disagreement_utility[i]` | ``d_i,\widehat{\mathcal W}_i^D`` | 指定独立运营计划经过结算后的分歧效用 | USD_synthetic | finite real / actor | PDF70/72; (4-71), (4-94) |
| r4-nash-transfer / `total_transfer[i]` | ``p_i,\phi_i`` | 总内部净支付，正为收款，替代原结算而非追加 | USD_synthetic | real; sum zero / actor | PDF71/72; (4-82), (4-94) |
| r4-nash-weight / `weights[i]` | ``\alpha_i,\Lambda_i`` | 正议价权重；容量与峰荷映射为独立声明的项目规则 | relative weight | strictly positive / actor | PDF70/72; capacity_load_v1 excludes battery MWh |
| r4-nash-surplus / `surplus` | ``S`` | 合作计划相对指定分歧点的总剩余 | USD_synthetic | real; may be negative / scalar | project R4-N1 |
| r4-nash-increment / `incremental_compensation[i]` | ``\Delta\phi_i`` | 新总支付减旧内部净收支，仅用于与原教学结算比较 | USD_synthetic | real; sum zero / actor | project R4-N2 |

## 疑点与采用边界

### R4-N01 解析分配适用条件

正权重、正总剩余、无限额预算平衡转移；零剩余退化，负剩余拒绝个体理性成功。固定调度分配不认证上游全局最优。

### R4-N02 市场力到容量键的映射

原文PDF72未逐设备定义容量汇总；项目只计CHP/PV电功率、HP/EB输入功率、电池功率及参考电热峰荷。运营商权重等于聚合商之和。等权是独立对照。

### R4-N03 TSPA分歧点与稳定性边界

PDF73的AGNB忽略网络，再以DHSO0-r松弛网络并加罚。PDF74从SW_coordinated>=SW_P2P推出(4-102)，但松弛分歧点不自动属于协调物理可行域；须核对罚项、可行域和总增益。本批未实现TSPA，不宣称所有子联盟稳定。

### R4-N04 ATC/ADMM待核对

PDF68-69的beta与beta平方、ADMM范数是否平方、辅助贸易更新是否缺rho以及对偶更新须逐项推导。本批不实现分布协调。
