# 第6章选定关系、符号与疑点

<!-- generated: ch06-audit -->

由`docs/reading/ch06/audit.toml`生成。当前是实施前的选定关系审计，
不是全部原式核查或已实现调度API。原件PDF107–119（印刷90–102）。

## R7-A1

~~~math
Q_s(x)=\max_{\gamma\in\mathcal U_s}\min_{(r,z)\in\mathcal Y_s(x,\gamma)}\sum_{\omega}\pi_\omega\sum_{t\in T_s^C}\left(L^P_{t,\omega,s}+L^H_{t,\omega,s}\right)\Delta t\le\bar L_s
\tag{R7-A1}
~~~

对规定事件的允许线路故障取最坏，对新能源场景加权。失供为MWh，电热分项保留；期望阈值不保证每条新能源轨迹都达阈值。窗外失供置零是待实施的显式边界。

原式/步骤：6-52、6-53、6-93；分类：`adopted_quantifier_and_unit_definition`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-quantifiers`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A2

~~~math
u_{g,t,s,\omega}^{\rm CHP}=u_{g,t}^{\rm CHP},\quad z_{e,s,\omega}=z_{e,s},\quad m_{p,t,s,\omega}=m_{p,t,s}
\tag{R7-A2}
~~~

CHP沿用灾前启停但允许灾后调整出力；事件拓扑跨时段/新能源场景共用，流量跨新能源场景共用。场景相关连续调度、储能及热状态分别保存。恢复前状态从同一x和同一omega继承，不能重置或默认满储。

原式/步骤：6-56、6-61、6-62、6-70、6-71、6-72；分类：`index_based_adopted_information_structure`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-shared-control`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A3

~~~math
C_a=\frac{c_w\rho_w\sum_p A_pL_p}{3.6\times10^9},\quad E_a=C_a(T_a-T_{a,0}),\quad \bar E_a=C_a(T_{a,\max}-T_{a,0}),\quad T_a=T_{a,0}+E_a/C_a
\tag{R7-A3}
~~~

项目采用相对下限温度的显热，a为供水S或回水R。cw用J/(kg K)、rho用kg/m3、体积用m3，C为MWh/K，E为MWh。此式为单个等温等效水箱；不同管温须先按体积计算初始显热，不把温度偏差当绝对温度。

原式/步骤：6-76、6-77、6-78、6-79、6-81、6-82、6-87、6-90；分类：`derived_energy_datum_correction`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-energy-datum`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A4

~~~math
E^S_{k+1}=E^S_k+\Delta t(H^{\rm src}_k-H^{S,loss}_k-H^{CF}_k),\quad E^R_{k+1}=E^R_k+\Delta t(-H^{D}_k-H^{R,loss}_k+H^{CF}_k)
\tag{R7-A4}
~~~

功率用MW，时间用h；两箱相加后循环交换项精确抵消。采用区间起点状态k和区间流量/功率，事件首区间从灾前对应边界继承，消除原储能t+1式与t_s-1描述的下标歧义。

原式/步骤：6-76、6-77、6-78、6-79；分类：`derived_time_integral_and_state_convention`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-energy-integration`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A5

~~~math
H^{CF}_{\rm lin}=\frac{c_w}{10^6}\left[m\Delta T^{\rm ref}+\hat m(\Delta T-\Delta T^{\rm ref})\right],\quad H^{CF}-H^{CF}_{\rm lin}=\frac{c_w}{10^6}(m-\hat m)(\Delta T-\Delta T^{\rm ref})
\tag{R7-A5}
~~~

作者一阶展开的余项可正可负，因此不是天然上界或下界。m用kg/s，DeltaT用K，功率用MW。需要冻结参考点并逐时报告余项，不能把线性代理认证扩大为详细输运认证。

原式/步骤：6-88、6-89；分类：`author_approximation_with_derived_error`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-circulation-remainder`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A6

~~~math
\sum_e z_{e,s}=|\mathcal N|-\sum_n\beta_{n,s}
\tag{R7-A6}
~~~

若保留全部节点且每个连通分量恰有一个计入beta的根，森林边数等于节点数减根数。原6-67另减1需未计入beta的额外根解释，而6-68又对全部节点施加根指示；采用前必须明确根集合和虚拟流关联矩阵。

原式/步骤：6-64、6-67、6-68、6-69；分类：`conditional_graph_identity_not_full_network_implementation`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-forest`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A7

~~~math
\min_{r\in\mathbb R^k}\{f^\mathsf Tr:Kr\le b\}=\max_{\lambda\le0}\{b^\mathsf T\lambda:K^\mathsf T\lambda=f\}
\tag{R7-A7}
~~~

