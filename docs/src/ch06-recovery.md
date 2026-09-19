# R7：给定灾前状态的恢复基准

本节点在[实施前核查](ch06-audit.md)之后，新增`r7_recovery_checked_v1`。
给定灾前启停、储能和管温边界及一个线路故障，求使期望电热失供最小的恢复计划。
**这是恢复子问题的开发基准，尚无灾前最优计划、嵌套C&CG或论文规模结果。**
合成输入固定在`configs/r7/recovery-hand.toml`；公式及符号见[采用台账](ch06-recovery-equations.md)。

## 1. 一次故障怎样改变供能？

考虑电节点1的CHP、电节点2的电池与负荷，以及连接两节点的一条电支路。
热网仍连通，拥有一对供回水管。事件期间与外部主网断开。
即使没有内部断线，也不能继续无限购电；断线后CHP的电力不能越过故障支路，
电池和原有热状态成为局部资源。CHP继承灾前启停，但能够调整出力。

恢复网络在整个事件窗口和所有新能源场景共用；热流量按时段选择、跨场景共用。
设备出力、失供和能量状态可以随场景变化。故障集合包含“不超过K”的全部组合，
保留零内部断线。不把场景期望偷偷换成每个场景的最大损失。

## 2. 采用模型与原式之间的边界

| 内容 | 本接口采用与限制 |
|---|---|
| 电网 | 原第6章的线性、无损关系；电压是幅值，非R4平方量；PCC为零 |
| 支路方向 | 默认保留给定方向的非负P/Q；`signed`为显式项目扩展 |
| 拓扑 | 全节点森林，每个分量一个合格根；根资格是输入假设，不证明设备成网硬件能力 |
| 孤立负荷 | 若没有合格根则采用模型不可行；尚未增加去电节点选择 |
| 电池 | 原式(6-12)功率和式界，逐时段积分；初值继承，恢复末值自由 |
| 热网 | 一个连通网络的供回水双水箱；质量守恒、端口热功率包络与冻结参考点Taylor循环关系 |
| 温度与损耗 | 相对温度下限的显热，分别计算两侧体积；UA用W/K，损耗转为MW |
| 物理范围 | 不验证交流潮流、逐管输运、混合、水压、停流冷却；热网自身故障不支持 |

源端口允许零温差是这个手算输入的显式设定，不能当作作者参数。
它允许无CHP产热时维持循环，在集总模型中利用原有显热。
正常运行的最短启停约束、正常经济目标和初始历史生成未由本接口认证。
`preplan_optimality_verified=false`始终保留，不能因为填写`preplan_id`就称灾前优化完成。

## 3. 可以手算的恢复答案

一小时时段，电负荷0.6 MW、热负荷0.4 MW，电池初始0.2 MWh、放电上限0.2 MW，效率1。
供水和回水各10 m³，均高于各自温度下限10 K，比热4200 J/(kg K)、密度1000 kg/m³。
每侧相对显热为7/60 MWh，两侧共7/30 MWh。

