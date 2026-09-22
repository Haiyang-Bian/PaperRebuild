# 第7.5节准备：允许部分节点停电的恢复域

本节点继续[关键负荷范围](ch07-critical-load.md)，处理已证实的全节点成网反例。
采用版本为`partial_energization_v1`；旧输入默认`all_nodes_energized_v1`，原结果不迁移。
这是明确的项目运行域扩展，**不是已完成作者第7.5节规模实验，也不是全文复现完成**。
权威映射为`docs/reading/ch07/resilience-energization.toml`。

## 1. 原文依据和解释边界

本次直接核读PDF113–114（印刷96–97页）。原（6-56）至（6-58）规定CHP继承日前启停、
调整出力并满足事件首步爬坡；（6-61）继承电池库存。原（6-62）至（6-69）描述故障开断、
动作次数、孤岛根和虚拟连通，未给出独立的节点带电选择。
旧项目式R7-R2要求全部节点进入带根森林，故无根孤立节点即使真实负荷为零仍要求虚拟流`0=-1`。

本项目采用解释：事故后可以有未供电区域；每个实际带电区域须连接一个有声明成网资格的根。
停电区域的机械开关可以仍然闭合，不能因为失电就凭空增加开关动作。
这符合“尽可能恢复负荷”的研究问题，但多出原文没有写明的运行选择，须独立编号并验证。

成网资格仍为显式输入`root_eligible`，PV不自动成为成网源。CHP还须在该时段已开机；
GT/BES的可用成网控制是本输入假设。没有黑启动、频率动态、维持电压所需最小辅助能量模型，
也未新增热网水泵供电依赖。因此通过以下检查不证明完整微网稳定或全部电热辅助设备可运行。

## 2. 机械闭合与实际带电分开

设``z_l``为机械开关闭合，``y_n``为节点带电，``w_l``为线路实际带电。
三者均为0/1且与既有事故拓扑一样跨事件时段和新能源场景共用。

```math
\begin{aligned}
|y_i-y_j|&\le 1-z_l,\\
w_l&\le z_l,\quad w_l\le y_i,\quad w_l\ge z_l+y_i-1,
\qquad l=(i,j).
\end{aligned}
\tag{R9-RE1}
```

闭合线路两端要么一起带电、要么一起停电；``w_l=z_ly_i``由上式精确线性化。
故障与动作仍约束``z``，R7-R1及动作预算不变；不对``w``额外收取动作次数。

## 3. 只让带电节点进入带根森林

```math
\begin{aligned}
\sum_l w_l&=\sum_n y_n-\sum_n\beta_n,\\
\sum_{l\in\delta^+(n)} f_l-\sum_{l\in\delta^-(n)}f_l&=q_n-y_n,\\
|f_l|&\le (N-1)w_l,\quad 0\le q_n\le N\beta_n,\\
\beta_n&\le y_n,\quad\beta_n\le e_n,\quad
\beta_n\le\sum_{g\in\mathcal G_n^{\mathrm{CHP}}}u_{g,t}
 +|\mathcal G_n^{\mathrm{GT,BES}}|\quad(\forall t).
\end{aligned}
\tag{R9-RE2}
```

最后一行只统计正额定电功率设备；``e_n``是显式根资格。辅助流``f,q``没有MW单位。
对任一带电连通分量，虚拟平衡迫使它至少有一个根；其边数至少为节点数减一。
全局边数等式进一步迫使每个带电分量恰有一个根且没有环。
停电节点不消耗虚拟流，也不能作为根。停电区域可以保留闭合环路，因为没有实际电压和潮流；
一旦恢复带电，必须重新满足带电森林条件。

## 4. 停电必须落实到物理量

```math
\begin{aligned}
v^{\min}y_n&\le v_{n,t,\omega}\le v^{\max}y_n,\\
-\overline P_lw_l&\le P_{l,t,\omega}\le\overline P_lw_l,\\
\left|v_i-v_j-\frac{r_lP_l+x_lQ_l}{S_{\mathrm{base}}v_{\mathrm{ref}}}\right|
&\le v^{\max}(1-w_l).
\end{aligned}
\tag{R9-RE3}
```

无功容量同理；原`forward_only`仍用零下界。``v``为电压幅值，绝非平方值。
断开线路潮流为零，但两端可能分别带电/停电，所以电压差上界须从旧``v^{\max}-v^{\min}``
变成``v^{\max}``，这是由允许电压区间推得的有限界。

```math
\begin{aligned}
0\le P^D_n-P^{\mathrm{shed}}_n&\le P^D_n y_n,\\
0\le P_g&\le\overline P_g y_{n(g)},\quad
0\le Q_g\le\overline Q_g y_{n(g)},\\
P_g^{\mathrm{ch}}+P_g^{\mathrm{dis}}&\le\overline P_g y_{n(g)},\qquad
u_{g,t}^{\mathrm{CHP}}\le y_{n(g)}.
\end{aligned}
\tag{R9-RE4}
```

PV上界使用当时可用功率。设备原容量、效率、CHP最小出力/爬坡、BES库存和充放电域全部保留。
CHP/EB热量仍由原电热转换关系计算，停电时不会凭空供热；管内原有热状态按所选热模型继续演化。
原削减比例上限不改：若某节点不允许全部削减，则不能以停电绕过这一边界。

