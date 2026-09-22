# 补救对偶：项目推导与符号

此页由recourse-duality.toml生成；编号R5-DK属于项目推导，不能冒用论文式号。

## R5-DK1

~~~math
\min_w c^\mathsf{T}w+c_0(x),\quad A_=w=b_=(x),\ A_+w\ge b_+(x),\ A_-w\le b_-(x).
\tag{R5-DK1}
~~~

独立按物理关联重建系数，全部变量界作为独立行；x为给定日前成交。

API：[`build_r5_dispatch_dual`](@ref)，测试：`R5 recourse independent coefficient inventory`。

## R5-DK2

~~~math
\max_y c_0(x)+b(x)^\mathsf{T}y,\quad A^\mathsf{T}y=c,\quad y_+\ge0,\ y_-\le0,\ y_=\ \mathrm{free}.
\tag{R5-DK2}
~~~

MOI原始乘子不换符号；固定变量仍保留上下界两项。

API：[`validate_r5_dispatch_duals`](@ref)，测试：`R5 recourse KKT and independent dual`。

## R5-DK3

~~~math
g_x=\nabla_x c_0(x)+[\nabla_x b(x)]^\mathsf{T}y^*.
\tag{R5-DK3}
~~~

连续LP的固定分支次梯度；非光滑点只给支撑方向，不强求唯一导数。

API：[`r5_dispatch_sensitivity`](@ref)，测试：`R5 recourse sensitivity analytic and finite differences`。

## R5-DK4

~~~math
g^{DA}_t=y^D_t,\quad g^{up}_t=\alpha^{up}_t(y^+_t-y^-_t)+\delta\Delta t y^B,\quad g^{down}_t=-\alpha^{down}_t(y^+_t-y^-_t)+\delta\Delta t y^B.
\tag{R5-DK4}
~~~

扣除日前常数的补救费用对三个成交量的次梯度，保持其他输入与舒适分支不变。

API：[`r5_dispatch_sensitivity`](@ref)，测试：`R5 recourse sensitivity analytic and finite differences`。

## R5-DK5

~~~math
(g^{DA},g^{up},g^{down})=(100-130,-5+0.4(130-80),-2-0.2(130-80))=(-30,15,-12).
\tag{R5-DK5}
~~~

合成光滑解析例的一小时总费用梯度，非作者参数。

API：[`r5_dispatch_sensitivity`](@ref)，测试：`R5 recourse sensitivity analytic and finite differences`。

## 符号

| ID | 数学符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| R5-DK-x | ``x=(P^{DA},R^{up},R^{down})`` | 给定的日前购能和上下备用，非本批优化变量 | MW | `P_DA_MW; R_up_MW; R_down_MW` |
| R5-DK-w | ``w`` | IES物理调度和误差上图变量按稳定ID排列 | MW/Mvar/K/pu，逐变量保留 | `r5_dispatch_dual_system.cost keys` |
| R5-DK-y | ``y_+,y_-,y_=`` | 原始MOI乘子，符号由行方向决定 | USD/(对应行单位) | `raw_constraint_duals; raw_bound_duals` |
| R5-DK-g | ``g_x`` | 包含或扣除固定日前费用的LP次梯度 | USD/MW（已含dt） | `gradient` |

## 采用边界

- **R5-DK-C01：**KKT按独立输入尺度检查，原始乘子不裁剪不调整。数值认证不等于精确算术证明。
- **R5-DK-C02：**备用参数同时进入误差双行与5-4右端；灵敏度不得遗漏容量预算贡献。
- **R5-DK-C03：**固定日前常数可能掩盖相对差，同时验收总目标与扣除常数后补救目标的原对偶差。
- **R5-DK-C04：**当前硬舒适分支没有z开关；未来改变舒适分支、价格或物理输入时不能直接复用该次梯度。
