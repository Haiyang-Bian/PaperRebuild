# 保供准备：保留初始管温的空间分布

本页继续[部分节点停电](ch07-energization.md)，补齐正常调度至事故恢复之间的初态表达。
`r7-initial-profile-v2`是**项目输入表示扩展**，保留既有塞流参考模型中的指数水团。
它没有补出作者未公开的历史，也没有完成第7.5节规模保供实验。
权威映射见`docs/reading/ch07/resilience-initial-profile.toml`。

## 1. 为什么平均温度不够

同样的总热量可以对应不同空间分布。靠近出口的水先离开管道；把一根管道全部改为平均温度，
虽然初始库存相同，却改变了近期出口温度和可交付热量。

对恒定入口、环境、正向流量的稳态有损管，质量坐标上的温度为

```math
T(x)=T_a+(T_{\mathrm{in}}-T_a)
\exp\!\left[-\frac{UA}{M c\dot m}x\right],\qquad 0\le x\le M .
\tag{R9-RI1}
```

``x``从该管当前入口量起，单位kg；``M``为管内水质量kg，
``c``为J/(kg·K)，``\dot m``为kg/s，``UA``为W/K。
指数无量纲，出口衰减为``\exp[-UA/(c\dot m)]``。
这从稳态对流—散热守恒推得，是项目参考初态，不是论文给出的节点历史。

已有水团回放器能够表示该分布；本批让输入、正常调度、事件继承和连续流量模型保持同一分布。
旧`mass_kg/temperature_K`仍表示分段常温，输入及历史记录不自动迁移。
`node_method_fixed_v1`需要它自己的入口历史；新空间输入不会静默转成作者节点法历史。

## 2. 输入表示、方向和能量

每段存储`mass_kg, base_K, amplitude_K, rate_per_kg, from_left`。
幅值允许为负，基准温度可以低于实际管温下界；须检查的是实际两端温度。
指数单调且衰减率非负，因此两端均合格可保证整个初始段位于温区内。
`from_left=false`只表示指数坐标从该段右端起算，不授权优化模型反向流动。

```math
\begin{aligned}
T_j(x)&=B_j+A_j e^{-k_j d_j(x)},&
d_j(x)&\in\{x,M_j-x\},\\
\overline T_j&=B_j+A_j\phi(k_jM_j),&
\phi(z)&=\begin{cases}(1-e^{-z})/z,&z>0,\\1,&z=0,\end{cases}\\
E_0&=\frac{c}{3.6\times10^9}
\sum_j M_j(\overline T_j-T_{\mathrm{ref}}).
\end{aligned}
\tag{R9-RI2}
```

能量``E_0``单位MWh，温度K；实现用`expm1`避免小指数直接相减的精度损失。
事件聚合能流模板可以使用精确均温，但详细恢复继续继承完整空间段，二者职责不同。
终端`pipe_inventory_initial`只约束总库存，不自动等于整条温度分布恢复。

| 量 | Julia/输入 | 单位和范围 |
| --- | --- | --- |
| ``M_j`` | `mass_kg` | kg，正且有限 |
| ``B_j,A_j`` | `base_K, amplitude_K` | K，有限；幅值可正可负 |
| ``k_j`` | `rate_per_kg` | 1/kg，非负有限 |
| ``d_j``的方向 | `from_left` | 显式布尔值 |
| 来源 | `provenance` | 非空说明，不能把合成初态写成原始测量 |
| 段精确均值 | 内部`initial.mean` | 与实际指数积分一致 |

## 3. 连续流量下如何保留该初态

累计质量法用入管标签追踪水团；初始标签与空间坐标方向相反。
每个时段求“当步离管区间”和“仍留在管中的区间”与各初始段的交集，
再在该交集上积分。每段的基准温度按环境变化递推，指数幅值按经过时间衰减。
零流量没有出口热交付，但库存仍会散热；恢复流动时继续使用留下的分布。

