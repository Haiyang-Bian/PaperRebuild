# 条件Benders：采用推导与符号

由benders.toml生成。PDF94–97为原算法出处；R5-BD为项目推导编号。

## R5-BD1

~~~math
Q_{s,b}(x)=\min_y c_s^\mathsf Ty,\qquad A_{s,b}y\ \bowtie\ b_{s,b}+B_sx,\quad y\in[\underline y_s,\overline y_s]
\tag{R5-BD1}
~~~

固定情景和舒适分支后为LP。日前承诺只进入交付、误差正负行及容量预算右端；补救目标不含日前常数。舒适分支不同的割不可无条件共享。

原式对应：5-87、5-88、5-89、5-90。API：[`build_r5_benders_subproblem`](@ref)，测试：`R5-BD finite input bounds and parameter rows`。

## R5-BD2

~~~math
L_s=\sum_k\min\{c_{sk}\underline y_{sk},c_{sk}\overline y_{sk}\},\quad \Delta P_t\in[\underline P_t^{DA}-\overline P^{PCC},\overline P_t^{DA}-\underline P^{PCC}],\quad 0\le e_t\le\delta\sum_\tau(R^u_\tau+R^d_\tau)^{\max}
\tag{R5-BD2}
~~~

输入有限盒给出允许负值的费用下界；等长时间步在逐时误差上界中相消。热量上界由比热、流量、供回温差推导，管出口温度由独立线性输运区间推导。实际实现对下界增加显式舍入余量，不读取优化结果选界。

原式对应：5-3、5-4、5-19、5-25、5-26。API：[`r5_benders_bounds`](@ref)，测试：`R5-BD finite input bounds and parameter rows`。

## R5-BD3

~~~math
F_{s,b}(x)=\min_{y,a}\sum_r\frac{a_r^++a_r^-}{M_r},\qquad A_ry+a_r^+-a_r^-\ \bowtie\ b_r+B_rx,\quad y\in[\underline y_s,\overline y_s]
\tag{R5-BD3}
~~~

项目phase-I放松全部非盒关系和所选舒适界，物理域盒保持硬约束。等式两向松弛，>=仅加正松弛，<=仅减负松弛。M由完整x/y盒推导并冻结，松弛也有有限上界。零诊断目标才对应原关系可行；与原5-96在z=0仍保持硬舒适的设置不同。

原式对应：5-94、5-95、5-96、5-97、5-98。API：[`build_r5_benders_subproblem`](@ref)，测试：`R5-BD elastic feasibility and hard physical boundary`。

## R5-BD4

~~~math
r=c-A^\mathsf T\lambda,\quad E=\sum_k|r_k|Y_k+\sum_r\lambda_r^{\mathrm{wrong}}V_r+E_{\mathrm{fp}},\qquad \ell(x)=\lambda^\mathsf T(b+Bx)-E
\tag{R5-BD4}
~~~

Y为变量绝对值盒界，V为全x/y盒上的约束松弛绝对界。>=要求lambda>=0，<=要求lambda<=0，等式自由。先通过未放宽的KKT，再扣除微小数值误差的界；原始乘子不裁剪。E_fp为1e-10乘以预先定义运算尺度，属浮点保护量，不是有理数/区间算术证书。

原式对应：5-91、5-92。API：[`r5_benders_cut`](@ref)，测试：`R5-BD signed multipliers and bounded numerical guards`。

## R5-BD5

~~~math
\theta_s\ge L_s,\qquad\theta_s\ge\ell_{s,b}(x)-M_{s,b}(1-\mathbf1\{z_s=b\}),\quad M_{s,b}=\max\{0,\max_{x\in X_{\mathrm{box}}}\ell_{s,b}(x)-L_s\}
\tag{R5-BD5}
~~~

成本条件割在匹配分支生效；不匹配时相对theta>=L冗余，负费用仍可行。有限盒对仿射函数求上界得到M；主问题只从通过独立检查的来源重建割。

原式对应：5-91、5-92。API：[`r5_benders_cut`](@ref)，测试：`R5-BD recourse KKT and conditional cuts`。

## R5-BD6

~~~math
\gamma_{s,b}(x)\le F_{s,b}(x),\qquad\gamma_{s,b}(x)\le M^F_{s,b}(1-\mathbf1\{z_s=b\}),\quad M^F_{s,b}=\max\{0,\max_{x\in X_{\mathrm{box}}}\gamma_{s,b}(x)\}
\tag{R5-BD6}
~~~

