# R7灾前启停推导与符号

<!-- generated: r7-commitment -->

来源：`docs/reading/ch06/normal-prerequisites.toml`。灾前CHP约束块与正常热网类别核查；尚非完整灾前网络优化。

## 关键原式

### 原式6-6

~~~math
\sum_{t^{\prime}=t-T^{\rm ON}+1}^{t}\nu_{g,t^{\prime}}^{\rm CHP}\le1-u_{g,t}^{\rm CHP}
\tag{6-6}
~~~

PDF107：按扫描原式保留。ν在上一页被定义为启动；本式启动当期矛盾，不用于主实现。负时间下标还需要显式历史。

### 原式6-7

~~~math
\sum_{t^{\prime}=t-T^{\rm OFF}+1}^{t}\nu_{g,t^{\prime}}^{\rm CHP}\le1-u_{g,t-T^{\rm OFF}}^{\rm CHP}
\tag{6-7}
~~~

PDF107：按原式保留移位的u下标。本批没有仅凭外形判它必错；转移定义、首末历史与最短停机语义一起通过独立持续时长判据重建。

### 原式6-92

~~~math
\mathcal X=\{x\in\mathbb R^k\times\{0,1\}^m:Ax\le b\}
\tag{6-92}
~~~

PDF117：原文紧凑正常域。正常详细热网到此形式的固定量或线性化步骤尚未闭合，不用该记号替代实际约束类型检查。

## R7-N1

~~~math
u_t-u_{t-1}=\nu_t^{\rm on}-\nu_t^{\rm off},\quad \nu_t^{\rm on}+\nu_t^{\rm off}\le1,\quad (u_t,\nu_t^{\rm on},\nu_t^{\rm off})\in\{0,1\}^3
\tag{R7-N1}
~~~

启动定义恢复：从0到1才有启动，从1到0才有关停。即使启机费为零也成立。原6-6把启动ν的滑动和限制为1-u，在启动当期要求1≤0，与PDF106的定义矛盾。项目新增关停变量，不把它冒称原文符号。

原式：6-1、6-6、6-7；`derived_correction_with_literal_counterexample`。

实现：[`add_r7_chp_commitment!`](@ref)。

验证：`test/r7_commitment.jl` / `R7-N1 literal startup contradiction`。

## R7-N2

~~~math
\sum_{k=\max(1,t-U+1)}^t\nu_k^{\rm on}\le u_t,\quad \sum_{k=\max(1,t-D+1)}^t\nu_k^{\rm off}\le1-u_t,\quad U=\lceil T^{\rm ON}/\Delta t\rceil,\ D=\lceil T^{\rm OFF}/\Delta t\rceil
\tag{R7-N2}
~~~

启动后U个区间内不能关机，关机后D个区间内不能启动。U或D为零时和式为空。离散动作只发生在区间边界，非整倍小时上取整是这一离散语义的结果；不改变实际最短小时数。验证器逐段计时，与建模侧滑动和式独立。

原式：6-6、6-7；`derived_equivalent_dwell_time_formulation`。

实现：[`add_r7_chp_commitment!`](@ref)。

验证：`test/r7_commitment.jl` / `R7-N2 N3 N4 exhaustive dwell-time oracle`。

## R7-N3

~~~math
r_0=\left\lceil\frac{\max(0,T^{u_0}-a_0)}{\Delta t}\right\rceil,\qquad u_t=u_0\ (1\le t\le\min(T,r_0))
\tag{R7-N3}
~~~

a0为窗口前已持续的小时数，T^u0按初始状态选最短开/停时长。首时段不能默认满足历史义务；初始开机出力按同一场景传入。原文没有闭合窗口前历史，本条是项目边界补充。

原式：6-6、6-7；`explicit_initial_history_completion`。

实现：[`add_r7_chp_commitment!`](@ref)。

验证：`test/r7_commitment.jl` / `R7-N2 N3 N4 exhaustive dwell-time oracle`。

## R7-N4

~~~math
r_T=\max(0,T^{u_T}-a_T)
\tag{R7-N4}
~~~

carry_obligation允许时域结束时仍有最短开/停义务，并输出rT及末状态；后续窗口必须继承。complete_within_horizon额外要求rT=0。这两种末端规则均为显式项目选择，不能把窗口外时间视为已经运行，也不能从原电池周期条件推断CHP周期启停。

原式：6-6、6-7；`project_terminal_boundary_variants`。

实现：[`validate_r7_chp`](@ref)。

验证：`test/r7_commitment.jl` / `R7-N2 N3 N4 exhaustive dwell-time oracle`。

## R7-N5

~~~math
C^{\rm CHP}=c^{\rm SU}\sum_t\nu_t^{\rm on}+\Delta t\sum_\omega\pi_\omega\sum_t c^P P_{t,\omega}^{\rm CHP}
\tag{R7-N5}
~~~

设备块只返回CHP的费用表达式。cP按电功率计综合运行费，USD/MWh；启机费USD/次不再乘dt，也不按场景重复收费。原6-1可见项为cCHP*P，接页正文又解释电、热成本，采用口径显式为electric_equivalent，不静默加入未显示的热成本。R为MW/h，正常爬坡乘dt；SU/SD为一次边界允许变化MW。完整PCC/GT/RE/BES目标尚未连接。

