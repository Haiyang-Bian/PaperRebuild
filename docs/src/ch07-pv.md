# R9：44电节点、38热节点的24小时固定模式基准

本批把[第7章已核实的连接和设备](ch07-inputs.md)接入现有WMM调度，实现CF-CT与CF-VT。
**输入含明确声明的合成替代值，不是作者同输入复现。** 两种模式使用同一24小时负荷、初始热历史和终端条件。
VF-CT、VF-VT及算法规模对照仍待接入；不会用固定流量结果冒充四模式全部完成。

## 1. 哪些数字来自论文？

| 类别 | 本批处理 |
|---|---|
| 44/38节点、边和设备位置 | 原图7-2；电源原44号映射为内部1号，双向映射保存 |
| 45.67 MVA、7.23 MW峰值 | 保留原额定总量；节点分配和小时比例是项目规则 |
| CHP、两台电锅炉、三台PV及成本 | 保留表7-1至7-4；7.2的PV1增为6 MW；电锅炉电容量为热容量除效率 |
| 有功/无功与小时负荷 | 合成功率因数0.9；非根43个电节点均分，36个非热源节点均分热负荷 |
| 线路和变压器 | 合成压降预算给定阻抗；110/10 kV和220/110 kV使用明确理想额定变比等值 |
| 管道与温度 | 合成管长600 m、参考速度1 m/s、SI物性/绝热层与固定摩阻系数 |
| 初末热状态 | 优化前解析计算CF-CT周期参考，冻结初始入口历史；末端恢复相同离散记忆 |

权威参数与逐字段来源是 `configs/r9/pv-protocol.toml`，采用式与符号见
`docs/reading/ch07/pv-adoption.toml`。冻结目录另外保存原始来源台账、完整输入及实际求解源码。
原文结果表不参与输入构造，不据作者费用或弃光率反推阻抗、负荷或温度。

CHP按式（3-1）的连续出力模型始终满足原最小出力，费用为燃料及购电/PV变动成本。
表7-2列有启动费，但尚不能据此断言7.2目标包含启停；本批未增添二元启停或启动费。
所有金额为CNY，不能与前章合成USD案例直接相减。

## 2. 电网等值与管道设计

将视在峰值拆成有功和无功：

```math
P=S\cos\varphi,\qquad Q=S\sqrt{1-\cos^2\varphi}.
\tag{R9-P1}
```

项目按每条根到节点路径的平方电压降预算0.04分配阻抗，取X/R=0.5。
用于设计的功率包络把下游负荷与设备额定值取绝对值相加，不使用优化后的潮流。
该规则是可追踪的合成线路设计，不能当作真实线路识别。

```math
r_{\mathrm{pu}}=\frac{R_\Omega S_{\mathrm{base}}}{V_{\mathrm{base}}^2},\qquad
R_{10}=R_V\left(\frac{10}{V}\right)^2.
\tag{R9-P2}
```

原高压馈线的110 kV阻抗和折算10 kV阻抗分别保存，二者有相同标幺值。
变压器采用无损、无限容量、无可调分接头的项目近似；没有把原44号220 kV地点当成真实10 kV母线。
支路原等式、SOCP和电压/电流边界仍分别检查。

热管截面积由参考流量与速度确定。圆筒绝热层积分导热、固定Darcy系数分别给出：

```math
A_p=\frac{m_p^0}{\rho u},\quad D_p=\sqrt{4A_p/\pi},\quad
\epsilon_p=\frac{2\pi k}{\ln[(D_p+2b)/D_p]},\quad
\mu_p=\frac{fL_p}{2000\rho D_pA_p^2}.
\tag{R9-P3}
```

这里 ``k`` 为绝热材料导热系数，``b`` 为厚度，``f`` 为给定Darcy摩阻系数。
``\epsilon`` 单位W/(m K)，``\mu`` 单位kPa s²/kg²；分母2000包含动压系数2与Pa转kPa的1000。
忽略外表面对流热阻、温度相关物性和变摩阻，是项目假设。

## 3. 为什么使用冻结的周期参考？

CF-CT参考源温为363.15 K（90℃）。参考流量按0.8倍热峰值和40 K温差构造；H15注入
部分流量，剩余由H1供应。输入检查拒绝负管流及超容量方案，不自动改参。

```math
H_{j,t}=10^{-6}c_pm_j(T^S_{j,t}-T^R_{j,t}).
\tag{R9-P4}
```

供水先沿树向下计算，负荷按上式求回温，再沿回水树向上混合。
固定流量的WMM系数已经确定，对24小时序列使用循环下标：

```math
T^{out}_{p,t}=T^a+
\left(\sum_s w_{p,s}T^{in}_{p,\operatorname{mod1}(t-s,N)}-T^a\right)
\exp\left(-\frac{\epsilon_pL_p}{c_pm_p^0}\right).
\tag{R9-P5}
```

这一步只计算预定CF-CT工况，不最小化费用。它提供一个日周期热参考，随后所有模式的初始历史均固定，
优化器不能额外选择免费初始热量。日周期参考也不冒称全天恒定的稳态工况。

## 4. 末端怎样检查？

只约束总库存相等可能掩盖管内温度分布变化。本批恢复足够长的入口记忆：

```math
L_p^h=\left\lceil\frac{M_p}{m_p^{min}\Delta t_s}\right\rceil,\qquad
T^{in}_{p,N-s}=T^{hist}_{p,-s},\quad s=0,\ldots,L_p^h-1.
\tag{R9-P6}
```

供回水两侧分别约束；CF的末段流量本来就等于历史参考。当前参数中每管保守记忆为一个时间步，
额外历史用于完整WMM权重计算。周期通过的含义是**采用WMM离散模型在重复日输入下可接续**；
不自动认证连续网络PDE、瞬时节点混合或任意变流量模型。
后续VF必须同时保存末段流量记忆，并将新增终端条件接入灵敏度，不能直接套用旧PG。

## 5. Julia操作与验收

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_pv.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_pv_evidence.jl
julia +1.12.6 --startup-file=no --project=. scripts/r9_pv_study.jl freeze results/runs/NEW_BATCH
julia +1.12.6 --startup-file=no --project=. scripts/r9_pv_study.jl run results/runs/NEW_BATCH Clarabel
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/run_r9_gurobi.jl results/runs/NEW_BATCH
julia +1.12.6 --startup-file=no --project=. scripts/r9_pv_study.jl report results/runs/NEW_BATCH results/runs/NEW_REPORT
```

目录必须是新的。六项运行在优化前冻结：两种模式各包含Clarabel SOCP、Gurobi SOCP、Gurobi原电网等式。
每项共享600秒，其中10%预留独立验证；未取得候选、超时和失败原样保留。
报告按冻结源码重读原值，不重新优化；温度、功率和无量纲A1门槛沿用原规定。
κ重构只修改有理论依据的辅助量，原始值与重构值分别保存。

```@index
Pages = ["ch07-pv.md"]
```

```@docs
r9_pv_case
load_r9_pv_case
audit_r9_pv_input
build_r9_pv_model
solve_r9_pv_case
validate_r9_pv_solution
```
