# R7恢复采用式与符号

<!-- generated: r7-recovery -->

来自`docs/reading/ch06/recovery.toml`。原页PDF107–116，
本页只覆盖给定灾前状态的恢复子问题；不代替111式全覆盖。
此前[实施前解析台账](ch06-audit-equations.md)保持历史范围。

## R7-R1

~~~math
z_l=z_l^0(1-\gamma_l)+a_l^{\rm on}-a_l^{\rm off},\quad 0\le a_l^{\rm on}\le(1-z_l^0)(1-\gamma_l),\quad 0\le a_l^{\rm off}\le z_l^0(1-\gamma_l)
\tag{R7-R1}
~~~

自动故障断开不占主动操作预算；仅健康线路可以操作。原式中的关闭动作符号冲突另存于实施前审计。

原式：6-62、6-63；分类：`project correction with binary truth table, see audit Q03`。

实现：[`build_r7_recovery`](@ref)；`test/r7_recovery.jl`：`R7-network-direction and R7-hard-failure`。

## R7-R2

~~~math
\sum_lz_l=N-\sum_n\beta_n,\quad \sum_{l\in\delta^+(n)}f_l-\sum_{l\in\delta^-(n)}f_l=q_n-1,\quad |f_l|\le(N-1)z_l,\quad 0\le q_n\le N\beta_n
\tag{R7-R2}
~~~

所有节点均进入森林，每个分量一个具备显式成网资格的根；虚拟商品流无MW单位。没有合格根的孤立负荷节点在采用模型中不可行，未实现去电节点选择。根电压不额外固定。

原式：6-67、6-68、6-69；分类：`project root/forest interpretation`。

实现：[`build_r7_recovery`](@ref)；`test/r7_recovery.jl`：`R7-network-direction and R7-hard-failure`。

## R7-R3

~~~math
\left|v_i-v_j-\frac{r_lP_l+x_lQ_l}{S_{\rm base}v_{\rm ref}}\right|\le (v^{\max}-v^{\min})(1-z_l)
\tag{R7-R3}
~~~

v是电压幅值，绝非R4的平方量；断开后P/Q为零，两端电压不再被迫相等。M由已知电压范围推得。默认保留原文给定方向的非负P/Q；signed仅为显式项目扩展。

原式：6-21、6-23、6-24、6-25；分类：`project unit conversion and switch correction`。

实现：[`build_r7_recovery`](@ref)；`test/r7_recovery.jl`：`R7-network-direction and R7-hard-failure`。

## R7-R4

~~~math
m_j^{\rm src}-m_j^{\rm load}=\sum_{a\in\delta^+(j)}m_a-\sum_{a\in\delta^-(j)}m_a,\qquad m_j^{\rm src},m_j^{\rm load}\ge0
\tag{R7-R4}
~~~

源与荷取流使用不同非负变量，管道流允许反向且受灾前参考流变化界限制。热端口的比热系数采用J/(kg K)除以一百万得到MW。管流和端口流跨新能源场景共用。

原式：6-72、6-73、6-74、6-75、6-83、6-84；分类：`project source/load port interpretation`。

实现：[`build_r7_recovery`](@ref)；`test/r7_recovery.jl`：`R7-recovery-integration and R7-shared-scenarios`。

## R7-R5

~~~math
L_{\rm e}\ge0.6-0.2=0.4,\quad L_{\rm h}\ge0.4-7/30=1/6,\quad L\ge17/30\ {\rm MWh}
\tag{R7-R5}
~~~

唯一电线断开后CHP电出力为零，电池最多供0.2MWh，两箱初始显热共7/30MWh。存在达到下界的采用模型候选；不证明详细热网状态可实现。

原式：6-53、project synthetic hand case；分类：`synthetic analytic lower bound with attainable proxy-model witness`。

实现：[`solve_r7_recovery`](@ref)；`test/r7_recovery.jl`：`R7-recovery-hand and R7-fault-certificates`。

## 原式—实现—测试分组

### R7R-devices

CHP继承启停并调整出力；PV按灾害系数降额；储能继承初值、显式小时积分、恢复末值自由。保留原6-12充放功率和式界，不增加互斥；同时充放另列检查。正常运行最短启停和经济目标不在本接口。

来源：6-2:15, 6-56:61；测试：`R7-proxy-boundaries`。

