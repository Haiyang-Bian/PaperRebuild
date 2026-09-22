# R7管内状态参考推导与符号

<!-- generated: r7-pipe-state -->

整管相对显热的独立输运参考；尚未连接完整灾前网络或认证灾后可回收量。

## 原式6-90

~~~math
E^{S/R}_{t^\prime,\omega,s}=c_w\rho_w\sum_{(j,k)\in\mathcal C}\left(A_{jk}L_{jk}\tau^{S/R}_{jk,\omega,t^\prime}\right),\quad t^\prime=t_s-1
\tag{6-90}
~~~

PDF116按原式保留。式中单一管温怎样由沿管分布得到未在本页闭合。前文平均温度/体积关系和能量守恒支持使用空间质量平均；项目相对下限的能量零点另作显式转换。

## R7-P1

~~~math
\partial_t\tau+m\partial_y\tau=-k(\tau-\tau^{\rm AM}),\quad 0\le y\le M,\quad M=\rho AL,\quad k=\frac{UA}{c_wM}
\tag{R7-P1}
~~~

以从左端累计水质量y作为空间坐标，流率m可正、负或零。t使用秒，UA为整根管道的W/K，不是单位长度传热系数。由局部热守恒推导的项目参考；不将其称为论文离散散热式。

实现：[`r7_pipe_step`](@ref)；测试：`test/r7_pipe_state.jl` / `R7-P3/P4 exact advection and independently integrated heat loss`。

## R7-P2

~~~math
\bar\tau=\frac1M\int_0^M\tau(y)\,\mathrm dy,\qquad E^{\rm ref}=\frac{c_w}{3.6\times10^9}\int_0^M[\tau(y)-\tau^{\rm ref}]\,\mathrm dy
\tag{R7-P2}
~~~

质量kg、比热J/(kg K)、温度K，E单位MWh。供回水各自计算、各计一次；参考温度显式。这个显热积分不保证全量可用于满足灾后热负荷。

实现：[`r7_pipe_inventory`](@ref)；测试：`test/r7_pipe_state.jl` / `R7-P1/P2 spatial state and inventory`。

## R7-P3

~~~math
\tau(a)=\tau^{\rm AM}+[\tau(0)-\tau^{\rm AM}]e^{-ka},\qquad \bar\tau^{\rm out}=\frac1{|m|\Delta t_s}\int_{\rm out}\tau_{\rm exit}\,\mathrm dM
\tag{R7-P3}
~~~

沿水团轨迹解析冷却，按实际迁移质量切割温度段。出口为本时间步流出质量的平均温度，不是步末端点值。新进入水团的留管时间各异，不能一律乘全步衰减。停流没有流出平均温度，返回nothing。

实现：[`r7_pipe_step`](@ref)；测试：`test/r7_pipe_state.jl` / `R7-P3/P4 exact advection and independently integrated heat loss`。

## R7-P4

~~~math
E_{t+1}-E_t=E^{\rm in}-E^{\rm out}-E^{\rm loss},\quad E^{\rm loss}=\frac{c_w}{3.6\times10^9}\int_{\rm parcels}(\tau_{\rm enter}-\tau^{\rm AM})(1-e^{-ka})\,\mathrm dM
\tag{R7-P4}
~~~

损耗逐水团按实际留管时间独立积分，再检查总能量平衡，避免用平衡式倒推损耗后自证。环境较热时允许负损耗。常边界下整步与分步应得到相同状态、出口积分和散热。

实现：[`r7_pipe_step`](@ref)；测试：`test/r7_pipe_state.jl` / `R7-P3/P4 exact advection and independently integrated heat loss`。

## 采用假设

- 不可压缩水和恒定比热密度
- 均匀截面及沿管均匀传热系数
- 每步流率、环境与入口温度恒定
- 无管壁热容和轴向导热
- 给定流量，不求水力与网络混合

## 符号

|ID|符号|含义|单位|Julia|
|---|---|---|---|---|
|R7-P-y|``y,M``|空间累计水质量、总管存水质量；项目坐标|kg|`mass_coordinate_kg / mass_kg`|
|R7-P-temperature|``\tau(y,t),\bar\tau,\tau^{\rm ref}``|沿管温度、质量平均温度、显热参考温度|K|`r7_pipe_temperature / mean_K / reference_K`|
|R7-P-flow|``m``|以左到右为正的质量流率；反向能力仅属于本参考核|kg/s|`mass_flow_kg_s`|
|R7-P-time|``\Delta t_s,a``|时间步秒数、水团本次留管时长；输入dt_h先乘3600|s|`D / transit`|
|R7-P-heat-coefficients|``c_w,UA,k``|水比热、整管传热、指数冷却率；原kJ须先转换J|J/(kg K); W/K; 1/s|`cp_J_kgK / UA_W_K / k`|
|R7-P-energy|``E^{\rm ref},E^{\rm in},E^{\rm out},E^{\rm loss}``|相对显热及本时间步能量积分|MWh|`relative_heat_MWh / input_heat_MWh / output_heat_MWh / loss_MWh`|

## 外部对照

[作者预印本v2，非论文所引期刊版](https://arxiv.org/pdf/1711.02274)：第3节按流出水质量平均温度，以及离散节点法/WMM散热区别的对照；未将本项目连续参考冒称该算法等价实现；查阅2026-09-20。