诊断的条件可行性割只排除其来源分支下不能零违反的点。来源点gamma<=1e-8时记为没有排除作用，不虚报迭代进展。该可行性割是项目实现选择；critical路线改为插入对应情景完整可行性关系，分别记录。

原式对应：5-94、5-99、5-100、5-101。API：[`r5_benders_cut`](@ref)，测试：`R5-BD elastic feasibility and hard physical boundary`。

## R5-BD7

~~~math
\min_{x,z,\theta,\lambda,\nu} c_0^\mathsf Tx+\rho\lambda_c+\sum_jp_j\nu^c_j,\quad \nu^c_j+\lambda_c d_{ij}\ge\theta_i,\quad \nu^r_j+\lambda_r d_{ij}\ge z_i,\quad \rho\lambda_r+\sum_jp_j\nu^r_j\le\epsilon,\quad \lambda_c,\lambda_r\ge0
\tag{R5-BD7}
~~~

完整有限支持运输对偶进入MILP主问题；费用和风险对手分别优化。与原5-85只用当前最坏权重的写法不同，属项目采用结构。theta以有效负费用下界和条件割约束，不将负净费用删掉。

原式对应：5-85、5-86、5-93。API：[`build_r5_benders_master`](@ref)，测试：`R5-BD master domains and full decomposition`。

## R5-BD8

~~~math
s\in C_k:\ A_sy_s\ \bowtie\ b_s+B_sx,\quad \underline T_s-(\underline T_s-\underline T_s^{phys})z_s\le T_s\le\overline T_s+(\overline T_s^{phys}-\overline T_s)z_s;\qquad \text{paper-critical only:}\ s\notin C_k\Rightarrow z_s=0
\tag{R5-BD8}
~~~

关键情景完整可行性关系与主问题辅助调度共同优化，费用仍由割约束。critical保留全部z，paper_critical实施5-102外集固定，后者域受限。关键集扩张后不能累计旧受限下界；外集为空才退化到完整域。

原式对应：5-99、5-100、5-101、5-102。API：[`build_r5_benders_master`](@ref)，测试：`R5-BD history scope persistence and failure propagation`。

## R5-BD9

~~~math
g=B^\mathsf T\lambda,\quad E_{coef}=\sum_k|g_k-\widehat g_k|X_k,\quad \widehat\ell(x)=\operatorname{round}_{-\infty}\!\left[\lambda^\mathsf Tb-E_{stat}-E_{sign}-E_{coef}\right]+\widehat g^\mathsf Tx
\tag{R5-BD9}
~~~

rational_box将已编码Float64系数和未裁剪的单位转换后乘子作为精确二进制有理数计算。驻点/符号及梯度转换误差在有限盒上扣除，截距向下舍入，停用M向上舍入。只认证编码LP的割，不继承物理模型、输入精度或整数求解的精确性保证；旧float_box仍保留。

原式对应：5-91、5-92。API：[`r5_benders_cut`](@ref)，测试：`R5-BD exact encoded cuts and equivalent scaling`。

## R5-BD10

~~~math
u=\sigma y,\quad Au\ \bowtie\ \sigma(b+Bx),\quad \min_u(c/\sigma)^\mathsf Tu,\qquad y=u/\sigma,\quad \lambda=\sigma\lambda_{solver},\qquad \sigma=2^{10}
\tag{R5-BD10}
~~~

诊断LP的等价二次幂表示。约束系数不变，右端及变量变大，目标系数相应缩小；不改变物理模型或验收阈值。分别保存求解器原始u/lambda_solver与还原量，检查变换一致。来源边界反例中原表示的微小负弹性量曾抵消正违反；缩放对照有单独记录，不修改原乘子制造通过。

原式对应：5-94、5-95、5-97、5-98。API：[`build_r5_benders_subproblem`](@ref)，测试：`R5-BD exact encoded cuts and equivalent scaling`。

## R5-BD11

~~~math
UB_k=\min_{i\le k:\,\mathrm{verified}}\{c_0^\mathsf Tx_i+\rho\lambda^c_i+\sum_jp_j\nu^c_{ij}\},\quad LB_k=\max_{i\le k:\,\mathrm{full\ domain}}LB_i^{master},\quad UB_k-LB_k\le10^{-7}+10^{-6}\max(1,|UB_k|,|LB_k|)
\tag{R5-BD11}
~~~

