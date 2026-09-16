# [第3章公式与符号索引](@id ch03-equations)

<!-- GENERATED: scripts/ch03_docs.jl; edit docs/reading/ch03/formulas.toml and symbols.toml. -->

本页为原式规范化转录，不是修正后的模型。疑点、角色边界与补全式见[模型解释](@ref ch03-models)。

索引分页：[热网与简化式](@ref ch03-heat-equations) · [符号表](@ref ch03-symbols)。

## [（3-1）运行成本目标](@id eq-ch03-001)

```math
\min_{\Xi}\sum_t\left(\lambda_t^{Grid}P_t^{Grid}+\sum_g c_g^{PV}P_{g,t}^{PV}+\sum_g c_g^{CHP}P_{g,t}^{CHP}+\sum_g c_g^{GT}P_{g,t}^{GT}\right)
\tag{3-1}
```

出处：PDF 46 / 正文 29；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

**疑点：R2-C04。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-2）CHP常热电比](@id eq-ch03-002)

```math
H_{g,t}^{CHP}=\eta_g^{CHP}P_{g,t}^{CHP}
\tag{3-2}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-3）CHP电功率界](@id eq-ch03-003)

```math
\underline P_g^{CHP}\le P_{g,t}^{CHP}\le\overline P_g^{CHP}
\tag{3-3}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-4）CHP热功率界](@id eq-ch03-004)

```math
\underline H_g^{CHP}\le H_{g,t}^{CHP}\le\overline H_g^{CHP}
\tag{3-4}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目特例：热界由电界和固定热电比导出，非独立热界的一般实现。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-5）燃气轮机电功率界](@id eq-ch03-005)

```math
\underline P_g^{GT}\le P_{g,t}^{GT}\le\overline P_g^{GT}
\tag{3-5}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-6）光伏可用出力上界](@id eq-ch03-006)

```math
0\le P_{g,t}^{PV}\le\overline P_{g,t}^{PV}
\tag{3-6}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-7）电热转换](@id eq-ch03-007)

```math
H_{g,t}^{EB}=P_{g,t}^{EB}COP_g^{EB}
\tag{3-7}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-8）电热设备耗电界](@id eq-ch03-008)

```math
0\le P_{g,t}^{EB}\le\overline P_g^{EB}
\tag{3-8}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 合成案例采用常热电比/常COP、设备单位功率因数、显式购电边界；空GT集合允许。MW×h计费。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_device](@ref sym-ch03-P_device)、[H_device](@ref sym-ch03-H_device)、[P_grid](@ref sym-ch03-P_grid)、[cost](@ref sym-ch03-cost)、[ratio](@ref sym-ch03-ratio)、[bounds](@ref sym-ch03-bounds)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)。

## [（3-9）节点有功平衡](@id eq-ch03-009)

```math
P_{n,t}^{net}=\sum_{b\in\Theta(n)}P_{nb,t}-(P_{mn,t}-r_{mn}\ell_{mn,t})
\tag{3-9}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-10）节点无功平衡](@id eq-ch03-010)

```math
Q_{n,t}^{net}=\sum_{b\in\Theta(n)}Q_{nb,t}-(Q_{mn,t}-x_{mn}\ell_{mn,t})
\tag{3-10}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-11）支路电压降](@id eq-ch03-011)

```math
v_{n,t}=v_{m,t}-2(r_{mn}P_{mn,t}+x_{mn}Q_{mn,t})+(r_{mn}^2+x_{mn}^2)\ell_{mn,t}
\tag{3-11}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-12）原电流关系的二阶锥松弛](@id eq-ch03-012)

```math
\left\|\begin{matrix}2P_{mn,t}\\2Q_{mn,t}\\\ell_{mn,t}-v_{m,t}\end{matrix}\right\|_2\le\ell_{mn,t}+v_{m,t}
\tag{3-12}
```

出处：PDF 47 / 正文 30；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：作者松弛；原等式独立回代。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-13）电压平方界](@id eq-ch03-013)

```math
\underline v_n\le v_{n,t}\le\overline v_n
\tag{3-13}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-14）电流平方界](@id eq-ch03-014)

```math
\underline\ell_{mn}\le\ell_{mn,t}\le\overline\ell_{mn}
\tag{3-14}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-15）有功净注入组成](@id eq-ch03-015)

