# R6新日策略与诊断公式

由r6-evaluation.toml生成；R6-E全部为项目推导，主策略与诊断分开。

## R6-E1

~~~math
e(y)=\max_{b,t}\{0,\underline\tau_b-\tau_{bt}(y),\tau_{bt}(y)-\overline\tau_b\},\qquad \operatorname{lexmin}_{y\in\mathcal Y_{\rm phys}(x,\xi)}\bigl(e(y),C_{\rm RT}(y)\bigr)
\tag{R6-E1}
~~~

独立舒适能力诊断：先试硬舒适费用问题，仅其明确不可行时最小化整日最大越界，再以最小越界加1e-8 K为上限优化费用。最小越界的原对偶绝对差须不超过1e-8 K。该诊断改变操作优先级，不替代机会约束策略；硬舒适不可行而峰值近零时保存状态冲突。

API：[`evaluate_r6_day`](@ref)；测试：`R6-E1`。

## R6-E2

~~~math
C_d=C_{\rm DA}(x,\lambda)+C_{\rm device}(y_d)+C_{\rm settlement}(y_d,\xi_d)+C_{\rm penalty}(y_d,\xi_d),\qquad (x,\lambda)=(x^{\rm train},\lambda^{\rm selected})
\tag{R6-E2}
~~~

冻结核验训练结果的日前成交和所选市场价格。新日不重新优化报价或重出清，日前净支付只计一次；设备/容量/热历史/初末边界共同保持。净支付可为负，不称系统资源成本。训练版本及费用完成标志单列，来源哈希不能替代共同模型字段检查。

API：[`r6_policy_from_training`](@ref)；测试：`R6-E2`。

## R6-E3

~~~math
V_d=\mathbf 1\{e(y_d)>10^{-4}\ {\rm K}\},\qquad U_{0.95}=\operatorname{CPUpper}(n_{\rm violation}+n_{\rm unknown},N)
\tag{R6-E3}
~~~

一个完整日是一个联合事件。实际温度越界与训练开关分开；未完成操作或缺少可信最优性证据标unknown。未知保留在分母且保守上界计为违约，采用既有A5单侧界。运行原值、原始乘子、输入、源码和哈希必须能独立重读；统计界本身不认证遗漏物理机制。

API：[`validate_r6_policy_day`](@ref)；测试：`R6-E3`。

## R6-E4

~~~math
d(\xi,\xi_s)=\sqrt{\frac{1}{2T}\sum_{t=1}^{T}\left[(p_t-p_{st})^2+\left(\frac{a_t-a_{st}}{2}\right)^2\right]},\quad s^*(\xi)=\min\operatorname*{argmin}_s d(\xi,\xi_s),\quad y(\xi)\in\operatorname*{argmin}_{y\in\mathcal Y_{z_{s^*(\xi)}}(x,\xi)}C_{\rm RT}(y)
\tag{R6-E4}
~~~

项目外推r6_support_nearest_v1：整日PV比例与有符号调用使用训练距离，等距按冻结支持顺序最早项。继承该训练代表的z：0为原舒适界，1为共同物理温度界；费用问题失败时不暗中换z或调用诊断。仍用完整未来轨迹，不是在线控制。有限支持风险保证不自动传递到新轨迹；多个最优调度的具体执行由预声明求解器确定并保存，不宣称物理策略唯一。

API：[`r6_support_label`](@ref)；测试：`R6-E4`。

## 符号

| ID | 符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| r6-e-trajectory | ``\xi=(p_t,a_t)_{t=1}^T`` | 完整日PV可用比例和有符号备用调用，正调用为上调 | 1 | `trajectory[1:2,t]` |
| r6-e-award | ``x,\lambda`` | 冻结的日前购电/备用成交和所选市场结算价格 | MW; USD/MWh | `R6Policy.data.award` |
| r6-e-label | ``z_{s^*(\xi)}`` | 最近训练代表的舒适放松开关，不是实际越界事件 | 1 | `r6_support_label(...)[label]` |
| r6-e-excess | ``e(y),V_d`` | 整日最大温度越界和按A1数值门槛分类的联合事件 | K; 1 | `peak_excess_K; comfort_outcome` |

## 原文与采用边界

### R6-EA01

PDF101/印刷84，第5.6.3节；状态：`author_sample_out_rule_not_fully_specified`。

原文记录：原文说明用1000个蒙特卡洛场景分析样本外表现，比较六方案的费用与备用；此页未明确如何将训练支持的舒适开关映射到新轨迹。

项目处理：保留原文结论与缺失细节，预先给出最近代表策略和独立诊断两个版本。它们是项目补充，不能说已恢复作者原始样本外程序；该不确定性进入最终比较边界。

### R6-EA02

训练情景开关与新日操作的接口；状态：`project_extension_not_guarantee`。

原文记录：有限支持优化只给出训练代表上的补救和z；在代表之间不存在自动定义的控制律。

项目处理：只按冻结距离外推开关，连续调度在真实新轨迹下重解。训练、验证和测试轨迹仍隔离，未用测试结果拟合或选优。R6-E4仅定义可重复操作，风险由独立测试检验。

### R6-EA03

样本外统计与舒适能力诊断；状态：`separate_primary_and_diagnostic`。

原文记录：统一舒适优先会覆盖机会模型允许少量越界的经济选择，因而改变被评价策略。

项目处理：正式主结果使用固定训练开关的外推，诊断仅回答硬舒适能否实现、若不能最小越界多大。不把诊断成功替代主策略失败，不把求解器不可行直接当已观察到的室温事件。

### R6-EA04

旧开发证据和后续源码版本；状态：`frozen_source_replay`。

原文记录：r6-training-pilot-v1冻结完整模块入口哈希，新增API会使当前源码不同。

项目处理：r6-pilot-replay-v2保存12feb05源码快照并校验全部输入，在隔离目录只读重验旧八项检查。新日记录也保存最小完整依赖及code/replay.jl，不移除来源检查，不重算旧最优调度。
