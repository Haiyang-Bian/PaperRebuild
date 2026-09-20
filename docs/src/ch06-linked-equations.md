# R7空间状态连接：原式、推导与符号

<!-- generated: r7-linked-planning -->

共同正常空间状态到逐管灾后恢复的条件安全规划；正常/恢复流量显式给定，不宣称完整正常控制域。

## 原式 6-70

~~~math
\tau_{jk,t^\prime,\omega,s}^{\mathrm{S/R}}=\tau_{jk,t^\prime,\omega}^{\mathrm{S/R}},\qquad t^\prime=t_s-1
\tag{6-70}
~~~

PDF 114页。原灾时管温与事件前正常管温关联。本项目管状态以动作前的空间分布表示，事件t_s继承正常states[t_s]，不是独立选择的初温。完整空间分布是项目参考状态，不能说原式已经显式给出了它。

## 原式 6-71

~~~math
\tau_{k,t^\prime,\omega,s}^{\mathrm{S/R,mix}}=\tau_{k,t^\prime,\omega}^{\mathrm{S/R,mix}},\qquad t^\prime=t_s-1
\tag{6-71}
~~~

PDF 114页。原节点混合温度初态继承。项目采用零节点容积、子步平均混合：保存事件前正常温度，事件后按新的源荷与来水混合；不把整段事件平均温度固定成前时段平均温度，也不宣称认证了有限节点热容或连续节点动态。

## 原式 6-72

~~~math
|m_{ij,t}-m_{ij,t,s}|\leq\Delta\overline m
\tag{6-72}
~~~

PDF 114页。恢复管流相对正常计划的偏差上界保留。当前两条流量计划均显式给定；这不是对原连续流量可行域的完整优化。

## 原式 6-103

~~~math
F x+H\gamma_\nu^{s*}+K r_\nu^s+J z_\nu^s\leq g,\qquad1\leq\nu\leq l,\ \forall s
\tag{6-103}
~~~

PDF 118页。所有故障恢复块链接同一个本轮正常决策x。详细输运版保留这一结构；改变的是采用的恢复热块，历史双水箱结果不改判。

## R7-L1

~~~math
\xi_{p,s,\omega}=\mathcal T_{p,1:t_s-1}(\xi_{p,1,\omega},\theta^{\mathrm{N}}_{p,1:t_s-1,\omega}),\qquad y_{p,s,\omega}=b_{p,s,\omega}+A_{p,s,\omega}\begin{bmatrix}\theta^{\mathrm{N}}_{p,1:t_s-1,\omega}\\\theta^{\mathrm{D}}_{p,s,\omega}\end{bmatrix}
\tag{R7-L1}
~~~

给定管流后平流散热对入口温度为仿射；y包括事件出口均温、每步库存、全部空间段端温。几何由流量和时间决定，正常历史列来自同一个规划变量。没有自由初温或仅库存相等的替代。

分类：项目详细塞流状态连接，替换双水箱/Taylor近似。实现：[`r7_linked_pipe_map`](@ref)。测试：`test/r7_linked_planning.jl` / `R7-L1 affine history and spatial memory`。

## R7-L2

~~~math
\min_{x\in\mathcal X_{\bar m}} C(x)\quad\mathrm{s.t.}\quad\forall(s,\gamma)\in\mathcal A:\ \exists y_{s,\gamma}\in\mathcal Y^{\mathrm{pipe}}_{\bar m_{s,\gamma}}(x,\gamma),\quad\ell_s(y_{s,\gamma})\leq L_s
\tag{R7-L2}
~~~

共同正常计划连接每个已加入故障的逐管恢复。恢复见证不必自身最小化失供；主问题只最小化正常费用。电池/CHP继承保持原约束，管道空间状态保留所有灾前入口的作用。

分类：给定流量的有限故障全量基准与外层C&CG。实现：[`build_r7_linked_planning`](@ref)。测试：`test/r7_linked_planning.jl` / `R7-L2 shared planning and independent fault witnesses`。

## R7-L3

~~~math
\underline C_k\leq C^\star_{\mathrm{declared}}\leq C(\hat x),\qquad\hat x\text{通过全部声明故障的独立输运回放}
\tag{R7-L3}
~~~

部分故障主问题界属于相同给定流量安全规划；所有故障可交付的正常候选才给上界。任一认证超门槛故障可以加入主问题；旧轮状态不能沿用。条件费用界不等于完整变流量界。

分类：目标与证书范围、独立原值验证。实现：[`validate_r7_linked_planning`](@ref)。测试：`test/r7_linked_planning.jl` / `R7-L3 provenance failures and original value replay`。

## 符号表

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7L-spatial | ``\xi_{p,s,\omega}`` | 事件前管道空间质量段温度状态，项目符号 | kg; K | `initial_pipe_profiles / states` | pipe × side × scenario × segment |
| R7L-history | ``\theta^{\mathrm N},\theta^{\mathrm D}`` | 正常入口历史与灾后子步入口温度，项目语义标签 | K | `normal_inlets / S / R` | pipe × side × scenario × time/substep |
| R7L-map | ``A,b,y`` | 已知流量下的仿射算子、常量与输出；只在管道作用域使用 | 输出为K或MWh；系数按相应行单位/K | `r7_linked_pipe_map.A / .b` | sample × (normal history + event substeps) |