无内部故障时，CHP与电池可供应全部负荷，最小失供为零。
唯一电支路故障时，节点1没有电负荷或电力出口，电平衡迫使CHP出力降到零。
采用模型的下界见[手算式R7-R5](ch06-recovery-equations.md#R7-R5)：电失供至少0.4 MWh，
热失供至少1/6 MWh，合计至少17/30 MWh。

同时可构造达到该界的候选：电池放电0.2 MW，循环热功率7/60 MW，
供热7/30 MW，两箱末值为各自能量下限，循环流量为25/27 kg/s。
该流量满足本案例的容量、参考流变化界及源/荷端口包络。
这是采用模型的可达性见证，尚不能当作逐管温度或混合可行的证明。

| 开发对照 | 最小期望失供MWh | 可声称的证据 |
|---|---:|---|
| 无内部故障，HiGHS整数模型 | 0 | 采用模型与有效界通过 |
| 唯一线路故障，HiGHS整数模型 | 0.566666667 | 等于17/30的解析答案 |
| 固定故障、枚举全部允许森林，HiGHS LP | 0.566666667 | 与整数模型同目标、完整枚举界 |
| 同一固定拓扑，Clarabel LP | 约0.566666667 | 数值一致；当前接口未提供ObjectiveBound，未认证有效间隙 |

手算门槛0.55 MWh低于故障最优损失。有效最小化下界已超过门槛，故可认证该给定灾前状态
在采用模型中的反例；不是仅凭一个较差的恢复可行值就判定失败。
另一个测试把门槛设为0.6 MWh并完整覆盖两个故障组合，才能给出采用模型内的安全判定。

## 4. 验证器实际检查什么？

[`validate_r7_recovery`](@ref)从保存数值重算设备、森林、节点平衡、能量积分和双水箱约束，
不复用JuMP表达式。沿用A1，采用模型通过、循环原乘积通过、电池互斥以及最优界分别记录。

75项专项检查包括：解析/LP/整数对照、半小时与两小时积分、两场景加权失供与共享维度、
正向/有符号支路差异、开路电压解耦、硬负荷与爬坡不可行、缺求解器/零预算、原值篡改和冻结源码重读。
完整R1–R6与最初73项恢复检查已回归通过；补充来源/预算两项后75项专项重验通过。
严格文档构建实际通过，日志及范围另见任务记录。

两个负结果是有用的边界：

- 保持充放净值相同，可构造同时充放仍满足原(6-12)的候选。验证器保留其采用模型通过和互斥失败。
- 改变初始温差后，Taylor交换模型可以通过，而原(6-88)乘积残差失败。
  即使循环乘积通过，也只验证了这一关系，未认证整个详细热网。

## 5. Julia调用、保存与重读

~~~julia
using PaperRebuild, JuMP, HiGHS
case = load_r7_recovery_case("configs/r7/recovery-hand.toml")
opt = optimizer_with_attributes(HiGHS.Optimizer, "threads" => 1)
run = solve_r7_recovery(case, [1]; optimizer=opt, budget_sec=60)
run["validation"]["loss_MWh"]
~~~

常用可重复入口：

~~~text
julia +1.12.6 --startup-file=no --project=. scripts/check_r7_recovery.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_recovery.jl
julia +1.12.6 --startup-file=no --project=. scripts/r7_recovery.jl solve configs/r7/recovery-hand.toml 1 results/runs/<new-name>
julia +1.12.6 --startup-file=no --project=. scripts/r7_recovery.jl check results/runs/<new-name>
~~~

保存接口拒绝覆盖、源码在求解后改变及与原值矛盾的摘要。源码升级后使用存档`code/replay.jl`
以原版本重读；不重新优化。运行保存求解器请求参数、请求预算、环境锁与源文件；
`metadata.toml`记录来源和保存时Git状态，脏工作区记录不冒充正式冻结实验。
穷举接口[`enumerate_r7_recovery`](@ref)与[`audit_r7_faults`](@ref)
分别负责固定故障的全部拓扑、同一灾前状态的全部故障，各自共享总预算。

## 6. 下一批

先冻结多支路、多时段案例及灾前状态来源，建立可靠的完整故障穷举基准。
再连接正常运行决策和事件状态继承，逐步实现嵌套C&CG，并与穷举的上下界核对。
双水箱解与详细热网回代必须另有结果；目前不进入第6章性能或弹性优势结论。

## 原生API

~~~@index
Pages = ["ch06-recovery.md"]
~~~

~~~@docs
PaperRebuild.R7RecoveryCase
PaperRebuild.load_r7_recovery_case
PaperRebuild.r7_faults
PaperRebuild.build_r7_recovery
PaperRebuild.solve_r7_recovery
PaperRebuild.validate_r7_recovery
PaperRebuild.enumerate_r7_recovery
PaperRebuild.audit_r7_faults
PaperRebuild.save_r7_recovery
PaperRebuild.read_r7_recovery
~~~