原式：6-1、6-4、6-5；`adopted_cost_basis_and_time_unit_completion`。

实现：[`add_r7_chp_commitment!`](@ref)。

验证：`test/r7_commitment.jl` / `R7-N5 cost, stochastic sharing, ramping and units`。

## R7-N6

~~~math
u^{\rm event}_k=u_{t_s+k-1},\quad P^{\rm before}_\omega=P_{t_s-1,\omega}^{\rm normal}
\tag{R7-N6}
~~~

事件启停来自窗口内正常计划，首区间爬坡从上一正常区间末的同场景出力开始。ts=1使用输入历史。该接口只继承CHP，不认证电池/管温或完整灾前计划；原值哈希、场景顺序、时间步与输入身份同时返回。

原式：6-56、6-57、6-58、6-59、6-60；`checked_component_state_handoff`。

实现：[`r7_chp_event_boundary`](@ref)。

验证：`test/r7_commitment.jl` / `R7-N6 inherited CHP event boundary`。

## R7-N7

~~~math
H=0.0042m\Delta T,\quad H(1,40)=H(2,20)=0.168,\quad H(1.5,30)=0.189\ne0.168
\tag{R7-N7}
~~~

两个等热功率可行点的中点不满足原等式；数值单位为MW、kg/s、K。原正常热网包含双线性、二次和变流量输运关系，不能仅凭6-92写成Ax≤b就断言其等价为MILP。该反例只说明这些保留等式非线性/非凸，不证明完整正常问题一定不可行。

原式：6-26、6-28、6-33、6-34、6-37、6-38、6-41、6-42、6-92；`analytic_model_class_counterexample_no_network_implementation`。

验证：`test/r7_commitment.jl` / `R7-N7 nonlinear normal heat`。

## 原页与采用解释

### R7-NC01

PDF106–107，6-1至6-7。

原文：ν被定义为启动指示；6-6右端为1-u，缺少完整ν/u转移及窗口前历史。

采用：N1/N2重建启停逻辑，N3/N4显式历史/末端。保留字面不可行反例；只修复有确定语义依据的部分。

状态：`component_implemented_independent_dwell_time_tests`。

### R7-NC02

PDF109–110、116–117，6-26至6-46、6-89、6-92。

原文：6.2正常热网保留非线性关系；6.3.4明确把6.3.3恢复热网替换为双水箱，随后正常域写成混合整数线性紧凑形式。

采用：记录正常域所需线性化/固定参数条件尚未闭合。下一步保留正常详细网络基准；任何固定流量或双水箱正常规划都须新版本、声明新增假设并回代，不视为论文自动给出的等价模型。

状态：`normal_network_derivation_open_component_work_continues`。

### R7-NC03

PDF116，6-90。

原文：恢复初始热量来自正常管温乘体积，未在本页给出非均匀管温的空间平均定义。

采用：后续状态桥接必须使用有来源的逐管平均状态/温度剖面，不能直接把出口温度当作全管平均，也不能默认满热储。当前CHP桥接不解除此项。

状态：`thermal_state_handoff_pending`。

## 符号表

| ID | 原符号 | 含义 | 类别 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|---|
| r7n-status | ``u_t^{\rm CHP}`` | 跨场景共享的开机状态 | variable | 1 | `u_CHP[t]` | 时间；设备由spec.id区分 |
| r7n-start | ``\nu_t^{\rm CHP},\nu_t^{\rm on},\nu_t^{\rm off}`` | 原启动指示；项目区分启动/关停，关停变量为新增 | variable | 1 | `ν_on[t], ν_off[t] (ASCII: nu_on/nu_off)` | 时间，共享场景 |
| r7n-duration | ``T^{\rm ON},T^{\rm OFF},a_0,a_T,r_T`` | 最短时长、窗口前/末持续时间、末端剩余义务 | parameter/state | h | `min_on_h, min_off_h, previous_duration_h, terminal_duration_h, terminal_remaining_h` | 每设备 |
| r7n-output | ``P_{t,\omega}^{\rm CHP},Q_{t,\omega}^{\rm CHP},H_{t,\omega}^{\rm CHP}`` | 有功、无功、热功率 | variable | MW/Mvar/MW | `P_CHP[t,ω], Q_CHP[t,ω], H_CHP[t,ω]` | 时间×场景 |
| r7n-ramp | ``R^{\rm CHP},SU^{\rm CHP},SD^{\rm CHP}`` | 正常爬坡率与启停边界功率变化限额 | parameter | MW/h; MW; MW | `ramp_MW_h, startup_MW, shutdown_MW` | 每设备 |
| r7n-cost | ``c^{\rm SU},c^P,\pi_\omega,\Delta t`` | 启动费、按电出力计综合运行费、概率、区间时长 | parameter | USD; USD/MWh; 1; h | `startup_cost_USD, cost_P_USD_MWh, probabilities, dt_h` | 概率为场景向量，其余标量 |

## 理论对照

- [PyPSA-UC](https://docs.pypsa.org/latest/user-guide/optimization/unit-commitment/)：仅对照最短开停时长、首时段历史与爬坡语义；没有引入Python依赖或照搬其末端规则。查阅2026-09-20。
