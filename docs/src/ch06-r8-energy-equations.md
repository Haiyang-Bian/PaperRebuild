# R8稳态能流对照：原页、推导与符号

<!-- generated: r8-energy-flow -->

r8_energy_flow_checked_v1；第6.5.3节方案3.1的显式项目采用解释。

核读PDF123–124（印刷106–107页）。作者声明仅考虑能量流节点平衡、忽略管道热储与温度动态，但未完整公开该对照的容量和散热实现；下列编号均属项目，不能冒用原论文式号。

## R8-E-source 原页核查

PDF123，第6.5.3节方案3.1。作者采用能流模型，仅考虑节点能量平衡，忽略管道热储与温度动态。移除净预充热约束并不是该模型。

状态：`original_page_verified`。

## R8-E-mechanism 原页核查

PDF124，图6-7及下方解释。示例灾害的前两小时供热大于需求，电锅炉将较充裕电力转成管网存热；后续利用储热减少电锅炉电耗。新增合成手算例专门检查这种时序机制。

状态：`original_page_verified`。

## R8-E1

~~~math
H_{j,t,w}^{gen}+\sum_{a:\,a\to j}(F_{a,t,w}-\bar L_{a,t})=H_{j,t}-H_{j,t,w}^{shed}+\sum_{a:\,j\to a}F_{a,t,w}
\tag{R8-E1}
~~~

逐节点瞬时能量平衡。正常期没有削减项；恢复期保留原负荷削减上界。F为每个供回水管对的净热能流，不是质量流率或供水绝对焓。没有管网库存、时延、温度混合或水压。

API：[`build_r8_energy_model`](@ref)。测试：`test/r8_energy_flow.jl` / `R8-E1:E3 steady energy balance and independent accounting`。

## R8-E2

~~~math
\bar L_{a,t}=10^{-6}\sum_{q\in\{S,R\}}UA_a^q(\bar T^q-T_t^{amb}),\qquad \bar L_{a,t}\le F_{a,t,w}\le\bar F_a
\tag{R8-E2}
~~~

reference_UA按SI单位、参考温度计算固定损耗，流入端扣一次损耗。它是项目散热解释，代表保持温热的固定网络；即使负荷全削减仍需要补偿这项热损耗，可能产生硬不可行。lossless只允许共同输入的UA全为零。有限管道热容量显式输入。

API：[`r8_energy_spec`](@ref)。测试：`test/r8_energy_flow.jl` / `R8-E1:E3 steady energy balance and independent accounting`。

## R8-E3

~~~math
\eta_s\ge\sum_w p_w\Delta t\sum_{t,j}(P_{j,t,w}^{shed}+H_{j,t,w}^{shed}),\quad\forall\gamma\in\Gamma_s
\tag{R8-E3}
~~~

每事件对全部故障使用上图变量；新能源场景加权，事件互为替代。正常成本、门槛与500USD/MWh罚项沿用R8口径。固定原正常计划后的独立恢复只最小化各事件η之和，其MWh界不能解释为正常费用界。

API：[`solve_r8_energy_case`](@ref)。测试：`test/r8_energy_flow.jl` / `R8-E1:E3 steady energy balance and independent accounting`。

## R8-E4

~~~math
\Delta E_t=\Delta t(H_t^{gen}-H_t^D),\quad H^{gen}=(0.5,0.5,0.3,0.3),\quad H^D=(0.4,0.4,0.4,0.4)\;\mathrm{MW}
\tag{R8-E4}
~~~

零UA、每小时交换整管水量的独立手算见证，累计相对初值储热为(0.1,0.2,0.1,0)MWh，末端供回水状态回到初值。CHP≤0.3MW、GT≤0.5MW，晚段电负荷0.8MW；即时能流下每增加p MW电锅炉至少增加p MW电削减，却只减少0.95p MW热削减，因此两个晚段总失供至少0.2MWh。该推导不是优化结果。

API：[`r7_pipe_step`](@ref)。测试：`scripts/test_r8_energy_cases.jl` / `R8-E4 frozen four-hour mechanism before optimization`。

## 符号

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| r8-energy-flow | ``F_{a,t,w}`` | 管对有向净热流 | MW | `H_pipe[a,t,w]` | 管道×时段×场景 |
| r8-energy-loss | ``\bar L_{a,t}`` | 冻结参考温度散热 | MW | `loss[a,t]` | 管道×时段 |
| r8-energy-capacity | ``\bar F_a`` | 显式热流容量，不自动取无穷 | MW | `pipe_capacity_MW[a]` | 管道 |
