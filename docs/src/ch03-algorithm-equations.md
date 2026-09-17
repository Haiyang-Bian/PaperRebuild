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

实现状态：已说明、未实现。主问题与割平面留后续；原式h标记含m，展开式却写x，未静默替换。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-60）固定流量和时延的子问题](@id eq-ch03-060)

```math
\min c(\mathbf x)\quad\mathrm{s.t.}\ f(\mathbf x,\mathbf m^K,\boldsymbol\theta^K)=0,\quad g_1(\mathbf x)=\mathbf a_1^\mathsf T\mathbf x+\mathbf b_1\le0,\quad r(\mathbf m^K,\mathbf x)\le0
\tag{3-60}
```

出处：PDF 53 / 正文 36；状态：原页视觉核读；采用解释和实现状态另列。

本批作用：固定流量下的已核查WMM特例；时延由流量和历史计算，保留电网及水力锥松弛。 PDF52–55算法抽象；本批固定流量SP可运行，弹性诊断和直接修正的细节由项目单独定义。MP、梯度及投影未实现。

实现入口：[`build_r3_subproblem`](@ref)；源码 `src/formulations/r3.jl`；测试 `R3 fixed schedule and reconstruction ch03-060`。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-61）拉格朗日灵敏度与时延链式项](@id eq-ch03-061)

```math
\left.\frac{\partial c(\mathbf x)}{\partial\mathbf m}\right|_{\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K}=\frac{\partial L^{Opt}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}=(\boldsymbol\lambda^K)^\mathsf T\left\{\frac{\partial f}{\partial\mathbf m}+\frac{\partial f}{\partial\boldsymbol\theta}\frac{\partial\boldsymbol\theta}{\partial\mathbf m}\right\}
\tag{3-61}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。需另核r对m的贡献、时延分段边界及对偶适用条件；本批不计算梯度。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-62）成本分支梯度步](@id eq-ch03-062)

```math
\mathbf m^{K+1,*}=\mathbf m^K-\gamma^K\frac{\partial L^{Opt}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}
\tag{3-62}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。成本下降分支不在本批。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-63）成本分支投影](@id eq-ch03-063)

```math
\mathbf m^{K+1}=\arg\min_{\mathbf m}\left\{\|\mathbf m^{K+1,*}-\mathbf m\|_2^2:(\mathbf m,\mathbf x)\in D_{MP}\right\}
\tag{3-63}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。后续应明确对x的存在量词、可行域与历史割；本批直接修正不等于该投影。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-64）原文可行性割](@id eq-ch03-064)

```math
(\boldsymbol\lambda^K)^\mathsf T\left[\frac{\partial L^{Feasi}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}(\mathbf m-\mathbf m^K)\right]+(\boldsymbol\mu^K)^\mathsf T g_2(\mathbf x^K)\le0
\tag{3-64}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。原页写g2(xK)，与3-58的g2(m)不一致；lambda重复乘法和割有效性也需推导。本批不使用该割。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-65）可行性分支梯度步](@id eq-ch03-065)

```math
\mathbf m^{K+1,*}=\mathbf m^K-\gamma^K\frac{\partial L^{Feasi}(\mathbf m^K,\mathbf x^K,\boldsymbol\theta^K)}{\partial\mathbf m}
\tag{3-65}
```

出处：PDF 54 / 正文 37；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。本批实现有明确名称的详细模型直接修正，不称作者该更新式已实现。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。

## [（3-66）可行性分支投影](@id eq-ch03-066)

```math
\mathbf m^{K+1}=\arg\min_{\mathbf m}\left\{\|\mathbf m^{K+1,*}-\mathbf m\|_2^2:(\mathbf m,\mathbf x)\in D_{MP}\right\}
\tag{3-66}
```

出处：PDF 55 / 正文 38；状态：原页视觉核读；采用解释和实现状态另列。

实现状态：已说明、未实现。梯度与投影外层留后续，当前只提供可行性基准。

符号：[alg_x](@ref sym-ch03-alg_x)、[alg_m](@ref sym-ch03-alg_m)、[alg_theta](@ref sym-ch03-alg_theta)、[alg_s](@ref sym-ch03-alg_s)、[alg_lambda](@ref sym-ch03-alg_lambda)、[alg_mu](@ref sym-ch03-alg_mu)、[alg_gamma](@ref sym-ch03-alg_gamma)。
