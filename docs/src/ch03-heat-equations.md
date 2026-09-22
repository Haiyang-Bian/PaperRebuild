# [第3章热网与简化式](@id ch03-heat-equations)

<!-- GENERATED: scripts/ch03_docs.jl -->

[设备、电网与水力](@ref ch03-equations) · [符号表](@ref ch03-symbols)。

## [（3-27）时段末管内质量覆盖](@id eq-ch03-027)

```math
\sum_{\varsigma=0}^{T_d}\alpha_{jk,t,\varsigma}m_{jk,t-\varsigma}\Delta T=\rho_wA_{jk}L_{jk}
\tag{3-27}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-28）alpha连续填充互补](@id eq-ch03-028)

```math
(1-\alpha_{jk,t,\varsigma})\alpha_{jk,t,\varsigma+1}=0,\quad\varsigma=0,\ldots,T_d-1
\tag{3-28}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-29）alpha权重界](@id eq-ch03-029)

```math
0\le\alpha_{jk,t,\varsigma}\le1,\quad\varsigma=0,\ldots,T_d
\tag{3-29}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-30）时段初管内质量覆盖](@id eq-ch03-030)

```math
\sum_{\varsigma=1}^{T_d}\beta_{jk,t,\varsigma}m_{jk,t-\varsigma}\Delta T=\rho_wA_{jk}L_{jk}
\tag{3-30}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-31）beta连续填充互补](@id eq-ch03-031)

```math
(1-\beta_{jk,t,\varsigma})\beta_{jk,t,\varsigma+1}=0,\quad\varsigma=0,\ldots,T_d-1
\tag{3-31}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-32）beta当前项与边界](@id eq-ch03-032)

```math
\beta_{jk,t,0}=1,\quad0\le\beta_{jk,t,\varsigma}\le1,\quad\varsigma=1,\ldots,T_d
\tag{3-32}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-33）无损出口质量加权温度](@id eq-ch03-033)

```math
m_{jk,t}\tau_{jk,t}^{S/R,out*}=\sum_{\varsigma=0}^{T_d}(\beta_{jk,t,\varsigma}-\alpha_{jk,t,\varsigma})m_{jk,t-\varsigma}\tau_{jk,t-\varsigma}^{S/R,in}
\tag{3-33}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-34）水质法热损耗](@id eq-ch03-034)

```math
\tau_{jk,t}^{S,out}=\widehat\tau_t^{AM}+(\tau_{jk,t}^{S,out*}-\widehat\tau_t^{AM})^{\frac{\epsilon_{jk}\Delta T}{2c_w\rho_wA_{jk}}(\sum_{\varsigma=0}^{T_d}\beta_{jk,t,\varsigma}+\sum_{\varsigma=0}^{T_d}\alpha_{jk,t,\varsigma})}
\tag{3-34}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：240dpi局部图核对：未印e或负号，温差括号直接作幂底；literal阻断，不将物理修正写进原式。 历史输入显式；逐段水质量恒定；原3-34保留转录，checked版采用负指数和beta从滞后1开始的版本。

**疑点：R2-C02。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 transport ch03-027:034`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[alpha](@ref sym-ch03-alpha)、[beta](@ref sym-ch03-beta)、[Td](@ref sym-ch03-Td)、[dt](@ref sym-ch03-dt)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_star](@ref sym-ch03-tau_star)、[tau_ambient](@ref sym-ch03-tau_ambient)、[epsilon](@ref sym-ch03-epsilon)、[cp](@ref sym-ch03-cp)。

## [（3-35）供水混合温度](@id eq-ch03-035)

```math
\tau_{k,t}^{S,mix}=\frac{\sum_{j:j\to k}m_{jk,t}\tau_{jk,t}^{S,out}+m_{k,t}\tau_{k,t}^{S}}{\sum_{j:j\to k}m_{jk,t}+m_{k,t}}
\tag{3-35}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

**疑点：R2-C01。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-36）回水混合温度](@id eq-ch03-036)

```math
\tau_{k,t}^{R,mix}=\frac{\sum_{l:l\to k}m_{lk,t}\tau_{lk,t}^{R,out}+m_{k,t}\tau_{k,t}^{R}}{\sum_{l:l\to k}m_{lk,t}+m_{k,t}}
\tag{3-36}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

**疑点：R2-C01。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-37）热源回水连接](@id eq-ch03-037)

```math
\tau_{k,t}^{R}=\tau_{k,t}^{R,mix},\quad k\in\mathcal J^S
\tag{3-37}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-38）热负荷供水连接](@id eq-ch03-038)

