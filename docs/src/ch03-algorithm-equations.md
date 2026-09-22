# [第3章算法公式](@id ch03-algorithm-equations)

<!-- GENERATED: scripts/ch03_docs.jl -->

[设备、电网与水力](@ref ch03-equations) · [符号表](@ref ch03-symbols)。

## [（3-58）WMM抽象优化问题](@id eq-ch03-058)

```math
\min c(\mathbf x)\quad\mathrm{s.t.}\ f(\mathbf x,\mathbf m,\boldsymbol\theta)=0,\quad g_1(\mathbf x)=\mathbf a_1^\mathsf T\mathbf x+\mathbf b_1\le0,\quad g_2(\mathbf m)=\mathbf a_2^\mathsf T\mathbf m+\mathbf b_2\le0,\quad r(\mathbf m,\mathbf x)\le0
\tag{3-58}
```

出处：PDF 52 / 正文 35；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。抽象表述已说明；原文f/g/r分类不能代替逐项模型核查，采用模型见R2/R3解释。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-59）含割平面的主问题](@id eq-ch03-059)

```math
\min c(\mathbf x)\quad\mathrm{s.t.}\ g_1(\mathbf x)\le0,\ g_2(\mathbf m)\le0,\ r(\mathbf m,\mathbf x)\le0,\quad h(\mathbf m,\mathbf x^K)=(\mathbf c^K)^\mathsf T\mathbf x+\mathbf d^K\le0,\ K=1,\ldots,N_K
\tag{3-59}
```

出处：PDF 53 / 正文 36；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。原式h标记含m，展开式却写x。已实现凸投影外松弛域；不实现未经证明的累计全局割主问题。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-60）固定流量和时延的子问题](@id eq-ch03-060)

```math
\min c(\mathbf x)\quad\mathrm{s.t.}\ f(\mathbf x,\mathbf m^K,\boldsymbol\theta^K)=0,\quad g_1(\mathbf x)=\mathbf a_1^\mathsf T\mathbf x+\mathbf b_1\le0,\quad r(\mathbf m^K,\mathbf x)\le0
\tag{3-60}
```

出处：PDF 53 / 正文 36；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：固定流量下的已核查WMM特例；时延由流量和历史计算，保留电网及水力锥松弛。 PDF52–55算法抽象；固定流量SP与项目弹性诊断可运行。直接修正和核查版投影梯度分别记录，不将局部半空间当全局有效割。

实现入口：[`build_r3_subproblem`](@ref)；源码 `src/formulations/r3.jl`；测试 `R3 fixed schedule and reconstruction ch03-060`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-61）拉格朗日灵敏度与时延链式项](@id eq-ch03-061)

```math
\left.\frac{\partial c(\mathbf x)}{\partial\mathbf m}\right|_{\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K}=\frac{\partial L^{Opt}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}=(\boldsymbol\lambda^K)^\mathsf T\left\{\frac{\partial f}{\partial\mathbf m}+\frac{\partial f}{\partial\boldsymbol\theta}\frac{\partial\boldsymbol\theta}{\partial\mathbf m}\right\}
\tag{3-61}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：采用解释补全流量相关不等式、固定变量与数值热系数贡献；不是原式逐字实现。 采用式补足全部流量相关项；仅连续凸子问题可信对偶，WMM分段导数与有限差分对照。

实现入口：[`r3_value_sensitivity`](@ref)；源码 `src/algorithms/r3_sensitivity.jl`；测试 `R3 dual signs and complete value sensitivity`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)。

## [（3-62）成本分支梯度步](@id eq-ch03-062)

```math
\mathbf m^{K+1,*}=\mathbf m^K-\gamma^K\frac{\partial L^{Opt}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}
\tag{3-62}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：归一化成本梯度及Armijo回溯为项目数值规则。 r3_pg_checked_v1；尺度、回溯、单侧试探和停止条件为项目补全，不继承参考文献的全局收敛证明。

实现入口：[`solve_r3_projected_gradient`](@ref)；源码 `src/algorithms/r3_pg.jl`；测试 `R3 convex projection and outer trace`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-63）成本分支投影](@id eq-ch03-063)

```math
\mathbf m^{K+1}=\arg\min_{\mathbf m}\left\{\|\mathbf m^{K+1,*}-\mathbf m\|_2^2:(\mathbf m,\mathbf x)\in D_{MP}\right\}
\tag{3-63}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：存在辅助调度变量的凸投影；距离尺度是项目约定。 主问题采用凸外松弛域，辅助调度变量共同优化；项目使用流量跨度归一化距离，原式为未缩放距离。

实现入口：[`build_r3_projection`](@ref)；源码 `src/algorithms/r3_projection.jl`；测试 `R3 convex projection and outer trace`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-64）原文可行性割](@id eq-ch03-064)

```math
(\boldsymbol\lambda^K)^\mathsf T\left[\frac{\partial L^{Feasi}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}(\mathbf m-\mathbf m^K)\right]+(\boldsymbol\mu^K)^\mathsf T g_2(\mathbf x^K)\le0
\tag{3-64}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。原页g2(xK)和lambda重复乘法疑点保留；项目只用诊断值一阶局部试探半空间，经实际求解接受或丢弃，不作为全局有效割。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-65）可行性分支梯度步](@id eq-ch03-065)

