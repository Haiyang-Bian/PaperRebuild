# R6六方法推导与符号

由r6-methods.toml生成；R6-M全部为项目推导编号，不替换论文式号。

## R6-M1

~~~math
P_{d,t}^{\rm PV,avail}=\bar P^{\rm PV}p_{d,t},\quad \alpha_{d,t}^{\rm up}=\max(a_{d,t},0),\quad \alpha_{d,t}^{\rm down}=\max(-a_{d,t},0)
\tag{R6-M1}
~~~

比例乘MW额定容量，正上调意味着减少购电，两个调用比例每时段互斥；设备/初值/历史/终端不随轨迹改变。D用全部训练PV均值及零调用。

API：[`r6_dispatch_day`](@ref)；测试：`R6-PHYSICAL`。

## R6-M2

~~~math
\min_{b,x,y}\ C_{\rm market}(b,x)+\sup_{q\in\mathcal Q}\sum_s q_s C_s(y_s),\qquad \sup_{q\in\mathcal Q}\sum_s q_s z_s\le\epsilon
\tag{R6-M2}
~~~

D/SP/CCP固定经验概率；D使用唯一名义日。RO取全部有限支持概率，DRO/DRJCC取运输球。D/SP/RO/DRO固定全部z=0，CCP/DRJCC采用整日机会约束。所有方法使用同一连续报价和乐观市场KKT。费用与风险有两套独立最坏分布；未更换为外生固定价格。

API：[`R6MethodSpec`](@ref)；测试：`R6-METHOD`。

## R6-M3

~~~math
\rho_{\rm RO}=\max_{i,j}D_{ij},\qquad \Pi_{ij}=q_i p_j\ \Longrightarrow\ \sum_{ij}D_{ij}\Pi_{ij}\le\rho_{\rm RO},\quad \sup_{q\in\Delta_N}\sum_iq_iC_i=\max_i C_i
\tag{R6-M3}
~~~

任意有限支持概率q均有可行运输Pi，故该半径覆盖完整有限单纯形。反之运输边际仍是该单纯形，得到等价最坏情景费用。rho=0且非对角距离严格正时唯一边际为p，恢复经验期望；R6拒绝重复支持，避免静默合并或误称唯一经验分布。保证不延伸到支持外轨迹。

API：[`r6_training_case`](@ref)；测试：`R6-ROBUST`。

## 符号

| ID | 符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| r6-rating | ``\bar P^{\rm PV}`` | 冻结的光伏额定功率 | MW | `devices.p_max_MW` |
| r6-first-stage | ``b,x=(P^{\rm DA},R^{\rm up},R^{\rm down})`` | 连续价格报价与全情景共用的日前成交 | USD/MWh; MW | `market.bids; risk.base.first_stage` |
| r6-ambiguity | ``\mathcal Q,\rho,D,\Pi`` | 概率集合、半径、冻结距离、运输概率质量 | 1 | `ambiguity; radius; distance; transport` |
| r6-label | ``z_s`` | 情景整日舒适约束的放松开关；实际越界另由数值回放判定 | 1 | `risk.z[s]` |

## 原文与采用边界

### R6-MA01

PDF100–101，第5.6.3节；状态：`project_adopted_six_method_definition`。

原文记录：D忽略调用/采用平均情景；SP已知分布；RO最坏情况；DRO Wasserstein模糊集；CCP在SP上增加供热质量机会约束；DRJCC为提出模型。

项目处理：同物理/市场结构，仅改变情景费用规则与舒适风险。SP使用训练代表经验分布而非已知真实分布；RO/DRO保证限于有限支持。D明确为均值PV/零调用，仍计该名义日内部调度费用。

### R6-MA02

项目configs/r6/physical-rule.toml与daily-small.toml；状态：`synthetic_daily_physical_template`。

原文记录：本小系统不是作者原始24小时算例。

项目处理：继承四小时父模型的所有设备/网络/历史/物理域，另显式声明24小时负荷、气温和费用。楼温terminal=initial，管温terminal=free；所有方法一致，不把管温免费边界称周期能量恢复。

### R6-MA03

项目configs/r6/pilot-rule.toml；状态：`development_cost_measurement_only`。

原文记录：正式输入有100代表；开发先取冻结顺序的前三个，权重按所选簇质量条件归一。

项目处理：六方法每项120秒，rho=0.01为预声明开发值，不是验证选出的半径；D始终取全部训练PV均值。另只构建100场景SP记录规模，未优化测试集。前三代表可能没有可释放的5%概率质量，不能以此试运行评价机会约束收益。
