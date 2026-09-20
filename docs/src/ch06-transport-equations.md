# R7逐管联合恢复：推导与符号

<!-- generated: r7-transport-recovery -->

原6-26至29端口关系与项目逐管输运参考的联合恢复；替换6-73至90中的双水箱/Taylor部分。给定管流，不冒称全变流量或作者完整模型等价实现。

## R7-D1

~~~math
\min_{y,\tau}\ \sum_\omega\pi_\omega\sum_t\Delta t\!\left(\sum_iP_{i,t,\omega}^{\rm shed}+\sum_jH_{j,t,\omega}^{\rm shed}\right),\qquad m=\bar m,\quad y\in\mathcal Y_{\rm electric,device,flow},\quad (y,\tau)\in\mathcal T_{\rm pipe}
\tag{R7-D1}
~~~

给定跨场景共享流量，设备和失供按原时段重新优化；逐管状态、端口功率、混合按子步闭合。原双水箱库存及Taylor交换块显式移除，不与详细热库存强行同时成立。保留原输入、设备和线性电网。

来源：6-26:29、6-51:75、R7-T1:T4、project conditional redispatch；分类`project detailed transport reference in prescribed-flow domain`。

实现：[`build_r7_transport_recovery`](@ref)。测试：`test/r7_transport.jl` / `R7-D1 conditional redispatch and original compatibility`。

## R7-D2

~~~math
\begin{aligned}\underline\tau^{\rm out}_{a,k}&=\Phi_{a,k}(\underline\tau^{\rm in};\tau^0,\bar m),&\overline\tau^{\rm out}_{a,k}&=\Phi_{a,k}(\overline\tau^{\rm in};\tau^0,\bar m),\\H^{\rm src}_{j,t}&\le c_w\bar m^{\rm src}_{j,t}(\overline\tau^{S}-\underline\tau^R_{j,k})/10^6,&H^{\rm delivered}_{j,t}&\le c_w\bar m^{\rm load}_{j,t}(\overline\tau^S_{j,k}-\underline\tau^{R})/10^6.\end{aligned}
\tag{R7-D2}
~~~

给定流量的被动平流散热对入口温度单调。以入口温区两端回放获得出口必要区间，节点按流量加权，再与原端口温差包络取交集。初始水尚未排完时，出口受空间初态限制。代码同时计算功率下界，记录原调度的MW缺口。只是原父调度冲突见证；不称最小IIS或充分可行条件。

来源：6-26:29、R7-T1:T3、monotonicity of adopted passive transport；分类`derived necessary interval test`。

实现：[`r7_transport_port_witness`](@ref)。测试：`test/r7_transport.jl` / `R7-D2 transport interval conflict`。

## R7-D3

~~~math
L_{\rm free\ flow}^{\star}\le L^{\star}(\bar m)\le L(y_{\rm feasible},\bar m)
\tag{R7-D3}
~~~

仅当热模型、状态、边界相同且自由域包含这条流量计划时，固定流量可行解是自由问题的候选上界。固定流量求解器下界不是自由问题下界；条件不可行也不证明所有流量不可行。子步热合格、水力、交流电网与全故障安全分别标记。

来源：set inclusion under identical model and boundaries、project certificate scope；分类`conditional bound interpretation`。

实现：[`validate_r7_transport_recovery`](@ref)。测试：`test/r7_transport.jl` / `R7-D3 evidence, failures and validation`。

## 符号表

| ID | 数学符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7D-flow | ``\bar m_{a,t},\bar m_{j,t}^{\rm src},\bar m_{j,t}^{\rm load}`` | 给定流量计划；管流可带符号，源荷端口非负，跨新能源场景共享 | kg/s | `flow_schedule[m_pipe/m_source/m_load]` | pipe or node × original time |
| R7D-temperature | ``\tau^S_{j,k,\omega},\tau^R_{j,k,\omega},\tau_{j,k,\omega}^{\rm src},\tau_{j,k,\omega}^{\rm load}`` | 节点混合、源供水与负荷回水温度分别记录；k是子步，不替代原调度t | K | `S,R,T_source,T_load` | node × thermal substep × scenario |
| R7D-gap | ``\delta H=\max\{\underline H-H,H-\overline H,0\}`` | 原父调度违反输运必要功率区间的缺口；不是新增能源、松弛调度或费用 | MW | `gap_MW` | port × thermal substep × scenario |