### R7R-electric

事件期PCC断开，包括零内部故障。电网采用线性、无损、独立P/Q容量边界，不认证交流潮流。拓扑是事件级跨时段/场景共享。

来源：6-19:25, 6-50:54, 6-62:69；测试：`R7-network-direction and R7-hard-failure`。

### R7R-heat

沿用已审计的相对显热零点、时间积分和Taylor交换。供回水体积分开计量，两个集总水箱只用于同一连通热网；不支持热网自身故障。原6-88乘积误差单列，不强制归零。

来源：6-55, 6-72:90; prior adopted R7-A3/A4/A5；测试：`R7-recovery-integration and R7-shared-scenarios`。

### R7R-loss

目标为期望电热失供MWh。固定故障最小化可行值是该故障上界；完全故障覆盖的上界才能用于安全，单故障有效下界可用于反例。缺界保留未决，不以OPTIMAL字符串替代界。

来源：6-53; prior adopted R7-A7/A8/A9；测试：`R7-recovery-hand and R7-fault-certificates`。

## 符号权威表

变量数组遵循设备/节点、时间、场景顺序；事件拓扑和流量共享是显式限制。

| ID | 原符号 | 含义 | 类别 | 单位 | Julia字段 | 维度 |
|---|---|---|---|---|---|---|
| R7R-index | ``l,n,a,j,g,t,k,\omega`` | 电支路/节点、热管/节点、设备、时段、状态边界、新能源场景 | index | 1 | `l,n,a,j,g,t,k,w` | k=1:T+1; t=1:T; w=1:W |
| R7R-graph | ``\gamma_l,z_l,\beta_n,a_l^{\rm on},a_l^{\rm off},f_l,q_n`` | 给定故障、恢复通断、根、健康线路动作、虚拟商品流与供给 | fault parameter; integer and continuous variables | 1 | `gamma,z,beta,a_on,a_off,virtual,root_supply` | line or node; no time/scenario dimension |
| R7R-grid | ``P_{lt\omega},Q_{lt\omega},v_{nt\omega},P_{t\omega}^{\rm PCC},Q_{t\omega}^{\rm PCC}`` | 线性电支路有功、无功、电压幅值与断开的外部接入 | variable | MW / Mvar / pu | `P_line,Q_line,v,P_PCC,Q_PCC` | line or node x time x scenario; PCC=time x scenario |
| R7R-resource | ``P_{gt\omega},Q_{gt\omega},H_{gt\omega},P_{gt\omega}^{\rm ch},P_{gt\omega}^{\rm dis},E_{gk\omega}^{\rm BES}`` | 设备电热出力、充放电与电池边界能量；EB的P为耗电，注入时取负 | variable | MW / Mvar / MWh | `P,Q,H,P_ch,P_dis,E_BES` | device x time/state boundary x scenario |
| R7R-shed | ``P_{nt\omega}^{\rm shed},H_{jt\omega}^{\rm shed}`` | 由原失供比例乘名义负荷等价改写的失供功率 | variable | MW | `P_shed,H_shed` | electric/heat node x time x scenario |
| R7R-flow | ``m_{at},m_{jt}^{\rm src},m_{jt}^{\rm load}`` | 有向管流、非负源和负荷端口质量流率 | variable | kg/s | `m_pipe,m_source,m_load` | pipe or heat node x time; shared across scenarios |
| R7R-tanks | ``E_{k\omega}^{S},E_{k\omega}^{R},H_{t\omega}^{\rm CF},H_{t\omega}^{\rm loss,S},H_{t\omega}^{\rm loss,R}`` | 相对各侧温度下限的显热、循环交换、供回水散热 | variable | MWh / MW | `E_S,E_R,H_CF,H_loss_S,H_loss_R` | state boundary/time x scenario |
| R7R-parameters | ``\pi_\omega,\Delta t,c_w,\rho,V_a^S,V_a^R,UA_a^S,UA_a^R`` | 正概率、时间步、比热、密度、分别给定的供回水体积与传热能力 | parameter | 1 / h / J/(kg K) / kg/m3 / m3 / W/K | `probabilities,dt_h,c_J_kgK,rho_kg_m3,volume_S_m3,volume_R_m3,UA_S_W_K,UA_R_W_K` | scenario/scalar/pipe; input keys are ASCII |
