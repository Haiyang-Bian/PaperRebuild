# R7联合流量：推导与符号

<!-- generated: r7-flow-planning -->

共同正常空间状态、连续正向正常管流与连续非负恢复管流；零散热、固定正常电拓扑、子步平均节点。

原初态及流量变化三式只在linked-planning.toml保留一份逐式定义。PDF117的6-93及6-97至99用各允许故障存在门槛内恢复的等价结构；本项目详细非凸输运不继承原紧凑MILP/LP对偶保证。 原式见[共同空间状态台账](ch06-linked-equations.md)。

## R7-J1

~~~math
0<\underline m^{\mathrm N}\le m^{\mathrm N}\le\overline m^{\mathrm N},\quad 0\le\underline m^{\mathrm D}\le m^{\mathrm D}\le\overline m^{\mathrm D},\quad |m^{\mathrm D}_{p,t,s,\gamma}-m^{\mathrm N}_{p,t}|\le\Delta\overline m_p
\tag{R7-J1}
~~~

正常活动端口保持正流，恢复允许停流；节点端口分别非负。每个流量矩阵不含新能源场景维度；不同故障可分别决策，但灾前计划共同。最后一项回接原6-72中的本轮正常变量，不再读取旧参考常数。

API：[`r7_flow_planning_spec`](@ref)。测试：`test/r7_flow_planning.jl` / `R7-J1/J4 failures remain explicit`。

## R7-J2

~~~math
\min_{x,m^{\mathrm N}} C(x)\quad\mathrm{s.t.}\quad\forall(s,\gamma)\in\mathcal A:\exists (y_{s,\gamma},m^{\mathrm D}_{s,\gamma})\in\mathcal Y(x,m^{\mathrm N},\gamma),\quad \ell_s(y_{s,\gamma})\le L_s
\tag{R7-J2}
~~~

原6-93/97至99的有限故障存在性结构，热块改用项目无损详细输运。正常成本是唯一目标，各恢复见证不必最小化失供；它们不能带失供最优界。全部流量固定退化到LP/MILP，至少一个流量自由通常为非凸MIQCP，按实际MOI类型报告。

API：[`build_r7_flow_planning`](@ref)。测试：`test/r7_flow_planning.jl` / `R7-J2 fixed degeneration and all fault inheritance`。

## R7-J3

~~~math
\boldsymbol q_{p,s,\gamma}=\left(\frac{3600\Delta t\,m^{\mathrm N}_{p,1:t_s-1}}{M_p},\frac{3600\delta t\,m^{\mathrm D}_{p,s,\gamma}}{M_p}\right),\quad \xi_{p,s,\omega}=\mathcal T(\xi_{p,1,\omega},\boldsymbol q^{\mathrm N},\boldsymbol\tau^{\mathrm N}_{\mathrm{in},\omega})
\tag{R7-J3}
~~~

沿用R7-F2/F3的质量区间交集，在同一初始空间段上拼接正常前缀与恢复后缀；δt=Δt/substeps。没有自由事件初温。q=0时出口平均温度不可观测，但库存仍守恒且重启继承原水团。源荷热功率为0乘温差，因此闲置温度不生成热量；有正流时仍检查源荷温差及混合。

API：[`add_r7_mass_transport!`](@ref)。测试：`test/r7_flow_planning.jl` / `R7-J1/J3 zero flow retains spatial memory`。

## R7-J4

~~~math
\mathrm{Accept}=V_{\mathrm N}\land\bigwedge_{(s,\gamma)\in\mathcal A}\left(V_{s,\gamma}^{\mathrm{inherit}}\land V_{s,\gamma}^{\mathrm{replay}}\land[\ell_s\le L_s]\right)
\tag{R7-J4}
~~~

从保存的正常流量/入口温度独立裁切水团得到每个事件的空间状态，再检查恢复边界、设备、线性电网、质量/热量、温度、库存和失供。停流出口仅不作观测误差判定，其声明温区仍检查；不裁剪负原值，不放宽A1。费用认证只属于声明的联合域。

API：[`validate_r7_flow_planning`](@ref)。测试：`test/r7_flow_planning.jl` / `R7-J2 fixed degeneration and all fault inheritance`。

## 符号表

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7J-flow | ``m^{\mathrm N},m^{\mathrm D}_{s,\gamma}`` | 共同正常流量与逐事件/故障恢复流量，N/D为项目语义标签 | kg/s | `normal.flow_values / witnesses.values.m_pipe,m_source,m_load` | pipe/node × time；事件/故障单独保存；无新能源场景轴 |
| R7J-prefix | ``\xi_{p,s,\omega},\boldsymbol q_{p,s,\gamma}`` | 同一正常历史确定的事件空间状态与拼接质量序列 | kg,K; q无量纲 | `r7_joint_event_values.profiles / cumulative` | pipe × side × scenario × segment；q为normal prefix + event substeps |
| R7J-witness | ``y_{s,\gamma},\ell_s,L_s`` | 恢复存在性见证、概率加权电热失供及门槛 | 见证按各变量单位；失供为MWh | `witnesses / witness_loss_MWh / loss_limit_MWh` | one record per allowed event and fault |