指数积分沿用[有损连续流量](ch06-lossy-flow.md)的5/10点Gauss规则。
由[NIST DLMF 第3.5(v)节的求积余项](https://dlmf.nist.gov/3.5#v)，映射到单位区间后有

```math
\left|\int_0^1 e^{a+du}\,\mathrm du-Q_n\right|
\le K_n |d|^{2n}e^{\max(a,a+d)},\qquad
K_n=\frac{(n!)^4}{(2n+1)((2n)!)^3}.
\tag{R9-RI3}
```

本项目由此另计初态空间指数跨度``\sigma=\max_j k_jM_j``；
不能仍然只按当步散热指数``\beta``估计误差。使用既有保守函数
``B_n(b,C)=C e^bK_n[b^{2n}+(2b)^{2n}]``，
新初态增加``B_n(\beta+\sigma,C_0+A_{\max})``，
其中``C_0=\max_{j,t}|B_j-T_{a,t}|``、``A_{\max}=\max_j|A_j|``。
全部量先按同一温区归一化，再加到旧截断界。
即使时间散热为零，非恒定空间初态仍需该检查；超过原`1e-10`门槛即拒绝。

该界只覆盖积分截断，不包括浮点舍入、优化器可行性容差或网络误差传播。
因此仍用独立`r7_pipe_step`核验出口、库存及能量；不以本建模核自检代替回放。
指数初态配合实际流量变量可能产生非线性约束，不能继续一概称为MIQCP。
零UA的新空间输入结果也显式标记费用界适用范围，并保持
`exact_transport_optimality_verified=false`；固定流量解析特例的条件界不会升级为完整连续系统的界。

## 4. Julia入口及验证

```@index
Pages = ["ch07-initial-profile.md"]
```

```@docs
r7_initial_profile
```

```julia
state = PaperRebuild.R7PipeState([
    PaperRebuild.R7PipeSegment(18000.0, 293.15, 50.0, 50/(18000*4200*5), true),
])
profile = r7_initial_profile(state; provenance="合成恒流稳态；UA=50 W/K，流量5 kg/s")
```

该`profile`用于相应管道的`initial_S_profiles`或`initial_R_profiles`；
每个情景须显式提供。输入检查会拒绝混合两种格式、缺来源、非法方向、质量或温度越界。
[`load_r7_normal_case`](@ref)、[`build_r7_normal_flow`](@ref)、
[`build_r7_flow_planning`](@ref)使用同一输入，独立验证和存档回放保留完整来源。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_initial_profile.jl
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/test_r7_initial_profile_gurobi.jl tmp/new-profile-check
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_initial_profile.jl
julia +1.12.6 --startup-file=no --project=. scripts/audit_r9_resilience_input.jl tmp/new-input-audit.toml
```

专项覆盖两种指数方向、正负幅值、非整步输运、停流/重启、变化环境和步长、
初态真实端点、过大截断界拒绝，以及正常—恢复共同规划、移位重读和篡改拒绝。
开发检查首版因测试用`fix(...; force=true)`删除声明边界而失败；
修正测试为等式固定并保留原界，原失败日志保留，没有调整A1。

## 5. 当前证据与下一步

第7.5节预优化输入审计使用既有工程参数协议。两套原图关键节点集各按
13.75 MW等分，再用逐节点较大值加共同剩余分配，构造同一总负荷41.103 MW。
这是显式的**候选分配和同峰假设**，不是作者原始节点数据，也尚未冻结为规模算例。

| 预检量 | 数值 | 可得出的结论 |
| --- | ---: | --- |
| 参考CHP2电出力 | 4.629704 MW | 在已声明的3.4–6 MW容量范围内 |
| 节点15参考供热 | 0.654203 MW | 在1.2 MW容量范围内 |
| 将同热量初态压为均温后的首步最大出口偏差 | 0.172556 K | 均温替代改变近期交付，不能视为原空间状态等价表示 |

这些是容量与输运预检，不是完整电热网络可行性或保供收益。
本批84项开放检查及20项本机Gurobi检查通过；解析反问题应取`q=2`，
实际`2.000000004000529`、有效下界`2.0`。这认证的是该单管小问题。
工程收尾以`docs/agent/tasks/2026-09-21-r9-initial-profile.md`的实际记录为准。

后续须明确可操作开关范围、关键负荷分配、事件时钟、故障集合/预算及成网资格，
再做无故障和少量故障的规模预运行。正常费用、关键/普通失供、热失供、有效界和故障覆盖
分别报告，不提前用小例通过宣布第7.5节或整篇论文完成。