```math
P_{n,t}^{net}=\sum_gP_{g,t}^{GT}+\sum_gP_{g,t}^{CHP}+\sum_gP_{g,t}^{PV}-\sum_gP_{g,t}^{EB}-P_{n,t}^{D}
\tag{3-15}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-16）无功净注入组成](@id eq-ch03-016)

```math
Q_{n,t}^{net}=\sum_gQ_{g,t}^{GT}+\sum_gQ_{g,t}^{CHP}-Q_{n,t}^{D}
\tag{3-16}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：本批设备无功固定0，根节点提供无功；一般机组无功能力曲线未实现。 固定有向径向树；根电压1pu；保留3-12锥松弛，原支路等式独立回代。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[P_branch](@ref sym-ch03-P_branch)、[Q_branch](@ref sym-ch03-Q_branch)、[v](@ref sym-ch03-v)、[ell](@ref sym-ch03-ell)、[impedance](@ref sym-ch03-impedance)、[P_device](@ref sym-ch03-P_device)、[P_demand](@ref sym-ch03-P_demand)、[Q_demand](@ref sym-ch03-Q_demand)、[P_net](@ref sym-ch03-P_net)、[Q_net](@ref sym-ch03-Q_net)、[bounds](@ref sym-ch03-bounds)。

## [（3-17）节点换热功率](@id eq-ch03-017)

```math
H_{j,t}^{net}=c_wm_{j,t}\Delta\tau_{j,t}
\tag{3-17}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

**疑点：R2-C01。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-18）供回水温差](@id eq-ch03-018)

```math
\Delta\tau_{j,t}=\tau_{j,t}^{S}-\tau_{j,t}^{R}
\tag{3-18}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-19）热源注入](@id eq-ch03-019)

```math
H_{j,t}^{net}=\sum_gH_{g,t}^{CHP}+\sum_gH_{g,t}^{EB},\quad j\in\mathcal J^G
\tag{3-19}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-20）热负荷负注入](@id eq-ch03-020)

```math
H_{j,t}^{net}=-H_{j,t}^{D},\quad j\in\mathcal J^D
\tag{3-20}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-21）水流连续性](@id eq-ch03-021)

```math
m_{k,t}=\sum_{j:j\to k}m_{jk,t}-\sum_{l:k\to l}m_{kl,t}
\tag{3-21}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

**疑点：R2-C01。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-22）水压降下界](@id eq-ch03-022)

```math
\Phi_{j,t}^{S/R}-\Phi_{k,t}^{S/R}\ge\kappa_{ij,t}
\tag{3-22}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：原式右端出现ij下标；项目按当前jk管段及供回方向解释。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

**疑点：R2-C01。**

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-23）非负流量与压力损耗](@id eq-ch03-023)

```math
m_{jk,t}\ge0,\quad\kappa_{jk,t}\ge0
\tag{3-23}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：本批为有正下界的子域，不支持原式允许的停流。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-24）供回水压排序及界](@id eq-ch03-024)

```math
\underline\Phi_j\le\Phi_{j,t}^{R}\le\Phi_{j,t}^{S}\le\overline\Phi_j
\tag{3-24}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：项目补全版/适用特例中的约束或边界。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-25）摩擦压力损耗原等式](@id eq-ch03-025)

```math
\kappa_{jk,t}=\mu_{jk}(m_{jk,t})^2
\tag{3-25}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：只用于原关系回代；优化约束采用3-26。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。

## [（3-26）水压损耗锥松弛](@id eq-ch03-026)

```math
\left\|\begin{matrix}2\sqrt{\mu_{jk}}m_{jk,t}\\\kappa_{jk,t}-1\end{matrix}\right\|_2\le\kappa_{jk,t}+1
\tag{3-26}
```

出处：PDF 48 / 正文 31；状态：原页视觉核读，原式literal仍受版本级阻断。

本批作用：作者松弛；归一化压力用于A1。 首批管内严格正向；端口用正幅值和source/load角色补全原式方向；3-25仅回代，构建使用3-26。

实现入口：[`build_r2_model`](@ref)；源码 `src/formulations/r2.jl`；测试 `R2 saved integration ch03-001:057`。

符号：[indices](@ref sym-ch03-indices)、[H_net](@ref sym-ch03-H_net)、[m_port](@ref sym-ch03-m_port)、[m_pipe](@ref sym-ch03-m_pipe)、[delta_tau](@ref sym-ch03-delta_tau)、[tau_port](@ref sym-ch03-tau_port)、[cp](@ref sym-ch03-cp)、[Phi](@ref sym-ch03-Phi)、[kappa](@ref sym-ch03-kappa)、[mu](@ref sym-ch03-mu)、[bounds](@ref sym-ch03-bounds)、[H_device](@ref sym-ch03-H_device)、[H_demand](@ref sym-ch03-H_demand)。
