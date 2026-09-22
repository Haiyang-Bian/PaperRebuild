# 有限支持风险：方程与符号

由risk.toml生成。原文PDF92–94已复核；R5-R为项目采用推导编号。

## R5-R1

~~~math
\mathcal U_\rho=\{\pi:\pi_i=\sum_j\Pi_{ij},\ \Pi\ge0,\ \sum_i\Pi_{ij}=\widehat p_j,\ \sum_{ij}d_{ij}\Pi_{ij}\le\rho\}
\tag{R5-R1}
~~~

列j为经验来源，行i为目的支持点；不同时固定行和。对角运输证明非空，质量守恒给有界多面体。原5-64行列记号按文字和5-68统一；半径本批人为冻结，没有统计校准。

原式对应：5-63、5-64、5-65、5-66、5-67、5-68、5-69。API：[`r5_worst_distribution`](@ref)，测试：`R5-R transport primal dual and joint event`。

## R5-R2

~~~math
\min_{x,y,z,\lambda_C,\nu_C}c^\mathsf Tx+\lambda_C\rho+\sum_j\widehat p_j\nu_{C,j},\qquad\lambda_Cd_{ij}+\nu_{C,j}\ge q_i(y_i),\quad\lambda_C\ge0,\quad\nu_C\in\mathbb R^N
\tag{R5-R2}
~~~

全情景直接模型对最坏补救费用取运输对偶，q可为负；日前支出只计一次。物理约束及共同x沿用已核查解释。本批不含原5-72中的报价/出清KKT，不冒称完整策略模型。

原式对应：5-71、5-73、5-74。API：[`build_r5_risk`](@ref)，测试：`R5-R direct MILP and all comfort branches`。

## R5-R3

~~~math
z_i\in\{0,1\},\quad\underline T_j-(\underline T_j-L_j)z_i\le T_{jti}\le\overline T_j+(U_j-\overline T_j)z_i,\quad L_j\le T_{jti}\le U_j
\tag{R5-R3}
~~~

z=0约束该情景全部楼宇/时段上下界。最小有效M来自显式物理域L/U。存在性等价：真实违约指示可用作z，反向只需z覆盖实际事件。原5-75仍有事件方向冲突；采用5-70/80，不强迫z=1一定越界。

原式对应：5-70、5-75、5-76、5-80、5-81。API：[`build_r5_risk`](@ref)，测试：`R5-R direct MILP and all comfort branches`。

## R5-R4

~~~math
\lambda_R\rho+\sum_j\widehat p_j\nu_{R,j}\le\varepsilon,\qquad\lambda_Rd_{ij}+\nu_{R,j}\ge z_i,\quad\lambda_R\ge0,\quad\nu_R\in\mathbb R^N
\tag{R5-R4}
~~~

风险对手与费用对手分开。由R5-R1原LP推导列和乘子自由；不沿用5-83列和项多余距离因子。5-77末尾未定义k不引入额外集合。

原式对应：5-77、5-78、5-79、5-82、5-83、5-84。API：[`validate_r5_transport`](@ref)，测试：`R5-R transport primal dual and joint event`。

## R5-R5

~~~math
\underline J=\min_b\underline J_b,\qquad\overline J=c^\mathsf Tx+\sup_{\pi\in\mathcal U_\rho}\sum_i\pi_iq_i(y_i),\qquad G=\frac{\max(0,\overline J-\underline J)}{\max(1,|\overline J|,|\underline J|)}
\tag{R5-R5}
~~~

全枚举只有全部分支被认证或证明不可行时才合成全局下界；部分枚举保留候选但不给全局证书。固定分支仍不是全问题。

原式对应：项目新增。API：[`solve_r5_risk`](@ref)，测试：`R5-R direct MILP and all comfort branches`。

## 符号

| ID | 数学符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| r5-r-probability | ``\widehat p_j,\Pi_{ij},\pi_i`` | 经验质量、来源j到目的i运输、最坏目的权重；后者可为零 | 1 | `probability, transport[i][j], worst_weights[i]` |
| r5-r-distance | ``d_{ij},\rho`` | 冻结归一化轨迹距离及总运输预算；本批用调用类别独热编码欧氏距离 | normalized_trajectory | `ambiguity.distance, ambiguity.radius` |
| r5-r-event | ``z_i,\varepsilon`` | 舒适放松开关和最坏联合违约上限；一个开关覆盖整个情景轨迹 | 1 | `z[i], epsilon` |
| r5-r-temperature | ``L_j,\underline T_j,\overline T_j,U_j`` | 项目物理域、原采用舒适下上界；初温和终温硬约束不解除 | K | `temperature_domain, buildings.T_min_K, buildings.T_max_K` |
| r5-r-dual | ``\lambda_C,\nu_{C,j},\lambda_R,\nu_{R,j}`` | 费用与风险两套独立运输对偶；nu为自由变量 | cost: USD/distance, USD; risk: 1/distance, 1 | `embedded_duals.cost, embedded_duals.risk` |
| r5-r-objective | ``q_i(y_i),\underline J,\overline J`` | 补救净费用可为负；同模型有效下界与核查策略费用上界 | synthetic USD | `recourse_cost, solver_objective_bound, worst_net_cost` |

## 采用边界

- **R5-R-C01：**费用和风险最大化各自取最坏分布；不能用费用最坏权重替代联合风险。非空有界运输LP的强对偶来自基本LP理论；有限支持结论不继承连续分布保证。
- **R5-R-C02：**原(5-75)与(5-70)/(5-80)冲突，原式保留。逐情景一个开关只解除室温舒适，不解除水温、建筑末期、设备、负荷、网络及交付。
- **R5-R-C03：**新增有限室温物理域是显式项目边界，不冒称原参数；本批舒适带上下各延伸1 K，仅用来限定放松幅度及推导M。热灵活性手算例另外声明末期室温free和0.1小时管延迟。
- **R5-R-C04：**完整情景轨迹补救与固定价格继续沿用；未实现市场策略报价、在线非预见性或统计半径选择。名义情景概率为正，最坏权重可为零，不能除以零提取条件乘子。
- **R5-R-C05：**零权重可能使某情景费用/误差上图不紧；原始值不裁剪。独立费用按真实交付误差计算，模型上图费用另列；无负罚价，减少误差上图保留原约束并不增费用，不声称所有条件补救已最优。
- **R5-R-C06：**实际事件同时记录原始严格越界和超过A1温度带1e-4 K的分类；不把浮点极小偏差当确定科学违约。风险上界来自覆盖事件的开关证书，概率门槛仍1e-8。
