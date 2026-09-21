# 第7.5节准备：币种、费用与恢复状态

本节点补齐人民币输入进入已有R7/R8计算链的接口；**尚未运行第7.5节规模保供实验**。
[上一轮百情景对照](ch07-compact-risk.md)的候选、失败与最优性限制保持。
本页的R9-RC1至RC3是项目接口说明编号，不是论文新增公式。
权威映射位于`docs/reading/ch07/resilience-currency.toml`。

## 1. 为什么不能只修改图表的单位

第6章既有输入使用USD，正常费用、启动费用和失供罚值都进入目标函数与费用界。
只把结果标签改成CNY，会混淆参数含义、目标、罚项和历史证据。
新版要求来源数值已经采用所声明的币种；不读取汇率，也不把旧实验重新标注为人民币。

| 项目 | 原v1接口 | 显式v2接口 |
| --- | --- | --- |
| 正常输入 | `r7-normal-case-v1`，隐含USD | `r7-normal-case-v2`，`currency = "USD"`或`"CNY"` |
| 电价 | `price_USD_MWh` | `price_MWh`，单位由`units.price`声明 |
| 设备运行费 | `cost_P_USD_MWh` | `cost_P_MWh` |
| CHP启动费 | `startup_cost_USD` | `startup_cost`，每次启动收费 |
| 正常费用与界 | `solver_objective_USD`、`lower_bound_USD` | `solver_objective`、`lower_bound`，结果显式记录币种 |
| 恢复罚值 | `penalty_USD_MWh`，省略时为500 | 必须显式给出`penalty_MWh`，单位为所声明币种/MWh |

v2的两种币种使用相同字段规则；缺少币种、币种与单位不同、混用旧/新字段均拒绝。
v1保留原字段和默认行为。保存结果时，正常子记录、规划主问题、费用验算和R8阶段记录共同保留币种。
只含物理量的恢复接口与MWh目标不需要改成货币版本。

## 2. 费用为何有的乘时间、有的不乘

以``\mathcal C``代表输入所声明币种。启动变量``v_{g,t}``按次计费；
出力``P``单位MW，运行费与电价单位``\mathcal C/\mathrm{MWh}``，故必须乘小时步长：

```math
C^{\mathrm{normal}}=
\sum_{g,t}c_g^{\mathrm{start}}v_{g,t}
+\sum_\omega p_\omega\sum_t\Delta t
\left[\sum_g c_g^P P_{g,t,\omega}^{\mathrm{use}}
+\pi_t P_{t,\omega}^{\mathrm{PCC}}\right].
\tag{R9-RC1}
```

启动决策跨场景共享，只收费一次；电池的``P^{\mathrm{use}}``为充、放电功率之和。
具体物理关系保持[正常调度模型](ch06-normal.md)的定义，不因新币种更改。

合成手算例使用与旧例相同的数字、另行声明为CNY设计：设备费用50.4、外购电68，合计118.4 CNY。
这不是USD到CNY的换算结果。另一测试将全部费用系数乘1000，验证同一物理解的费用随之缩放。
启动测试取30 CNY/次，四时段出力均为0.4 MW、运行费20 CNY/MWh：
总费用为``30+32\Delta t`` CNY；步长从1 h改为0.5 h时，启动费仍为30。

## 3. 灾害开始时继承什么

事件在正常时段``a``开始，恢复计算继承该时段开始时的储能状态、前一时段的CHP出力与开机状态，
以及此前入口温度和流量形成的真实管内状态：

```math
E^{\mathrm{rec}}_1=E^{\mathrm{normal}}_a,\qquad
P^{\mathrm{rec}}_0=P^{\mathrm{normal}}_{a-1},\qquad
X^{\mathrm{pipe,rec}}_1=X^{\mathrm{pipe,normal}}_a.
\tag{R9-RC2}
```

``a=1``时使用显式窗口前输入。币种随父输入传递，原运行和输入哈希保持可追溯；
事件输入删去正常期电价序列，因为恢复目标计量失供量。
本节点只核查现有共同时间网格的继承，**没有新增小时到15分钟的事件重采样**。
后续采用不同时间步时，还须独立处理爬坡、最小开停时间、热输运和能量积分。

## 4. 正常费用、失供量、罚费分别保存

R8的罚项方案采用：

```math
C^{\mathrm{penalty}}=C^{\mathrm{normal}}+\lambda_{\mathcal C/\mathrm{MWh}}
\sum_e\eta_e,\qquad
\eta_e\ge\max_{f\in\mathcal F_e}
\sum_\omega p_\omega L_{e,f,\omega}^{\mathrm{MWh}}.
\tag{R9-RC3}
```

事件之和不是事件发生概率。经济方案与阈值方案的主要目标仍为正常费用；
固定正常计划后的独立恢复评估始终以MWh为目标，不能把这个下界当作费用下界。
v2调用规格时统一要求显式罚值；在不使用罚项的方案中，该值仅作为已声明配置保留。

本轮测试用10000 CNY/MWh合成罚值核对目标与存档，**没有把它当作作者参数**。
现有``L``统计全部声明的电、热失供量；第7.5节的关键负荷集合及统计范围尚待单独实现。
不能通过修改列名将两者视为同一个指标。

## 5. Julia入口、验证与后续

API仍由原生docstring提供：[`R7NormalCase`](@ref)、[`R7CHPSpec`](@ref)、
[`solve_r7_planning`](@ref)、[`r7_normal_event`](@ref)、[`r8_spec`](@ref)及[`r8_energy_spec`](@ref)。
没有复制整段实现。两个新增测试入口同时在VS Code任务中提供：

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_currency.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_currency_planning.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_resilience_currency.jl
```

覆盖费用手算、步长、单位和混用拒绝、灾前继承、有限故障规划、详细/能流恢复、三种R8目标，
以及存档移位重读和篡改拒绝。开放求解使用HiGHS；这些测试说明接口与核算可用，
不认证新规模运行、关键负荷保供或作者完整输入。

下一步先冻结关键/普通负荷划分、事件窗口、故障集合和成网资格，测量一个有预算的小批次，
再进入完整实验。现有来源冲突继续保存在`docs/reading/ch07/resilience-review.toml`；
明确采用的项目假设可用于验证，但不能冒称是作者唯一输入。

原页复核进一步确认：PDF112（印刷95页）式（6-53）同时积分电、热失供；
PDF139（印刷122页）第7.5节方案4B改称“重要负荷”的失供，罚值10元/kWh，
即10000 CNY/MWh；4C声明四小时重要负荷失供不超过2 MWh。
这说明下一步必须先定义重要负荷的计算范围，不能只复用罚值。
上述币种测试虽使用相同罚值数值，仍未验证这一负荷范围或作者规模案例。

实际检查状态见`docs/agent/tasks/2026-09-21-r9-resilience-currency.md`。
