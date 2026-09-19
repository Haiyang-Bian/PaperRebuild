# R7内层故障对手：方程、符号与边界

<!-- generated: r7-adversary -->

固定灾前状态、线性恢复与有限拓扑的内层故障对手；截断与原生指示约束为项目采用解释。

## 原式6-105

~~~math
\theta(x^*,\gamma^*)=\min_{(r,z)\in\mathcal Y(x^*,\gamma^*)}f^{\mathsf T}r
\tag{6-105}
~~~

PDF119：固定故障后最小化恢复失供；不可行采用扩展值+∞。

## 原式6-106

~~~math
\overline\Theta=\max f^{\mathsf T}r_0
\tag{6-106}
~~~

PDF119：受限恢复模式的对手主问题最大化；有效求解器界是最坏损失上界。

## 原式6-107

~~~math
G\gamma\geq E
\tag{6-107}
~~~

PDF119：本页右侧为E，其他紧凑式记号不完全一致；代码直接用线路脆弱标志与故障数量预算。

## 原式6-108

~~~math
Fx^*+H\gamma+Kr_0+Jz_0\leq g
\tag{6-108}
~~~

PDF119：同时要求候选故障存在恢复见证。若模型允许某个故障完全无恢复，该式会将其排除；不能直接套用到已证实存在硬不可行的采用模型。

## 原式6-109

~~~math
f^{\mathsf T}r_0\leq(g-Fx^*-H\gamma-Jz_q^*)^{\mathsf T}\pi_q,\quad 1\leq q\leq o
\tag{6-109}
~~~

PDF119：使用已发现恢复拓扑的对偶约束限制对手。原文对偶符号须与6-108及恢复变量域联合检查；本实现从全部实际LP行重新推导。

## 原式6-110

~~~math
K^{\mathsf T}\pi_q\geq f,\quad1\leq q\leq o
\tag{6-110}
~~~

PDF119：不能直接用于自由变量、≤行的最小化LP。采用版将变量界显式列为行，平稳性为等式。

## 原式6-111

~~~math
\pi_q\in\mathbb R_+^n,\ z_q\in\{0,1\}^p,\quad1\leq q\leq o
\tag{6-111}
~~~

PDF119：文中z_q*是已发现拓扑。项目λ采用≤0约定，不靠修改原始乘子令其通过。

## R7-I1

~~~math
q_z(\gamma)=\min_{r\in\mathbb R^n}\{c^{\mathsf T}r: A_zr\leq b_z+D_z\gamma\},\qquad q_z(\gamma)=\sup_{\lambda\leq0,\ A_z^{\mathsf T}\lambda=c}(b_z+D_z\gamma)^{\mathsf T}\lambda
\tag{R7-I1}
~~~

将实际标量仿射行、变量上下界和固定值全部抽取；等式拆为两侧，恢复变量本身自由。给定灾前状态及拓扑，故障只进入右侧。可行有界LP用强对偶；不可行且对偶可行时取+∞。

原式：6-105、6-108、6-109、6-110、6-111；分类`derived_from_actual_primal_rows`。

实现：[`r7_recovery_lp`](@ref)。测试：`test/r7_adversary.jl` / `R7-I1-row-extraction`。

## R7-I2

~~~math
c_j>0,\ -r_j\leq0\ \Longrightarrow\ \lambda_{i(j)}=-c_j,\quad \lambda_i=0\ (i\notin\{i(j)\})
\tag{R7-I2}
~~~

失供目标只有非负系数，每个有费用变量有显式零下界，因此上述λ对所有故障同时满足Aᵀλ=c、λ≤0。该事实让不可行恢复具有对偶无界方向，不能默认所有固定拓扑都可行。抽取时拒绝不满足此条件的目标。

原式：6-105、6-109；分类`common_dual_feasibility_certificate`。

实现：[`validate_r7_dual`](@ref)。测试：`test/r7_adversary.jl` / `R7-I2-free-variables-and-common-seed`。

## R7-I3

~~~math
B=\Delta t\sum_{t,\omega}\pi_\omega\left(\sum_n\bar\alpha_nP_{n,t}^d+\sum_j\bar\alpha_j^hH_{j,t}^d\right),\quad C=B+1\ {\rm MWh},\qquad \overline W_Z^C=\max_{\gamma\in\mathcal U}\min\{C,\min_{z\in Z}q_z(\gamma)\}
\tag{R7-I3}
~~~

