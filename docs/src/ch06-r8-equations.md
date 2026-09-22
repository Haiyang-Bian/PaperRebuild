# R8：目标、恢复界与符号

<!-- generated: r8-tradeoff -->

第6.5节经济/失供上限/罚项的同输入比较；采用既有详细输运参考和有限故障全量式，不声称作者紧凑模型或论文规模。

PDF122明确失负荷惩罚系数500 USD/MWh。6-112对事件求和，内部最坏故障和恢复最小化；新能源场景概率继承6-55。原方案3.1是稳态能量流，不能替换成固定总热库存后仍宣称相同消融。

## R8-S1 原页核查

PDF121，式6-112；PDF122首段。基准仅最小化正常期望费用；方案1加入逐事件最坏恢复失供罚项，惩罚系数500美元/MWh；方案2-A/2-B以6/2MWh约束失供。

状态：`verified_original_page`。

## R8-S2 原页核查

PDF123–124，图6-6及6.5.3。方案3.1采用只含节点能量平衡的能流模型，忽略蓄热与温度动态；方案3.2不允许故障后重构；原阈值对照4/6/8/10/12MWh。

状态：`explained_energy_flow_ablation_not_yet_implemented`。

## R8-S3 原页核查

PDF120–123。PDN15-DHN10名称/图与33电节点正文不符，原Q07保持；PDF122首段方案编号与前页定义不符，按目标识别；事件末端5–11/5–10、16–21/16–22须区分小时索引与物理窗口，不静默统一。

状态：`unresolved_original_labels_and_inputs`。

## R8-T1

~~~math
V_s(x)=\max_{\gamma\in\Gamma_s}\min_{y\in Y_s(x,\gamma)}\sum_\omega p_\omega\Delta t_h\sum_{t,i}(P^{\rm shed}_{i,t,\omega}+H^{\rm shed}_{i,t,\omega}),\quad \min_x C(x)\ \text{s.t.}\ V_s(x)\le L_s
\tag{R8-T1}
~~~

失供先在每新能源场景积分，再按概率加权，然后对故障取最坏；要求每个事件分别满足门槛。电热失供合计用MWh。物理恢复硬约束不可行时不能把损失填成零或全负荷。

API：[`r8_spec`](@ref)。测试：`test/r8_tradeoff.jl` / `R8-T1:T5 objectives, fixed-plan risk and evidence`。

## R8-T2

~~~math
\min_{x,y,\zeta}\ C(x)+\rho\sum_s\zeta_s,\qquad y_{s,\gamma}\in Y_s(x,\gamma),\quad \zeta_s\ge E_{s,\gamma}(y),\quad\rho=500\ {\rm USD/MWh}
\tag{R8-T2}
~~~

所有故障共用正常计划，各故障恢复分别决策。上图变量取事件内最大值，不能把所有故障损失相加。事件之和没有擅自添加发生概率。非凸求解只继承采用模型实际有效界，阈值及罚项比较不依赖论文同输入。

API：[`build_r8_model`](@ref)。测试：`test/r8_tradeoff.jl` / `R8-T1:T5 objectives, fixed-plan risk and evidence`。

## R8-T3

~~~math
J_{\rm penalty}=C_{\rm normal}+\rho\sum_s\zeta_s,\qquad J_{\rm threshold}=J_{\rm economic}=C_{\rm normal}
\tag{R8-T3}
~~~

费用报表分开正常资源费用、失供罚项与求解目标；例如解析例193.275美元正常费用加两个0.4MWh事件、500美元/MWh，罚项目标为593.275美元。经济基线不含灾后存在性约束，其恢复评估失败也保留正常最优记录。

API：[`validate_r8_solution`](@ref)。测试：`test/r8_tradeoff.jl` / `R8-T1:T5 objectives, fixed-plan risk and evidence`。

## R8-T4

~~~math
\widehat x=x^{\rm saved},\quad B_\Sigma\le\sum_s V_s(\widehat x)\le\sum_s U_s,\quad \max(0,B_\Sigma-\sum_{j\ne s}U_j)\le V_s(\widehat x)\le U_s
\tag{R8-T4}
~~~

主调度之后独立固定全部正常控制及状态，最小化逐事件最坏失供之和。各事件恢复块条件独立，整体下界减其他事件可行上界给逐事件下界。阈值主问题只需存在性见证，不能用其任意损失冒称最小最坏损失；独立评估不回写正常计划，界以MWh计。

API：[`solve_r8_case`](@ref)。测试：`test/r8_tradeoff.jl` / `R8-T1:T5 objectives, fixed-plan risk and evidence`。

## R8-T5

~~~math
z_\ell=z_\ell^0(1-\gamma_\ell),\qquad E_{p,t}^{S/R}\le E_{p,1}^{S/R}\quad(\text{optional, separate controls})
\tag{R8-T5}
~~~

第一项只用于无重构对照，强制故障边断开并保持其余原状态；第二项只用于禁止正常期净预充热。两项独立选择，不能把第二项称为去掉热惯性或作者方案3.1。删除电池是另一独立输入变体。

API：[`build_r8_model`](@ref)。测试：`test/r8_tradeoff.jl` / `R8-T1:T5 objectives, fixed-plan risk and evidence`。

## R8-T6

~~~math
\beta=\frac{UA\Delta t_s}{Mc},\quad k=\frac{1-e^{-\beta}}{\beta},\quad \bar R_T\le a+(S_0-a)e^{-\beta}-(S_0-R_0)k<R_0
\tag{R8-T6}
~~~

项目负结果证书：单供回管、每步换水质量等于管内质量、同UA与恒定环境、初态为无损均温平衡、固定热负荷、至少两时段。逐步供管库存不超初始推出入口上界；负荷温降及回管积分使末端平均回温低于初值，因此与回管周期库存冲突。只认证此固定流量边界，不推广到自由流量或作者稳态能流；UA为零时等号恢复。

API：[`r7_pipe_step`](@ref)。测试：`scripts/test_r8_heat_boundary.jl` / `R8-T6 normal heat boundary certificate`。

## 符号

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R8-boundary | ``a,S_0,R_0,M,c,\beta,k`` | 环境温度、初始供回均温、单管质量、比热、一步散热指数、平均衰减系数；仅用于R8-T6边界证书 | K; K; K; kg; J/(kg K); dimensionless; dimensionless | `ambient_K / initial_S_profiles / initial_R_profiles / mass / c_J_kgK / β / k` | 单管与单场景标量 |
| R8-cost | ``C,J,\rho`` | 正常费用、各模式目标、失供价格 | USD; USD; USD/MWh | `normal_cost_USD / objective_value / penalty_USD_MWh` | 标量 |
| R8-risk | ``V_s,\zeta_s,L_s,U_s`` | 固定计划最坏期望失供、上图变量、允许门槛、见证上界 | MWh | `event_lower_MWh / eta_MWh / limits_MWh / event_upper_MWh` | 事件 |
| R8-index | ``s,\gamma,\omega,p_\omega`` | 事件、故障组合、新能源场景、场景概率；事件无额外概率 | 索引或无量纲 | `event / fault / scenario / probabilities` | 原输入集合 |