对与原6-95同方向、自由r的可行有界LP重新推导；变量界作为约束行。若改为r非负，对偶驻点须改为K^T lambda<=f。原正乘子/大于号组合不直接复用，也不把MILP整体强对偶。

原式/步骤：6-95、6-105、6-109、6-110、6-111；分类：`derived_dual_convention`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-dual`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A8

~~~math
\max_{\gamma\in U_0}\ell_\gamma\le Q_s(x)\le\max_{\gamma\in\mathcal U_s}u_\gamma,\quad \ell_\gamma\le q_\gamma(x)\le u_\gamma
\tag{R7-A8}
~~~

左侧可用已检查故障的有效最小化下界；右侧要求覆盖全部允许故障的可行恢复上界。漏查故障/缺解不能给有限安全证书。对手主问题若仅含部分恢复模式，是最大化松弛，只有有效求解器上界可用于其上界。

原式/步骤：6-96、6-105、6-106、6-109；分类：`derived_nested_certificate_direction`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-bounds`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## R7-A9

~~~math
\operatorname{safe}(x^{(k)})\Longleftrightarrow\bigwedge_s\left[\operatorname{revision}(\operatorname{certificate}_s)=k\ \land\ UB_s(x^{(k)})\le\bar L_s\right]
\tag{R7-A9}
~~~

外层每次改变x后旧事件通过标志失效。安全认证用每个事件在同一当前x上的有效上界；不能只修正原I的0/1停止条件而沿用旧记录。

原式/步骤：6-100、6-102、6-103、6-104、outer-step-2b、outer-step-2d；分类：`derived_Q06_adopted_contract`。

解析核查：`scripts/audit_ch06.jl`；测试：`R7-revision`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。

## 符号

Julia栏为下一批接口命名约定，`planned`表示尚未实现。

| ID | 符号 | 含义 | 单位 | Julia命名计划 |
|---|---|---|---|---|
| r7-first-stage | ``x`` | 灾前决策及场景状态；必须绑定版本 | mixed | `planned: pre_event` |
| r7-event | ``s,T_s^C,t_s,L^C`` | 事件、离散时间窗、开始时段和持续步数 | index | `planned: events` |
| r7-fault | ``\gamma_{e,s}`` | 1为线路故障，跨事件窗固定 | 1 | `planned: γ_fault[e,s]` |
| r7-switch | ``z_{e,s},\beta_{n,s}`` | 1为闭合线路、1为被计入的微网根；不同于第5章舒适开关 | 1 | `planned: z_line[e,s], β_root[n,s]` |
| r7-scenario | ``\omega,\pi_\omega`` | 新能源场景及概率，故障对手不选择此概率 | index; 1 | `planned: scenario_weights` |
| r7-shed | ``L^P,L^H,\bar L_s`` | 电热失供功率与事件加权失供能量门槛；L^P/L^H为项目清晰别名 | MW; MWh | `planned: P_shed, H_shed, limit_MWh` |
| r7-heat-state | ``E^S,E^R,C_S,C_R,T_{a,0}`` | 两侧相对显热、等效热容及能量零点温度 | MWh; MWh/K; K | `planned: E_S, E_R, C_MWh_per_K, T_min_K` |
| r7-circulation | ``m^{CF},H^{CF},\hat m,\Delta T^{ref}`` | 循环流量、两箱交换功率、冻结流量参考和供回温差参考 | kg/s; MW; kg/s; K | `planned: m_CF, H_CF, m_reference, ΔT_reference` |
| r7-dual | ``\lambda,\ell_\gamma,u_\gamma`` | 采用LP方向的乘子、给定故障恢复的有效下界和可行上界 | row-dependent; MWh; MWh | `planned: raw_duals, recovery_bound, recovery_value` |

## 原页与采用解释

### R7-C01

PDF107、113；6-2至6-7、6-56至6-61；`interpretation_checked_remaining_inputs_open`。

原页记录：慢启停CHP的日前启停计划在恢复期保持，出力可以调整；事件开始爬坡与灾前相连，电池继承故障前状态且可不约束灾后首末相等。

项目处理：区分固定启停与固定出力；存储k为区间起点的采用索引。最低开停机的nu转移及首日历史仍须逐式补齐，不套用其他章边界。

### R7-C02

PDF108、114；6-23至6-25、6-66；`literal_counterexample_and_correction_pending_model`。

原页记录：6-23以(Vmax-Vmin)z限制电压松弛；6-24/25以z乘容量，6-66文字明确z=0断开。

项目处理：关闭支路应施加电压关系，断路应允许电压解耦；原开关因子方向须登记。采用有限电压界导出的M(1-z)，不随意设置大M。当前只作二值逻辑反例，未建电网模型。

### R7-C03

PDF111–112；6-47至6-50；`eventwise_definition_available_general_set_conflict_preserved`。

