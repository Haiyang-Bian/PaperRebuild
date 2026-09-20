# R7电池域：原式、推导与符号

<!-- generated: r7-battery-domain -->

原电池和式约束、显式互斥域和理想循环重构；不改变正常/灾时能量边界，不认证完整热安全规划。

## 原式 6-12

~~~math
0\le p_{g,t,\omega}^{\mathrm{BES,C}}+p_{g,t,\omega}^{\mathrm{BES,D}}\le\overline p_g^{\mathrm{BES}}
\tag{6-12}
~~~

PDF 108页。原页印刷91：只给充放功率和式容量，未给互斥。采用版额外明确两种功率分别非负。

## 原式 6-14

~~~math
E_{g,t+1,\omega}^{\mathrm{BES}}-E_{g,t,\omega}^{\mathrm{BES}}=\left(\eta_g^{\mathrm{BES,C}}p_{g,t,\omega}^{\mathrm{BES,C}}-\frac{p_{g,t,\omega}^{\mathrm{BES,D}}}{\eta_g^{\mathrm{BES,D}}}\right)\Delta t
\tag{6-14}
~~~

PDF 108页。功率MW乘以时间h得到MWh；充放效率分别作用，不能用净功率直接替代。6-13另限制能量上下界。

## 原式 6-15

~~~math
E_{g,1,\omega}^{\mathrm{BES}}=E_{g,|\mathcal T|+1,\omega}^{\mathrm{ESS}}
\tag{6-15}
~~~

PDF 108页。保留原末项ESS类别字样；上下文同一电池周期边界，采用实现统一为BES。正常运行保留首末相等。

## 原式 6-61

~~~math
E_{g,t',\omega,s}^{\mathrm{BES}}=E_{g,t',\omega}^{\mathrm{ESS}},\qquad \forall g,\omega,s,\quad t'=t_s-1
\tag{6-61}
~~~

PDF 113页。原页印刷96，保留右侧ESS类别及t'=t_s-1写法。文字说明灾时承接事件前状态、首末相等可忽略。本项目把E[t]定义为第t段动作前的状态，所以事件承接E[t_s]；原分类差异与状态时标转换均显式登记，不将E[t_s-1]再错移一段。

## R7-B1

~~~math
0\le p^{\mathrm{BES,C}}_{g,t,\omega}\le \overline p_g^{\mathrm{BES}}b_{g,t,\omega},\qquad 0\le p^{\mathrm{BES,D}}_{g,t,\omega}\le \overline p_g^{\mathrm{BES}}(1-b_{g,t,\omega}),\qquad b_{g,t,\omega}\in\{0,1\}
\tag{R7-B1}
~~~

b=1允许充电，b=0允许放电，两者都允许闲置。按时段与场景决策，保留原6-12/13/14及各自初末边界。固定电拓扑不会消除该整数变量。

分类：项目新增运行域，非原式笔误修正。实现：[`with_r7_battery_rule`](@ref)。测试：`test/r7_battery.jl` / `R7-B1 declared domain and fixed modes`。

## R7-B2

~~~math
\begin{aligned}\delta&=\min(p^C,p^D),&p^{C\prime}&=p^C-\delta,&p^{D\prime}&=p^D-\delta,\\p^{D\prime}-p^{C\prime}&=p^D-p^C,&\Delta E^{\prime}-\Delta E&=\Delta t\,\delta\left(\frac{1}{\eta^D}-\eta^C\right).\end{aligned}
\tag{R7-B2}
~~~

等量移除循环保持净注入。非理想效率使能量增量增加，可能违反能量上界或周期等式；本次三个原Clarabel输入双效率为1，才可保持原能量与其他控制不变。重构另存并验全模型，不继承求解器界。

分类：由原6-14推导的恒等式，非通用修复保证。实现：[`r7_battery_cycle_effect`](@ref)。测试：`test/r7_battery.jl` / `R7-B2 preserved injection is not preserved energy`。

## R7-B3

~~~math
\mathcal F_{\mathrm{exclusive}}\subseteq\mathcal F_{\mathrm{sum}},\qquad L^\star_{\mathrm{sum}}\le L^\star_{\mathrm{exclusive}}
\tag{R7-B3}
~~~

在相同条件下最小化失供，增加互斥约束不会降低理论最优值；两次求解得到不同候选不能单凭费用大小证明相反结论。正常、事件、有限故障规划一致传递运行域。旧仅拓扑LP对偶算法明确拒绝未固定互斥电池。

分类：相同输入、目标、状态和其他边界下的集合包含关系。实现：[`r7_reconstruct_battery_cycles`](@ref)。测试：`test/r7_battery.jl` / `R7-B3 normal event and finite fault planning`。

## 符号表

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7B-mode | ``b_{g,t,\omega}`` | 项目新增充放模式，1充电/0放电，可闲置；不是原文符号 | 1 | `b_BES[g,t,w]` | device × time × scenario |
| R7B-charge | ``p_{g,t,\omega}^{\mathrm{BES,C}},p_{g,t,\omega}^{\mathrm{BES,D}}`` | 原充电/放电非负功率；代码延续既有P主名，登记小写p别名 | MW | `P_ch[g,t,w], P_dis[g,t,w]` | device × time × scenario |
| R7B-cycle | ``\delta,\Delta E^{\prime}-\Delta E`` | 同时充放移除量及每步能量增量变化，不是新增储能资源 | MW; MWh | `removed_cycle_MW; energy_increment_MWh` | one device-time-scenario |
