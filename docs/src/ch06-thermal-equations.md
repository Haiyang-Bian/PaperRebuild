# R7逐管热重构：方程与符号

<!-- generated: r7-thermal -->

固定原恢复控制的逐管温度重构；子步平均混合，连续塞流管道参考；不是完整连续热网或水力认证。

## R7-T1

~~~math
\boldsymbol y_{a\omega}=A_a(\boldsymbol m_a)\boldsymbol\tau_a^{\rm in}+\boldsymbol b_a(\boldsymbol T_{a,0},\boldsymbol T^{\rm amb})
\tag{R7-T1}
~~~

给定有符号流量后，分段常入口的平流散热是仿射算子。输出y含子步出口平均、各边界库存和全部质量段的两端温度；停流没有出口温度。供水坐标from→to，回水坐标to→from，反转不重置初态。

来源：6-39:43、project R7-P1:P4；分类`project continuous plug-flow reference, not literal node method`。

实现：[`build_r7_thermal_reconstruction`](@ref)。测试：`test/r7_thermal.jl` / `R7-T signed, stopped and lossy affine transport`。

## R7-T2

~~~math
H_{j,t,\omega}^{\rm src}=\frac{c_w}{10^6}m_{j,t}^{\rm src}(\tau_{j,t,\omega}^{\rm src}-\tau_{j,t,\omega}^{R}),\quad H_{j,t,\omega}^{\rm delivered}=\frac{c_w}{10^6}m_{j,t}^{\rm load}(\tau_{j,t,\omega}^{S}-\tau_{j,t,\omega}^{\rm load})
\tag{R7-T2}
~~~

端口流来自原恢复，非负源/荷分开。比热J/(kg K)、流量kg/s、热功率MW。same_dispatch固定原热交付；curtail_heat允许在原失供边界内进一步削减，不重调电网或热源。每原时段各子步保持原源功率。

来源：6-26、6-28、6-83、6-84；分类`project fixed-control reconstruction of original exact port relations`。

实现：[`build_r7_thermal_reconstruction`](@ref)。测试：`test/r7_thermal.jl` / `R7-T fixed-control thermal reconstruction`。

## R7-T3

~~~math
\tau_{j,t,\omega}^{S}=\frac{\sum_{a\in\delta_S^-(j,t)}|m_{a,t}|\bar\tau_{a,t,\omega}^{S,\rm out}+m_{j,t}^{\rm src}\tau_{j,t,\omega}^{\rm src}}{\sum_{a\in\delta_S^-(j,t)}|m_{a,t}|+m_{j,t}^{\rm src}}
\tag{R7-T3}
~~~

实际流向决定入流集合；回水用相反管向和负荷回温。分母为零的节点没有热流，设参考温度仅消除未使用变量自由度。此处是子步平均混合，不是瞬时混合，必须单列细分敏感性。

来源：6-37、6-38；分类`project substep-mean network closure`。

实现：[`validate_r7_thermal_reconstruction`](@ref)。测试：`test/r7_thermal.jl` / `R7-T spatial memory and refinement`。

## R7-T4

~~~math
E_{a,k}^{q}=\frac{c_w}{3.6\times10^9}\int_0^{M_a^q}(T_{a,k}^q(\xi)-T_{\min}^q)\,d\xi,\qquad \Delta\sum_{a,q}E_{a,k}^q=\Delta t\left(\sum_jH_{j,k}^{\rm src}-\sum_jH_{j,k}^{\rm delivered}\right)-\sum_{a,q}E_{a,k}^{q,\rm loss}
\tag{R7-T4}
~~~

逐管库存独立积分，供回水各一次；散热由水团停留时间积分，不由总守恒倒推。验证整个子步边界空间温度，不能仅以均温落在范围内通过。子步内节点入口仍为常值近似，水力和管壁热容未纳入。

来源：6-76:90、project R7-P2:P4；分类`project spatial inventory and independent energy audit`。

实现：[`validate_r7_thermal_reconstruction`](@ref)。测试：`test/r7_thermal.jl` / `R7-T fixed-control thermal reconstruction`。

## R7-T5

~~~math
H_{j,t}^{\rm src}\ge\frac{c_w}{10^6}m_{j,t}^{\rm src}\max\left(\Delta\tau_{j,\min}^{\rm src},\tau_{\min}^{S}-\tau_{\max}^{R}\right)
\tag{R7-T5}
~~~

采用同样供回温区间时，正循环流通常产生正的最小加热功率；原端口包络若允许零温差，可能漏掉这一必要条件。违背它证明该固定控制无法重构；未触发不能证明可行。

来源：6-26:29、6-83；分类`derived necessary condition for adopted temperature intervals`。

实现：[`r7_thermal_port_witness`](@ref)。测试：`test/r7_thermal.jl` / `R7-T fixed-control thermal reconstruction`。

## R7-T-Q01

原文：PDF115–116以双水箱总能量和端口温差包络替代节点/管道温度变量，使用近参考温度的循环交换近似。

采用：保留原恢复判定；新检查固定控制后重新引入逐管空间状态。总能量足够只是必要信息之一，不直接给出按位置和时间可交付的热量。

状态：`reconstruction implemented; old claims unchanged`。

## R7-T-Q02

原文：式6-90只使用管温聚合到总能量，不能唯一还原空间温度分布。

采用：正常事件沿用完整分段profiles；只有显式声明均匀假设才从旧均温构造初态。初态质量与均温必须匹配继承值。

状态：`explicit profile provenance required`。

## 符号表

| ID | 数学符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7T-temperature | ``\tau^S,\tau^R,\tau^{\rm src},\tau^{\rm load},\bar\tau^{q,\rm out}`` | 子步混合温度、热源出口、负荷回温、管道时间平均出口；代码S/R仅在本温度重构作用域内表示温度 | K | `S,R,T_source,T_load,out_S,out_R` | node or pipe × substep × scenario |
| R7T-state | ``T_{a,0}^q(\xi),E_{a,k}^q`` | 显式初始空间分布及子步边界相对显热，q为供/回侧，ξ为空间质量坐标 | K; MWh; kg | `profiles,R7PipeState,E_S,E_R` | pipe × side × scenario; pipe × (K+1) × scenario |
| R7T-control | ``m_a,m_j^{\rm src},m_j^{\rm load},H_j^{\rm src},H_j^{\rm delivered}`` | 原有有符号管流、非负端口流、固定源功率和核查的实际交付 | kg/s; MW | `m_pipe,m_source,m_load,generated,H_delivered` | flow shared across scenarios; heat node × substep × scenario |
| R7T-time | ``t,k,n,\Delta t`` | 原时段、细分子步、每时段细分数和细分后小时步长；不改变事件物理时长 | 1; h | `t,k,substeps,dt` | k=1:T*n, t=ceil(k/n) |