上界仅来自全情景模型/风险/费用通过的完整策略和费用运输对偶；下界保留有效来源/作用域。受限域只用当前主问题界与同域候选判断，不宣称完整域费用完成。费用A2相对间隙1e-4单列；失败、超时和无新割不等于不可行，最后失败保留旧最佳候选。

原式对应：5-85、5-93。API：[`validate_r5_benders`](@ref)，测试：`R5-BD history scope persistence and failure propagation`。

## 符号

| ID | 数学符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| r5-bd-commitment | ``x=(P^{DA},R^u,R^d)`` | 共同日前购电、上备用和下备用；按原有时段索引 | MW | `first_stage, P_DA_MW[t], R_up_MW[t], R_down_MW[t]` |
| r5-bd-branch | ``s,b,z_s`` | 情景、固定舒适分支、外层开关；b=0严格舒适，b=1物理域 | 1 | `scenario, branch, z[s]` |
| r5-bd-recourse | ``y,c,Q_{s,b},F_{s,b}`` | 补救变量、线性费用系数、补救净费用和归一化诊断值 | y按变量；Q: USD；F: 1 | `flat_values, system.cost, solver_objective, objective_type` |
| r5-bd-dual | ``\lambda,r,B^\mathsf T\lambda`` | 原始约束乘子、驻点残差与固定分支次梯度 | 成本: USD/行单位，USD/变量单位；诊断: 1/行单位 | `solver_raw_duals, raw_duals (original units), stationarity_raw, gradient` |
| r5-bd-master | ``\theta_s,\lambda_c,\lambda_r,\nu_j^c,\nu_j^r,C_k,LB,UB`` | 情景费用上图、费用/风险运输对偶、关键集与数值上下界 | theta,LB,UB: USD；risk:1；lambda随距离尺度 | `theta, embedded_duals, critical, lower_bound, upper_bound` |
| r5-bd-scale | ``\sigma,u,\lambda_{solver}`` | 诊断数值表示比例、求解器变量和原始乘子；不同于作者未定的停止sigma | sigma:1；u为原单位乘表示比例；lambda_solver为目标/表示后行单位 | `diagnostic_scale, numerical_scale, solver_raw_values, solver_raw_duals` |
| r5-bd-box | ``\underline y,\overline y,Y,V,L`` | 有效物理盒、变量绝对界、行违反界、净费用下界 | 随变量/行；L: USD | `r5_benders_bounds, box, lower_cost` |
| r5-bd-guard | ``E,M,M^F`` | 浮点割保护量、成本与诊断停用常数；不改变原始KKT阈值 | 成本: USD；诊断: 1 | `guard, stationarity_guard, sign_guard, rounding_guard, deactivation_M` |

## 采用边界

- **R5-BD-C01：**原5-91/92停用到零要求另有非负补救费用假设；当前实时收入允许负费用。由显式盒推导负下界后生成条件割；项目合成负费用测试不证明作者原输入也为负。
- **R5-BD-C02：**每个情景独立求补救并读取条件LP原始对偶，完全不除以最坏分布权重。零权重不免除物理或条件最优性检查；费用和风险对手仍须分开。
- **R5-BD-C03：**原5-96在z=0时没有舒适松弛，诊断未必总可行。项目phase-I显式按物理盒放松所有非盒关系及舒适界，诊断尺度和范围不同于原式；排序影响待关键情景实验，不能叫笔误修正。
- **R5-BD-C04：**原5-102把关键集之外z固定为0，限制舒适策略域。paper_critical的界只属于该域；关键集扩张后不累计旧受限下界。开发手算中受限路线与完整路线恰巧费用相同，仍只记录restricted_domain_gap，不当完整域证明。正式算法批次待冻结。
- **R5-BD-C05：**原算法页只称sigma足够小，未给具体数值。项目外层最多200轮、绝对1e-7/相对1e-6，共享600秒；KKT1e-6、A1/A2不放宽。旧float_box保护不是严格有理证明，新增rational_box只对编码LP的割做有理运算；不得混成整个算法精确认证。
- **R5-BD-C06：**纯割开发反例先受float_box约2.69e-7保护量影响；改有理算术后仍在约1.30e-9 MW处停滞。原phase-I负松弛约-3.3e-10抵消正电平衡违反，不能由近零目标认定可行。预声明1024倍等价表示解除该手算反例；保留旧记录，不普遍宣称数值问题消失。
