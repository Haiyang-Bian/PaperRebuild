# R6正式选择与压力规则

由r6-study.toml生成；R6-F全部为项目实验约定，不替换作者参数。

## R6-F1

~~~math
U_c=\operatorname{CPUpper}_{0.95}(n_{c,\rm violation}+n_{c,\rm unknown},500),\qquad \bar C_c=\frac{1}{500}\sum_{d=1}^{500}C_{cd}\quad\text{only if all costs are complete}
\tag{R6-F1}
~~~

验证候选在相同500个完整日上评价。未知日不删分母，上界全部计为违约；费用有缺失时总体均费为未定义，只能报告已完成子集的条件统计。一个日是一个联合室温事件。沿用R6-S/A5，不降低风险或数值阈值。

API：[`r6_summarize_days`](@ref)；测试：`R6-F1`。

## R6-F2

~~~math
\mathcal E_m=\{c\in\mathcal C_m:U_c\le0.05,\ n_{c,\rm missing}=0\},\qquad c_m^*\in\operatorname*{argmin}_{c\in\mathcal E_m}\bar C_c
\tag{R6-F2}
~~~

每种方法只用验证集选参数。均费在最低值加1e-8合成USD内，取较小半径，再取冻结顺序较早者。合格集为空时按风险上界、缺失费用数、完整均费（不完整视为正无穷）、半径和顺序回退，validated=false。回退使失败可完整评价，不宣称验证通过；选择后的验证区间不作最终风险保证。

API：[`select_r6_methods`](@ref)；测试：`R6-F2`。

## R6-F3

~~~math
\mathcal X_{\rm stress}=\{(0,+\mathbf1),(0,-\mathbf1),(p^{\rm clear},+\mathbf1),(p^{\rm clear},-\mathbf1)\}
\tag{R6-F3}
~~~

四个预声明确定性压力日：无PV或共同晴空PV，全天持续上调或下调。沿用24小时物理边界、冻结成交与主操作策略。它们不是独立同分布抽样，不计算二项概率置信界，不进入测试总体费用排名。源码和输入在首次求解前冻结；既有失败或超时只能重读，不能被重跑覆盖。

API：[`R6StudySpec`](@ref)；测试：`R6-F3`。

## 符号

| ID | 符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| r6-f-candidate | ``c\in\mathcal C_m`` | 方法m的预声明候选；D/SP/RO/CCP各一项，DRO/DRJCC各五项，共14项 | 1 | `r6_study_candidates(spec)` |
| r6-f-radius | ``\rho\in\{0,0.0005,0.001,0.005,0.01\}`` | 已有归一化轨迹距离下的运输球半径，零半径作为名义分布退化对照 | 1 | `R6StudySpec.data.radii` |
| r6-f-cost | ``\bar C_c,U_c`` | 完整验证日的平均IES净费用、将未知计为违约的单侧95%风险上界 | synthetic USD/day; 1 | `mean_net_cost_USD; risk.upper` |
| r6-f-stress | ``p^{\rm clear},\mathbf1`` | 共同协议的晴空可用比例和逐小时满调用比例；正号为上调 | 1 | `r6_study_stress_set` |

## 原文与采用边界

### R6-FA01

第5.6.3节已核查记录sample-out.toml及r6-evaluation.toml；状态：`project_protocol_not_author_parameters`。

原文记录：原论文样本外比较及其未公开细节沿用已有原页记录；本节点不声称作者采用本项目的选参网格、500验证日或回退准则。

项目处理：在任何正式验证/测试优化之前固定网格与规则。小正半径覆盖较弱分布扰动，零半径检查名义退化，RO另给有限支持最坏情况。该网格不是已证实最优范围；不依据后续测试扩充网格挑选收益。

### R6-FA02

训练候选、费用完成及主策略资格；状态：`retain_verified_incumbent_without_optimality_upgrade`。

原文记录：600秒内可能只得到训练可行候选；求解器停止状态与独立模型、风险、成本和市场检查是不同证据。

项目处理：仅四项独立检查通过的训练候选进入新日评价。通过但限时的候选保留并标最优性未完成；无合格策略则全部日记未知。主策略失败不换成独立舒适诊断。

### R6-FA03

统计隔离与正式结论；状态：`validation_selection_then_independent_test`。

原文记录：多个验证候选经过选择后的区间不能直接作为最终选择策略的无条件保证；有限支持训练保证也不自动传递到最近代表外推。

项目处理：14候选全部验证记录逐日重验后锁定六策略，才允许1000测试日与确定性压力评价。主要概率结论预声明为DRJCC联合舒适，其余为比较；新日保留未来轨迹已知、乐观市场与简化网络边界。
