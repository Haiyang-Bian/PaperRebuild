# R7相容端口：推导与符号

<!-- generated: r7-compatible-ports -->

旧双水箱代理的显式温区必要条件、孤岛失供解析下界及规划传播；不是详细热模型，也不是已确认的作者笔误修正。

## R7-C1

~~~math
\begin{aligned}\Delta\tau_{j,\min}^{q,\rm compatible}&=\max\{\Delta\tau_{j,\min}^{q},\tau_{\min}^{S}-\tau_{\max}^{R}\},\\\Delta\tau_{j,\max}^{q,\rm compatible}&=\min\{\Delta\tau_{j,\max}^{q},\tau_{\max}^{S}-\tau_{\min}^{R}\},\\\frac{c_w}{10^6}m_j^q\Delta\tau_{j,\min}^{q,\rm compatible}&\le H_j^q\le\frac{c_w}{10^6}m_j^q\Delta\tau_{j,\max}^{q,\rm compatible},\quad q\in\{\mathrm{src},\mathrm{load}\}.\end{aligned}
\tag{R7-C1}
~~~

源、荷端口均采用非负流。原6-83/84包络保留，新增供回温区投影。当前合成温区给出10至50K；与原包络取交集。正流交集为空则只能关闭该端口，不改输入界或静默删约束。此条件没有描述温度的位置和输运。

来源：6-26:29、6-81:84、project global temperature-box interpretation；分类`project strengthening under declared common temperature intervals`。

实现：[`r7_port_temperature_bounds`](@ref)。测试：`test/r7_ports.jl` / `R7-C1 versioned interval projection`。

## R7-C2

~~~math
\left[\forall j:H_j^{\rm src}=0,\ \Delta\tau_{j,\min}^{\rm src,compatible}>0\right]\Rightarrow\sum_jm_j^{\rm src}=\sum_jm_j^{\rm load}=0\Rightarrow H_j^{\rm delivered}=0\Rightarrow L_H\ge\sum_\omega\pi_\omega\sum_{j,t}H_{j,t}^{D}\Delta t
\tag{R7-C2}
~~~

本采用无损电网里，无任何有功消纳端的电孤岛使其非负发电总和为零。若全部热源均被这一关系限制，源端口正温差使源流为零，再由质量守恒、非负荷流与有限温差迫使全部热失供。存在微小正电负荷、可充电电池或电锅炉时，该接口保守拒绝证书，不以数值容差将它们忽略。

来源：6-11、6-19、6-26、6-73、6-83:84；分类`derived necessary loss bound in adopted linear-electric compatible-port domain`。

实现：[`r7_island_heat_bound`](@ref)。测试：`test/r7_ports.jl` / `R7-C2 bound, counterexamples and independent values`。

## R7-C3

~~~math
\exists s,\gamma\in\mathcal U_s:\quad\underline L_H(s,\gamma)>\overline L_s\quad\Longrightarrow\quad\nexists x\ \text{satisfying all declared resilience constraints}
\tag{R7-C3}
~~~

只有当解析下界独立于允许的灾前状态、且设备与潜在恢复电网保持不变时，才能推广为规划不可行。当前单源断线例的热失供必要下界0.4MWh已经超过原零门槛。另设0.4MWh的规划仅是诊断对照，不把放宽目标当作原问题修复。

来源：6-52:53、R7-C2、project synthetic single-source cut；分类`conditional planning impossibility proof, not a global physical claim`。

实现：[`with_r7_port_temperature_bounds`](@ref)。测试：`test/r7_ports.jl` / `R7-C3 planning domain and common event propagation`。

## R7-C-Q01

原文：6-27按热源节点给供温范围，没有写乘以启停变量或零产热时豁免。6-73:90简化后用端口温差包络和全网储热代替具体温度。

采用：本批保留原合成输入的温区，显式新增port_checked版本；此前原项目包络0至80K/0至60K比温区相容的10至50K更宽。首先是项目采用模型的内部相容性问题，不能直接认定作者原参数也有这一错误。

状态：`original pages checked; no silent off-source exemption`。

## R7-C-Q02

原文：管内热量可能在没有新产热时释放，但是否能循环取热仍依赖实际端口温区、空间输运和泵/旁通条件。

采用：不把本输入的无热交付证明扩展为所有储热均无价值。若允许停机循环降温或加入旁通，须显式建立新边界与设备模型；本批没有实现该改动，也没有为通过而调整温区。

状态：`alternative operating interpretation remains a separate research question`。

## 符号表

| ID | 数学符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7C-port | ``\Delta\tau_{j,\min/\max}^{q,\rm compatible}`` | 原端口包络与采用供回温区的相容交集；描述性上标为项目规则 | K | `source_min,source_max,load_min,load_max` | heat node |
| R7C-bound | ``\underline L_H,\overline L_s`` | 期望热失供必要下界与事件期望电热失供上限；二者不能当实际调度费用 | MWh | `minimum_heat_loss_MWh,loss_limit_MWh` | fixed fault and event |
| R7C-island | ``\mathcal C_{\rm no\ sink}`` | 健康线路全连接的超图中，无负荷、电锅炉或可充电电池的电连通分量 | 1 | `no_sink_electric_components` | vector of node sets |