```math
\tau_{k,t}^{S}=\tau_{k,t}^{S,mix},\quad k\in\mathcal J^D
\tag{3-38}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-39）供水管入口连接](@id eq-ch03-039)

```math
\tau_{jk,t}^{S,in}=\tau_{j,t}^{S,mix}
\tag{3-39}
```

出处：PDF 49 / 正文 32；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-40）回水管入口连接](@id eq-ch03-040)

```math
\tau_{lk,t}^{R,in}=\tau_{l,t}^{R,mix}
\tag{3-40}
```

出处：PDF 50 / 正文 33；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-41）全部供回水温度界](@id eq-ch03-041)

```math
\underline\tau^S\le\tau^S\le\overline\tau^S,\quad\underline\tau^R\le\tau^R\le\overline\tau^R
\tag{3-41}
```

出处：PDF 50 / 正文 33；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 按实际供回水方向确定入流，热源注入供水、负荷注入回水；不能将负的净注入直接当混合权重。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)、[bounds](@ref sym-ch03-bounds)。

## [（3-42）热功率McCormick原式](@id eq-ch03-042)

```math
\begin{aligned}H_{j,t}^{net}&\ge c_wm_{j,t}\underline{\Delta\tau}_j+\underline m_j(\Delta\tau_j-\underline{\Delta\tau}_j)\\H_{j,t}^{net}&\ge c_wm_{j,t}\overline{\Delta\tau}_j+\overline m_j(\Delta\tau_j-\overline{\Delta\tau}_j)\\H_{j,t}^{net}&\le c_wm_{j,t}\overline{\Delta\tau}_j+\underline m_j(\Delta\tau_j-\overline{\Delta\tau}_j)\\H_{j,t}^{net}&\le c_wm_{j,t}\underline{\Delta\tau}_j+\overline m_j(\Delta\tau_j-\underline{\Delta\tau}_j)\end{aligned}
\tag{3-42}
```

出处：PDF 50 / 正文 33；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

**疑点：R2-C03。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-43）节点温差和流量盒](@id eq-ch03-043)

```math
\underline{\Delta\tau}_j\le\Delta\tau_j=\tau_{j,t}^S-\tau_{j,t}^R\le\overline{\Delta\tau}_j,\quad\underline m_j\le m_{j,t}\le\overline m_j
\tag{3-43}
```

出处：PDF 50 / 正文 33；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-44）热网能量状态原式](@id eq-ch03-044)

```math
E_t^{DHN}=E_{t-1}^{DHN}+\sum_jH_{j,t}-\sum_{(j,k)}(H_{jk,t}^{S,loss}+H_{jk,t}^{S,loss})
\tag{3-44}
```

出处：PDF 50 / 正文 33；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

**疑点：R2-C04。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-45）热网能量界](@id eq-ch03-045)

```math
0\le E_t^{DHN}\le\overline E^{DHN}
\tag{3-45}
```

出处：PDF 50 / 正文 33；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-46）初始能量原式](@id eq-ch03-046)

```math
E_0^{DHN}=c_w\rho_w\sum_{(j,k)}\left\{2A_{jk}L_{jk}\left[\left(\frac{\tau_{jk,0}^{S,in}+\tau_{jk,0}^{S,out}}2-\underline\tau^S\right)+\left(\frac{\tau_{jk,0}^{R,in}+\tau_{jk,0}^{R,out}}2-\underline\tau^R\right)\right]\right\}
\tag{3-46}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

**疑点：R2-C04。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-47）最大能量原式](@id eq-ch03-047)

```math
\overline E^{DHN}=c_w\rho_w\sum_{(j,k)}\left\{A_{jk}L_{jk}(\overline\tau^S-\underline\tau^S)+(\overline\tau^R-\underline\tau^R)\right\}
\tag{3-47}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

**疑点：R2-C04。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-48）供水稳态热损失推导式](@id eq-ch03-048)

```math
\tau_{jk,t}^{S,out}=(\tau_{jk,t}^{S,in}-\widehat\tau_t^{AM})e^{-\epsilon_{jk}L_{jk}/(c_wm_{jk,t})}+\widehat\tau_t^{AM}
\tag{3-48}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：推导背景，不与3-52动态式同时强加。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-49）回水稳态热损失推导式](@id eq-ch03-049)

```math
\tau_{lk,t}^{R,out}=(\tau_{lk,t}^{R,in}-\widehat\tau_t^{AM})e^{-\epsilon_{lk}L_{lk}/(c_wm_{lk,t})}+\widehat\tau_t^{AM}
\tag{3-49}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：推导背景，不作为第二套独立动态约束。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-50）参考供水温度下的定热损耗](@id eq-ch03-050)

```math
H_{jk,t}^{S,loss}=\epsilon_{jk}L_{jk}(\tau_{jk,t}^{S,in}-\widehat\tau_t^{AM})\approx\epsilon_{jk}L_{jk}(\widehat\tau^{S,ref}-\widehat\tau_t^{AM})=\overline\epsilon_{ij,t}^{S}
\tag{3-50}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：作者近似；定损耗开关。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-51）参考回水温度下的定热损耗](@id eq-ch03-051)

