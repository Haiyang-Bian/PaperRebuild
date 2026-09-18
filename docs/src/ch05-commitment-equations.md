# 共同承诺：项目推导与符号

由commitment.toml生成。原式参照既有第5章台账，R5-SC为项目基准编号。

## R5-SC1

~~~math
\min_{x,w_s}\ C^{DA}(x)+\sum_{s\in\mathcal S}p_s c_s^{\mathsf T}w_s,\qquad p_s>0,\quad\sum_s p_s=1.
\tag{R5-SC1}
~~~

日前净支出计一次，概率只加权补救费用；采用原5-5至5-8的期望结构和已核查符号。

API：[`build_r5_commitment`](@ref)，测试：`R5 shared commitment analytic and scenario KKT`。

## R5-SC2

~~~math
A_s w_s\bowtie b_s+B_sx,\quad \underline x\le x\le\overline x,\quad \underline P^{PCC}\le P_t^{DA}-R_t^U,\quad P_t^{DA}+R_t^D\le\overline P^{PCC}.
\tag{R5-SC2}
~~~

x在全部情景共享；电热关系、硬舒适和交付考核逐情景成立。PCC容量不代表内部物理容量。

API：[`build_r5_commitment`](@ref)，测试：`R5 shared commitment mechanisms and frozen future`。

## R5-SC3

~~~math
y_s^{conditional}=\lambda_s^{joint}/p_s,\qquad g_s=B_s^{\mathsf T}y_s^{conditional}.
\tag{R5-SC3}
~~~

联合目标的概率缩放必须还原；保存实际原始乘子和除数，再检查条件LP的KKT。

API：[`validate_r5_commitment`](@ref)，测试：`R5 shared commitment analytic and scenario KKT`。

## R5-SC4

~~~math
\nabla C^{DA}+\sum_s p_s g_s-F^{\mathsf T}\nu=0,\qquad D=\sum_s p_s(Q_s^{dual}-g_s^{\mathsf T}x)+f^{\mathsf T}\nu.
\tag{R5-SC4}
~~~

Fx⪋f收集一阶段界和PCC关系；用独立参数导数核验共同驻点及完整原对偶差，不能仅以条件子问题最优代替整体最优。

API：[`validate_r5_commitment`](@ref)，测试：`R5 shared commitment input, missing dual and persistence`。

## R5-SC5

~~~math
J=18.46-30P^{DA}-87.5R^U-112.5R^D,\quad (P^{DA},R^U,R^D)=(0.08,0.08,0.062),\quad J^*=2.085.
\tag{R5-SC5}
~~~

合成一小时解析例，费用单位USD、承诺MW；不是作者参数或作者收益。

API：[`solve_r5_commitment`](@ref)，测试：`R5 shared commitment analytic and scenario KKT`。

## 符号

| ID | 数学符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| R5-SC-x | ``x=(P^{DA},R^U,R^D)`` | 跨情景共同日前优化量；与固定成交版本的参数作用域分开 | MW | `first_stage[P_DA_MW/R_up_MW/R_down_MW][t]` |
| R5-SC-w | ``w_s`` | 完整情景已知后的逐情景设备、温度及交付变量 | MW/Mvar/K/pu，依分量 | `scenarios[id].values` |
| R5-SC-p | ``p_s`` | 显式正概率，总和为1；本批输入不是估计出的真实概率 | 1 | `scenarios[id].probability` |
| R5-SC-lambda | ``\lambda_s^{joint},y_s^{conditional}`` | 联合模型的原始乘子和按概率换算的条件乘子 | USD/(对应约束行单位) | `weighted_raw_scenario_duals; raw_constraint_duals; raw_bound_duals` |
| R5-SC-nu | ``\nu`` | 共同承诺边界及PCC约束的原始MOI乘子 | USD/MW | `raw_first_stage_duals` |

## 采用边界

- **R5-SC-C01：**采用原期望费用结构，价格固定且外生；可自由选择的承诺不保证会被市场接受，不能称策略报价。
- **R5-SC-C02：**第二阶段提前知道完整情景轨迹，是两阶段信息结构；不增加在线或多阶段非前视保证。
- **R5-SC-C03：**逐情景硬舒适；尚未联动最坏分布与DRJCC。零概率拒绝而不偷偷删除情景或除以零。
- **R5-SC-C04：**原5-4容量分母和交付罚款保留；模型合格与相对调用量的实际未满足比例分别报告。
- **R5-SC-C05：**原补救系数表已逐项对照旧JuMP建模；共同模型复用该表，物理验算保留独立数值回放。条件KKT使用原系数表，不能宣称又独立推导第三套物理模型。
- **R5-SC-C06：**情景模板成交仅保留来源。优化点的条件视图保留原始数值，不裁剪；一阶段A1独立验收。日前净支出只计一次，不将情景概率重复乘到公共支付。