```math
\mathbf m^{K+1,*}=\mathbf m^K-\gamma^K\frac{\partial L^{Feasi}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}
\tag{3-65}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：冻结尺度的弹性诊断梯度；实际诊断目标下降才接受。 r3_pg_checked_v1；尺度、回溯、单侧试探和停止条件为项目补全，不继承参考文献的全局收敛证明。

实现入口：[`solve_r3_projected_gradient`](@ref)；源码 `src/algorithms/r3_pg.jl`；测试 `R3 convex projection and outer trace`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-66）可行性分支投影](@id eq-ch03-066)

```math
\mathbf m^{K+1}=\arg\min_{\mathbf m}\left\{\|\mathbf m^{K+1,*}-\mathbf m\|_2^2:(\mathbf m,\mathbf x)\in D_{MP}\right\}
\tag{3-66}
```

出处：PDF 55 / 正文 38；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：可行性分支投影与单次局部半空间试探，不跨轮累积未证明的割。 主问题采用凸外松弛域，辅助调度变量共同优化；项目使用流量跨度归一化距离，原式为未缩放距离。

实现入口：[`build_r3_projection`](@ref)；源码 `src/algorithms/r3_projection.jl`；测试 `R3 convex projection and outer trace`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-67）CF-VT固定预设流量](@id eq-ch03-067)

```math
m_{jk,t}=\hat m_{jk,t},\quad(j,k)\in\mathcal C,\ t\in\mathcal T
\tag{3-67}
```

出处：PDF 58 / 正文 41；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：采用预先冻结的恒定流量作为预设计划特例，原文前置优化另行说明。 PDF58四模式原定义；项目冻结恒定参考流量，只固定热源供水端口温度。新输入使用有界负荷回水和共同恢复尾段。

实现入口：[`R3OperationSpec`](@ref)；源码 `src/core/r3_operation.jl`；测试 `R3 four operation modes and local candidate`。

符号：[indices](@ref sym-ch03-indices)、[alg_m](@ref sym-ch03-alg_m)、[bounds](@ref sym-ch03-bounds)、[mode_flow](@ref sym-ch03-mode_flow)、[mode_temperature](@ref sym-ch03-mode_temperature)。

## [（3-68）VF-CT固定热源供水温度](@id eq-ch03-068)

```math
\tau^S_{k,t}=\hat\tau^S_{k,t},\quad k\in\mathcal J^S,\ t\in\mathcal T
\tag{3-68}
```

出处：PDF 58 / 正文 41；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：CT只固定热源供水端口，管道和负荷温度仍有动态。 PDF58四模式原定义；项目冻结恒定参考流量，只固定热源供水端口温度。新输入使用有界负荷回水和共同恢复尾段。

实现入口：[`R3OperationSpec`](@ref)；源码 `src/core/r3_operation.jl`；测试 `R3 four operation modes and local candidate`。

符号：[indices](@ref sym-ch03-indices)、[alg_m](@ref sym-ch03-alg_m)、[bounds](@ref sym-ch03-bounds)、[mode_flow](@ref sym-ch03-mode_flow)、[mode_temperature](@ref sym-ch03-mode_temperature)。

## [（3-69）CF-CT同时固定流量及热源供水温度](@id eq-ch03-069)

```math
\begin{cases}m_{jk,t}=\hat m_{jk,t},\\ \tau^S_{k,t}=\hat\tau^S_{k,t}.\end{cases}
\tag{3-69}
```

出处：PDF 58 / 正文 41；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：四模式共用物理边界与恢复尾段；更自由模式含受限模式可行解。 PDF58四模式原定义；项目冻结恒定参考流量，只固定热源供水端口温度。新输入使用有界负荷回水和共同恢复尾段。

实现入口：[`R3OperationSpec`](@ref)；源码 `src/core/r3_operation.jl`；测试 `R3 four operation modes and local candidate`。

符号：[indices](@ref sym-ch03-indices)、[alg_m](@ref sym-ch03-alg_m)、[bounds](@ref sym-ch03-bounds)、[mode_flow](@ref sym-ch03-mode_flow)、[mode_temperature](@ref sym-ch03-mode_temperature)。
