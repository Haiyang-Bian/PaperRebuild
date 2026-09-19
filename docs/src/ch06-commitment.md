# R7：灾前启停与状态继承

本批把正常运行中的慢启停CHP做成可嵌入JuMP模型的约束块。
它是后续完整灾前规划的一部分；目前不含完整电热网络、灾前电池优化或嵌套C&CG。
原件核查范围为PDF106–107、109–110、116–117；权威推导和符号见[采用台账](ch06-commitment-equations.md)。

## 为什么先核清启停？

作者让CHP的启停计划在灾后保持，但允许调整其出力。因此灾前计划决定了灾后的资源可用性。
如果启动定义错误，恢复模型再精确也可能继承一个本来无法执行的计划。

PDF106定义原``\nu``为启动指示。PDF107式（6-6）在真正启动时却要求``1\le0``。
本项目保留这个字面反例，按“开机后须连续运行、关机后须连续停机”的作者文字重建
[启停转移](ch06-commitment-equations.md#R7-N1)与[最短持续时间](ch06-commitment-equations.md#R7-N2)。
并不是把一个不明符号直接改名：新增关停指示、初始持续小时数和末端规则均单独登记。
与[PyPSA官方启停说明](https://docs.pypsa.org/latest/user-guide/optimization/unit-commitment/)对照了
历史与爬坡语义；计算仍完全使用Julia/JuMP，没有增加依赖。

## 首时段与末时段怎样处理？

假设最短开机时间2小时，窗口开始前已经开机0.5小时，时间步1小时。
剩余1.5小时不能向下取整成1小时，前两个区间仍需保持开机。
若在四时段窗口的最后一个时段才开机，则窗口结束时仍欠1小时：

- `carry_obligation`保存这项义务，下一窗口必须接着执行。
- `complete_within_horizon`禁止这种晚启动，要求最短持续义务在当前窗口内完成。

两者是不同边界；原文没有明确选择，输入必须显式指定。电池的初末相等条件不自动变成CHP周期条件。
正常爬坡参数为MW/h，需要乘时间步；启动与关停上限为边界功率变化MW，不再次乘时间步。

## 可手算的设备调度

合成配置`configs/r7/chp-component-hand.toml`给出4个一小时时段、两场景，概率0.25与0.75。
测试中的电需求分别为`[0.5,1,0.5,0]`和`[0.6,0.8,0.4,0]`MW，外购价100合成USD/MWh。
CHP运行费20合成USD/MWh、启动费30合成USD/次，初始已停机3小时，最短开机2小时。

可达最优为共同启停`[1,1,1,0]`，按场景发电2和1.8MWh：

~~~math
C=30+20(0.25\times2+0.75\times1.8)=67\quad\mathrm{USD}.
\tag{R7-N-HAND}
~~~

若从未开机，全部外购费用为185；任意开机计划至少支付一次启动费30，
且每MWh供电成本至少20，故运行费用不低于37。已给候选达到下界67，因此可手算核对全局最优。
此例只核验设备块与教学供需平衡，未加入真实网络和热负荷，不能称为完整灾前调度。
原式（6-1）的CHP费用按电出力计；接页正文对电、热成本的说明未完全闭合，
本输入显式采用`electric_equivalent`，没有擅自重复计费。

## 连接到灾后恢复的哪一部分？

[`r7_chp_event_boundary`](@ref)先独立验证原值，再提取事件期间启停与前一正常区间的各场景出力。
上述案例在第3时段发生事件时，继承启停`[1,0]`，前一出力为`[1,0.8]`MW。
它不会把两个场景平均，也不会误用第3时段出力替代故障前的第2时段出力。

返回值带规格/原值哈希、设备ID、时间步和概率；`scope="chp_component_only"`与
`preplan_optimality_verified=false`明确其范围。电池能量与管温还需完整正常模型提供。

## 为什么没有把正常热网直接写成MILP？

原正常模型式（6-26）—（6-46）有热功率乘积、水力平方项、混合和变流量输运。
[中点反例](ch06-commitment-equations.md#R7-N7)表明保留这些关系时不能直接得到线性可行域。
PDF116的文字明确把双水箱替换用于6.3.3的恢复热网，不能自动将它扩大到正常运行。
后面的式（6-92）写为``Ax\le b``，其所需的额外固定量/线性化仍需核清。

后续继续建立详细正常热网基准；若另建固定流量或双水箱规划版本，将显式命名并比较。
特别是灾前管温到恢复初始显热的转换，必须核对空间平均状态，不能把出口温度直接乘全管体积。

## Julia与验收入口

~~~julia
using PaperRebuild, JuMP, TOML
spec = R7CHPSpec(TOML.parsefile("configs/r7/chp-component-hand.toml"))
model = Model()
chp = add_r7_chp_commitment!(model, spec)
# 将chp.variables的P/Q/H连接到正常网络，再合成完整目标；本接口不自行求解。
~~~

VS Code提供映射检查和专项测试，对应：

~~~text
julia +1.12.6 --startup-file=no --project=. scripts/check_r7_commitment.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_commitment.jl
~~~

测试用6套初始/末端条件穷举各16个状态序列，将JuMP线性约束与独立逐段计时判据比较。
另外检查启机费用、场景共享、半小时换算、爬坡、继承下标、原值变化和非凸热关系反例。
测试通过只认证上述范围；完整正常网络与灾前—故障—恢复闭环仍未完成。

## 原生API

~~~@index
Pages = ["ch06-commitment.md"]
~~~

~~~@docs
PaperRebuild.R7CHPSpec
PaperRebuild.add_r7_chp_commitment!
PaperRebuild.validate_r7_chp
PaperRebuild.r7_chp_event_boundary
~~~