```math
H_{lk,t}^{R,loss}=\epsilon_{lk}L_{lk}(\tau_{lk,t}^{R,in}-\widehat\tau_t^{AM})\approx\epsilon_{lk}L_{lk}(\widehat\tau^{R,ref}-\widehat\tau_t^{AM})=\overline\epsilon_{lk,t}^{R}
\tag{3-51}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：作者近似；定损耗开关。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-52）温度有限差分原式](@id eq-ch03-052)

```math
(\overline\tau_{jk,t}^{S/R}-\overline\tau_{jk,t-1}^{S/R})+\frac{m_{jk,t}}{\rho_wA_{jk}}\frac{\tau_{jk,t}^{S/R,out}-\tau_{jk,t}^{S/R,in}}{L_{jk}}+\frac{\epsilon_{jk}}{\rho_wA_{jk}L_{jk}}(\overline\tau_{jk,t}^{S/R}-\widehat\tau_t^{AM})=0
\tag{3-52}
```

出处：PDF 51 / 正文 34；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 原式存在量纲/系数/双线性疑点；mc版采用单独记录的项目补全，不将其目标解释为原问题下界。

**疑点：R2-C05;Q10。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 envelopes and literal counterexamples ch03-042:052`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_bar](@ref sym-ch03-tau_bar)、[E](@ref sym-ch03-E)、[cp](@ref sym-ch03-cp)、[rho](@ref sym-ch03-rho)、[area](@ref sym-ch03-area)、[length](@ref sym-ch03-length)、[epsilon](@ref sym-ch03-epsilon)、[loss](@ref sym-ch03-loss)、[tau_ref](@ref sym-ch03-tau_ref)、[tau_ambient](@ref sym-ch03-tau_ambient)、[dt](@ref sym-ch03-dt)、[bounds](@ref sym-ch03-bounds)。

## [（3-53）管道最大注入流选择](@id eq-ch03-053)

```math
m_{jk,t}\le\overline m_{k,t}^S\le m_{jk,t}+(1-z_{jk,t}^{in})\overline M
\tag{3-53}
```

出处：PDF 52 / 正文 35；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 最大入流温度替代质量加权温度；同值最大流量允许多个选择，枚举/二进制分别对照。M按流量与温度各自有限边界计算。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[m_max](@ref sym-ch03-m_max)、[z](@ref sym-ch03-z)、[bigM](@ref sym-ch03-bigM)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)。

## [（3-54）本地最大注入流选择](@id eq-ch03-054)

```math
m_{k,t}\le\overline m_{k,t}^S\le m_{k,t}+(1-z_{k,t})\overline M
\tag{3-54}
```

出处：PDF 52 / 正文 35；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 最大入流温度替代质量加权温度；同值最大流量允许多个选择，枚举/二进制分别对照。M按流量与温度各自有限边界计算。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[m_max](@ref sym-ch03-m_max)、[z](@ref sym-ch03-z)、[bigM](@ref sym-ch03-bigM)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)。

## [（3-55）唯一主导来源](@id eq-ch03-055)

```math
\sum_{j:j\to k}z_{jk,t}^{in}+z_{k,t}=1
\tag{3-55}
```

出处：PDF 52 / 正文 35；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 最大入流温度替代质量加权温度；同值最大流量允许多个选择，枚举/二进制分别对照。M按流量与温度各自有限边界计算。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[m_max](@ref sym-ch03-m_max)、[z](@ref sym-ch03-z)、[bigM](@ref sym-ch03-bigM)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)。

## [（3-56）主导管道出口温度](@id eq-ch03-056)

```math
\tau_{jk,t}^{S,out}+(z_{jk,t}^{in}-1)\overline M\le\tau_{k,t}^{S,mix}\le\tau_{jk,t}^{S,out}+(1-z_{jk,t}^{in})\overline M
\tag{3-56}
```

出处：PDF 52 / 正文 35；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 最大入流温度替代质量加权温度；同值最大流量允许多个选择，枚举/二进制分别对照。M按流量与温度各自有限边界计算。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[m_max](@ref sym-ch03-m_max)、[z](@ref sym-ch03-z)、[bigM](@ref sym-ch03-bigM)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)。

## [（3-57）主导本地端口温度](@id eq-ch03-057)

```math
\tau_{k,t}^{S}+(z_{k,t}-1)\overline M\le\tau_{k,t}^{S,mix}\le\tau_{k,t}^{S}+(1-z_{k,t})\overline M
\tag{3-57}
```

出处：PDF 52 / 正文 35；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：项目补全版/适用特例中的约束或边界。 最大入流温度替代质量加权温度；同值最大流量允许多个选择，枚举/二进制分别对照。M按流量与温度各自有限边界计算。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[m_pipe](@ref sym-ch03-m_pipe)、[m_port](@ref sym-ch03-m_port)、[m_max](@ref sym-ch03-m_max)、[z](@ref sym-ch03-z)、[bigM](@ref sym-ch03-bigM)、[tau_pipe](@ref sym-ch03-tau_pipe)、[tau_mix](@ref sym-ch03-tau_mix)、[tau_port](@ref sym-ch03-tau_port)。
