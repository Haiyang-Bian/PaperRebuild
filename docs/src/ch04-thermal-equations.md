# 稳态循环热网：公式与符号

由docs/reading/ch04/thermal.toml生成；全部T式为项目采用方程。

## R4-T1

~~~math
b_{ij,t}+b_{ji,t}\le u_{ij}^{VL},\qquad \underline m_{ij}b_{ij,t}\le m_{ij,t}\le\overline m_{ij}b_{ij,t}
\tag{R4-T1}
~~~

日阀门仍形成连通树；逐时运行方向至多一个，也可闲置。相对原式(4-48)等式，这是明确的项目边界变化。闭/闲置弧无输运，停流管内储热不在稳态状态中。

API：[build_r4_thermal](@ref PaperRebuild.build_r4_thermal)；测试：R4-T1。

## R4-T2

~~~math
m c_p\,{dT\over dx}=-U(T-T_a)\quad\Longrightarrow\quad T^{out}=T_a+(T^{in}-T_a)\exp\!\left(-{UL\over c_pm}\right),\quad L^H={c_pm(T^{in}-T^{out})\over10^6}
\tag{R4-T2}
~~~

UA=U乘长度，单位W/K，cp为J/(kg K)。正向运行时采用稳态单管传热解，供回水分别计算；reference对照则冻结UL(Tref-Ta)/10^6。

API：[r4_steady_pipe](@ref PaperRebuild.r4_steady_pipe)；测试：R4-T2。

## R4-T3

~~~math
\begin{aligned}H_{ij}^{in}&=c m_{ij}(S_i-R_{ij}^{out}),&H_{ij}^{out}&=c m_{ij}(S_{ij}^{out}-R_j),\\H_i^{src}&=c m_i^{src}(S_i^{src}-R_i),&H_i^{load}&=c m_i^{load}(S_i-R_i^{load}).\end{aligned}
\tag{R4-T3}
~~~

c=cp/10^6。管对的热量在相同空间截面定义，回水方向与供水相反；节点混合温度与设备端口出口温度分别建模。

API：[build_r4_thermal](@ref PaperRebuild.build_r4_thermal)；测试：R4-T3。

## R4-T4

~~~math
\begin{aligned}m_i^{src}+\sum_{p\to i}m_p&=m_i^{load}+\sum_{i\to p}m_p,\\m_i^{src}S_i^{src}+\sum_{p\to i}m_pS_p^{out}&=(m_i^{load}+\sum_{i\to p}m_p)S_i,\\m_i^{load}R_i^{load}+\sum_{i\to p}m_pR_p^{out}&=(m_i^{src}+\sum_{p\to i}m_p)R_i.\end{aligned}
\tag{R4-T4}
~~~

质量和双侧焓混合守恒；前向供水与反向回水各验一次。独立验算还以K检查加权平均，避免小流量掩盖温差。

API：[validate_r4_thermal](@ref PaperRebuild.validate_r4_thermal)；测试：R4-T4。

## R4-T5

~~~math
\underline m^{exp}=\max\!\left\{m_{floor},\max_{q\in\{S,R\}}{UL\over c_p\log[(\overline T_q-T_a)/(\underline T_q-T_a)]}\right\},\quad \underline m^{ref}=\max\!\left\{m_{floor},\max_q{UL(T_q^{ref}-T_a)\over c_p(\overline T_q-\underline T_q)}\right\}
\tag{R4-T5}
~~~

由最大入口/最小出口推导正流量必要下界，与显式运行下限取最大。温度带须高于环境，供温下界高于回温上界。若低于流量容量仍不代表混合可行。

API：[r4_thermal_min_flow](@ref PaperRebuild.r4_thermal_min_flow)；测试：R4-T5。

## R4-T6

~~~math
C=C^{resource}+C^{discomfort}+C^{grid}+C^{switch},\qquad P^{pump}=0\quad\hbox{(not modeled)}
\tag{R4-T6}
~~~

费用继承原集中资源/购电/不满意度/动作成本；内部支付抵消。本版本未建泵耗，固定流量时热方程为仿射，全部离散固定且电网SOCP才成为连续凸特例。

API：[solve_r4_thermal](@ref PaperRebuild.solve_r4_thermal)；测试：R4-T6。

## 符号

|稳定ID|原符号|Julia名称|含义与维度|单位|
|---|---|---|---|---|
|thermal_activity|``u_{ij}^{VL},b_{ij,t}``|u_H / u_H_arc|物理管阀门(管)，实际循环方向(方向弧×时段)；均为二进制|1|
|thermal_flow|``m_{ij,t},m_i^{src},m_i^{load}``|m_pipe / m_source / m_load|非负供回管对及端口质量流；管道或节点×时段|kg/s|
|thermal_node_T|``S_i,R_i,S_i^{src},R_i^{load}``|τ_S / τ_R / τ_source / τ_load|节点混合与源/荷端口温度；保存K，内部(T-273.15)/100|K|
|thermal_pipe_T|``S_{ij}^{out},R_{ij}^{out}``|τ_S_out / τ_R_out|供回管出口温度；未运行管的值仅占位，不代表储热|K|
|thermal_transfer|``U,L,c_p,\alpha``|U_W_mK / length_m / cp / attenuation|单位长度传热系数、长度、比热及指数衰减；辅助m_safe只避免停流除零|W/(m K), m, J/(kg K), 1|

## 边界与疑点

### R4-T-C01

阀门开与循环开启是否相同？

旧版等式/历史状态保留。新版本允许闲置，是显式准稳态运行假设，不冒称原论文已如此定义。

### R4-T-C02

停流时仍会散热，为什么不计连续输运损耗？

真实停流散热应从管内储热扣除；本版本没有该状态，只计算稳态运行流，明确不认证停流冷却/重启能量。不得解释为真实管道不散热。

### R4-T-C03

旁通是否可以消除零负荷叶节点冲突？

本批不静默加入旁通。源/荷端口正温差下限保留，闲置分支可以无循环；若系统要求持续循环，需要新旁通设备和相应容量/泵耗模型。

### R4-T-C04

热状态完善后是否仍是MISOCP？

流量温度双线性等式非凸，指数损耗更含非线性关系。保存实际MOI类型；仅在流量和离散量固定、采用电网锥形式时称连续SOCP。

### R4-T-C05

温度带和运行流量下限是否来自论文？

均为预先冻结的项目设定。默认复用上一批reference10温度带，流量floor=1e-4kg/s；派生的传热必要下界另行记录，不能事后为通过测试放宽。