B是任一可行恢复的失供积分上界；C只是对手认证截断，不是物理损失或乘子边界。有限模式池给完整最坏损失的上包络：若有效主问题上界低于C，则原最坏损失不超过它；若饱和，原问题上界保持∞，由完整恢复判断缺模式还是实际不可行。空池初值为C。

原式：6-93、6-105、6-106、6-108、6-109；分类`project_capped_oracle_for_infeasible_recourse`。

实现：[`r7_recovery_loss_cap`](@ref)。测试：`test/r7_adversary.jl` / `R7-I3-finite-cap-not-dual-M`。

## R7-I4

~~~math
\gamma_l=0\Rightarrow w_{qil}=0,\qquad\gamma_l=1\Rightarrow w_{qil}=\lambda_{qi},\qquad\theta\leq b_q^{\mathsf T}\lambda_q+\sum_{i,l}D_{qil}w_{qil}
\tag{R7-I4}
~~~

二值故障乘子乘积采用原生指示等式，关闭自动桥接且没有项目选择的乘子大M。求解器内部表示仍受数值容差影响，必须检查原始乘子、指示乘积、完整恢复原值和有效界。不适用于某故障的模式留在行系统中，不在零故障下先过滤掉。

原式：6-109；分类`native_indicator_reformulation`。

实现：[`build_r7_adversary`](@ref)。测试：`test/r7_adversary.jl` / `R7-I4-fault-dependent-topology-domain`。

## R7-I5

~~~math
\max_{\gamma\ {m checked}}\underline q(\gamma)\leq W,\qquad W\leq\overline W_Z^C\quad\text{仅当已认证 }\overline W_Z^C<C
\tag{R7-I5}
~~~

固定故障完整恢复的有效最小化下界给W下界；对手最大化的有效界给未截断上界。不能把受限对手可行目标当完整恢复最优值。预算、重复模式未闭合、无许可与不支持原生指示保持未决；认证恢复不可行另给∞反例。

原式：6-93、6-105、6-106；分类`corrected_bound_direction_and_failure_semantics`。

实现：[`solve_r7_adversary`](@ref)。测试：`test/r7_adversary.jl` / `R7-I5-budget-and-unsupported-native`。

## 原文与采用解释

### IP01

原文：原6-108要求故障具有可行恢复；本项目已有继承CHP孤岛硬冲突。

采用：不删除无恢复故障；共同可行对偶和预定截断处理无界模式，完整恢复MILP决定是否为真实反例。

状态：`derived_and_implemented_tests_recorded_separately`。

### IP02

原文：原步骤2.a把固定故障恢复值赋给UB，2.b把对手值赋给LB。

采用：对max-min的含义分别推导上下界，不能直接沿用标签；用同一固定状态的穷举参考检验。

状态：`bound_labels_corrected_with_explicit_derivation`。

### IP03

原文：原文说明BigM线性化二值故障与对偶乘积，未在本页给出有效乘子有限界。

采用：使用Gurobi/JuMP支持的原生指示约束，项目不猜乘子界；未声称求解器内部没有M或数值风险。

状态：`project_alternative_reformulation`。

## 符号表

| ID | 数学符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7-I-lp | ``A_z,b_z,D_z,c,r`` | 完整LP行、故障系数、失供费用及自由恢复变量 | 各物理行原单位；目标MWh | `R7RecourseLP.data / rows / cost` | sparse row lists / recovery variables |
| R7-I-dual | ``\lambda_z,w_{zil}`` | 非正对偶乘子及二值故障乘积 | MWh每单位原行量 | `lambda / products` | row; nonzero fault coefficient |
| R7-I-cap | ``B,C,\theta,\overline W_Z^C`` | 可行损失上界、认证截断、对手目标、受限模式最坏值 | MWh | `feasible_upper_MWh / cap_MWh / theta / solver_upper_bound_MWh` | scalar |
| R7-I-pool | ``\gamma,Z,z`` | 故障向量、已验证恢复拓扑池、共享恢复拓扑 | binary/set | `fault / topologies / added_topology` | line vector / pool |