原页记录：文字gamma=1为断线，而6-47的故障开始窗口和<=1-gamma；6-50另给事件固定故障集合且sum gamma<=K。

项目处理：通用6-47在激活开始时与文字冲突。首批采用作者后给的事件窗集合6-50，保留零故障到K故障，不假定故障单调性；即使内部零故障，事件期PCC仍按6-51脱网。

### R7-C04

PDF113；6-62；`literal_counterexample_not_adopted`。

原页记录：扫描式第三行给a_OFF<=0，另有z_base+a_ON<=1；开断动作又被定义为二值动作。

项目处理：按此字面约束，健康闭合线路不能主动打开，已开线路遇gamma=1也有身份冲突。后续需明确故障候选仅含哪些线路并建立二值真值表；不静默把<=0替换为常见式。

### R7-C05

PDF114；6-67至6-69；`conditional_identity_proved`。

原页记录：文字允许多个独立微网，每个分量选根；边数式为N-1-sum beta，虚拟流对所有节点使用beta。

项目处理：采用R7-A6前明确定义全部根是否计入beta；虚拟流是无量纲连通性工具，不直接沿用物理S容量。三节点森林穷举核查边数，当前不认证完整原模型。

### R7-C06

PDF109、115–116；6-26、6-28、6-73、6-83、6-84、6-88；`port_convention_requires_explicit_adopted_model`。

原页记录：源端口m为正、荷端口以-m计热；后简化6-84直接用m乘正温差，6-73为入流减出流。

项目处理：采用版拟分开非负源注入与负荷取流，并写入流+源=出流+荷；不对负荷有符号m套正向温差包络。源/荷和两网络方向需一同定义，尚未进入调度。

### R7-C07

PDF115–116；6-76至6-90；`energy_datum_and_units_derived`。

原页记录：容量按温差算，E下界为0；6-87用E除热容作绝对平均温度，6-90却由绝对管温初始化；6-78/79未显式写Delta t。

项目处理：采用R7-A3/A4统一相对下限显热和MWh；原式继续保留。线性等效水箱不认证各节点温度、停留时间、水压或双向水力。

### R7-C08

PDF116；6-88、6-89；`approximation_boundary_derived`。

原页记录：循环换热以平均供回温差和总循环流量表达，再在参考点作一阶展开。

项目处理：分别登记网络集总近似与一阶展开；R7-A5给精确余项。参考温度和流量须来自输入，不能用优化结果倒推参考值。

### R7-C09

PDF118；外层2.b/2.d，既有Q06；`adopted_contract_proved_algorithm_pending`。

原页记录：通过设I_s=1，但全部I_s=0时停止。每次MP更新后未明确旧事件标志失效机制。

项目处理：采用R7-A9的版本绑定证书；解析两事件反例证实仅改0/1仍不足。采用逻辑可继续开发，作者实际源码行为未知。

### R7-C10

PDF117、119；6-95、6-105至6-111；`dual_sign_counterexample_and_derivation`。

原页记录：紧凑约束Kr<=b且r属于R，所给对偶使用pi>=0及K^T pi>=f。

项目处理：从实际原始约束逐行构建R7-A7；min r s.t. -r<=-2的解析值为2，而字面正乘子约束不可行。固定整数后才能用LP对偶，变量界不能漏行。

### R7-C11

PDF119；内层步骤2.a–2.c；`bound_direction_proved_nested_algorithm_pending`。

原页记录：固定故障的最小恢复目标写入UB；部分恢复模式的最大化主问题写入LB，然后UB<=LB+sigma停止。

项目处理：按R7-A8重建界的方向，已求故障最小化下界用于最坏失供下界；受限模式最大化松弛的有效界用于上界。三故障两模式表构造了过早停止的解析反例。

### R7-C12

PDF119；6-109乘积的BigM说明；Zhao-Zeng作者预印本PDF6–9；`implementation_prerequisite_open`。

原页记录：论文提出对二值故障与对偶乘积采用BigM，但本页未提供有限乘子界。

项目处理：先做有限故障穷举基准；不能从一次求解得到的乘子最大值定义通用界。逐个固定恢复模式可能不可行，不直接套需要完全补救的KKT重构。后续强对偶、无界射线及SOS1路线各自核查。

## 独立参考

- [MOI-duality](https://jump.dev/MathOptInterface.jl/stable/background/duality/)：最小化LP不等式方向、自由变量及乘子符号的独立核对。查阅日期2026-09-19。
- [Zhao-Zeng-2012](https://optimization-online.org/wp-content/uploads/2012/01/3310.pdf)：2012年作者预印本，PDF6–9：整数补救、内层上下界及两种重构的条件；未认定其就是论文某条参考文献。查阅日期2026-09-19。