| 符号 | 含义/单位 | Julia名称与维度 |
| --- | --- | --- |
| ``y_n`` | 事件级节点带电，0/1 | `energized[n]` |
| ``w_l`` | 事件级实际带电线路，0/1 | `live[l]` |
| ``z_l`` | 原机械开关闭合，0/1 | `z[l]` |
| ``\beta_n,e_n`` | 根选择/声明资格，0/1 | `beta[n]` / `electric.root_eligible[n]` |
| ``f_l,q_n`` | 虚拟商品流/根供给，无量纲 | `virtual[l]` / `root_supply[n]` |

## 5. 固定模式、LP对偶和规划继承

```math
\mathcal M=(z,y),\qquad
Q_{\mathcal M}(\gamma)=\min_x\{c^\mathsf Tx:
A_{\mathcal M}x\le b_{\mathcal M}+D_{\mathcal M}\gamma\}.
\tag{R9-RE5}
```

仅固定机械开关仍有带电整数选择，模型保持MILP。把``z,y``都固定为合法模式后，根只影响虚拟连通，
取该带电分量内最早合格且可用的节点；不固定根电压或改变物理调度能力。
原和式电池域由此得到实际LP；独立充放电互斥若未固定，仍不能套用LP对偶。

部分带电的对手版本为`r7_inner_energization_v1`，模式同时保存`switch`和`energized`；
旧向量不能静默充当完整新模式。模式生成仍使用完整恢复MILP，受限对手的界仍遵守原截断认证规则。
机械开关穷举在新域下逐模式求解带电MILP，不把它冒称全部连续LP。

正常输入通过电网元数据带入事件模板和真实灾前状态切片，正常调度本身仍使用原连接树。
R7有限故障规划、详细热恢复以及R8详细/能流两条路径继承该域；`retain_surviving`固定机械``z``，
仍允许缺少电源的整个分量停电，不强迫保留线路具有电压。

```@index
Pages = ["ch07-energization.md"]
```

```@docs
with_r7_electric_domain
```

```julia
c = load_r7_recovery_case("configs/r7/recovery-hand.toml")
new_case = with_r7_electric_domain(c, "partial_energization_v1";
    provenance="项目R9-RE1至RE5：显式停电节点采用解释")
```

[`build_r7_recovery`](@ref)、[`solve_r7_recovery`](@ref)接受`fixed_energized`；
[`r7_recovery_lp`](@ref)在新域接收`Dict("switch"=>z,"energized"=>y)`。
[`validate_r7_recovery`](@ref)从保存原值独立检查图、乘积、状态、供能及失供，不复用JuMP约束。

## 6. 验证状态和负结果

解析目标预先定义：一小时0.6MW负荷、其中关键0.3MW，故障后下游没有合格根，则关键失供0.3MWh，
普通失供0.3MWh；若下游拥有合格BES并继承0.2MWh，则关键失供0.1MWh。
零需求孤立节点在新域可停电，旧全节点域仍不可行；两者属于不同采用域。

首轮专项74项通过、2项失败、1项错误，日志`tmp/r7-energization-tests-v1.log`保留。
失败来自测试将原0.5MW CHP状态直接用于0.25h事件：1MW/h爬坡只能降到0.25MW，
孤立且无电需求的源节点不能消纳这部分功率，原模型正确返回不可行。
后续将该工况明确保留为负例，积分测试另给零出力初态，不能把两个初态视为等价转换。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_energization.jl
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/test_r7_energization_gurobi.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_energization.jl
```

当前节点的最终通过数量和完整回归状态以`docs/agent/tasks/2026-09-21-r9-energization.md`为准。
第二轮78项解析/数学、63项正常继承/规划/R8检查通过；本机Gurobi实际对偶8项通过，
固定模式LP对偶、完整恢复MILP故障审计共同认证合成例的最坏关键失供0.3MWh。
这些结果限于声明的运行域；新的节点状态选择没有证明所有故障均可保供，也不能解除CHP的真实爬坡冲突。
第7.5节规模关键负荷分配、故障全集/预算、成网资格与事件窗口仍须独立冻结。

## 7. 本轮结果说明什么

本轮将两类不可行分开：无源节点在旧域内违反全节点成网要求；已开CHP在孤立源区内无法消纳
其最小出力或爬坡下界，则仍违反实际采用的供需边界。允许前者停电，不意味着后者也能自动消失。
因此模型现在可以回答“哪些区域失供、失供多少”，而不只返回无法形成全节点森林。

手算孤岛中，关键失供从无本地电源时的0.3MWh，到显式合格、继承0.2MWh电池时的0.1MWh，
检验的是所声明能量和服务范围；不能由此推断第7.5节系统收益、全部故障覆盖或成网动态安全。
专项测试通过也不能替代规模研究结果。本文新增域单独版本化，旧输入和原结果保留。

下一步先冻结关键负荷节点及分配、事件窗口和共同时间网格、故障全集/预算及成网资格；
完成无故障和少量显式故障的建模、状态继承、回放与耗时预检后，再比较经济调度、失供罚费和
失供上限三种规划。比较须分别报告正常费用、关键/普通失供、热失供、求解界及实际故障覆盖。
