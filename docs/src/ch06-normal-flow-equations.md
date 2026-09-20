# R7连续流量：原式、推导与符号

<!-- generated: r7-normal-flow -->

连续正向无损正常调度；固定电拓扑与端口活动集合。不是完整有损/反向域，也未连接自由流量灾后安全规划。

## 原式 6-26

~~~math
\sum_g H_{g,t,\omega}=c_wm_{j,t}(\tau^{\mathrm S}_{j,t,\omega}-\tau^{\mathrm R}_{j,t,\omega})
\tag{6-26}
~~~

PDF 109页。原式设备集合包括该源CHP及EB。流量没有ω下标，热量与温度有；流量跨场景共享。采用版区分源出口与混合节点。MW换算c_J/1e6。

## 原式 6-31

~~~math
-\overline m_{jk}\le m_{jk,t}\le\overline m_{jk}
\tag{6-31}
~~~

PDF 109页。作者原域允许有符号管流。本节点只补正向连续分支；严格正下界是项目显式范围，不冒称覆盖原域。

## 原式 6-42

~~~math
J_{jk,t}=\exp\!\left[-\frac{\epsilon_{jk}L_{jk}}{c_w\rho_w A_{jk}L_{jk}}\left(\chi_{jk,t}+\frac12+\frac{S_{jk,t}-R_{jk,t}}{m_{jk,t-\chi_{jk,t}}\Delta T}\right)\right]
\tag{6-42}
~~~

PDF 109页。按原页保留散热与节点法驻留时间的表达；本批UA=0时J=1，不用本式替代连续有损传播，不认定完整节点法与塞流相同。

## R7-F1

~~~math
0<\underline m_{p,t}\le m_{p,t}\le\overline m_{p,t},\quad m^{\mathrm{src}}_{j,t}+\sum_{p\to j}m_{p,t}=m^{\mathrm{load}}_{j,t}+\sum_{j\to p}m_{p,t}
\tag{R7-F1}
~~~

流量按管道或节点×时段，共享所有可再生情景。源荷端口分别非负，正活动端口有明确正下界，闲置端口固定零。源荷位置、电拓扑、设备与原始空间温度不变。

分类：project_explicit_continuous_positive_subdomain。API：[`r7_normal_flow_spec`](@ref)。测试：`test/r7_normal_flow.jl` / `R7-F1 input domain and model classification`。

## R7-F2

~~~math
q_t=\frac{3600\Delta t\,m_t}{M},\quad C_t=\sum_{r=1}^tq_r,\quad\mathcal L([a,b],[c,d])=[b-c]_+-[a-c]_+-[b-d]_++[a-d]_+
\tag{R7-F2}
~~~

质量以整管质量归一化。初始空间y对应入流标签ξ=-y，后续区间入口标签为[C[r-1],C[r]]。出口在时段t排出[C[t-1]-1,C[t]-1]；末态保留[C[t]-1,C[t]]。交集是四个正部的恒等式，覆盖跨越多个入口区间与本步直接穿管。每个正部的有限M由变量界逐项推导。

分类：derived_exact_interval_identity。API：[`add_r7_mass_transport!`](@ref)。测试：`test/r7_normal_flow.jl` / `R7-F2 mass labels and independent replay`。

## R7-F3

~~~math
q_t\theta_t^{\mathrm{out}}=\sum_r\mathcal L([C_{t-1}-1,C_t-1],I_r)\theta_r,\quad e_{t+1}=\sum_r\mathcal L([C_t-1,C_t],I_r)\theta_r
\tag{R7-F3}
~~~

θ=(τ-τmin)/(τmax-τmin)，e是除以cM温区跨度后的相对热库存。r同时遍历原始空间段与已进入的水团。流量与温度乘积保留；不是McCormick松弛。给定分段恒定入口与零散热时精确；节点仍按整时间步平均混合，不认证任意连续节点动态。

分类：lossless_continuous_transport_reference_nonconvex_MIQCP。API：[`build_r7_normal_flow`](@ref)。测试：`scripts/test_r7_normal_flow_gurobi.jl` / `R7-F3 continuous flow nonconvex reference`。

## R7-F4

~~~math
\mathcal V=\{\text{flow bounds, mass balance, device/electric/pressure equations, parcel replay, cost}\}
\tag{R7-F4}
~~~

独立验证按保存的连续流量重新裁切水团，不读取优化的交集权重。数值条件案例只是复用旧验证器的载体，原输入哈希不变。原求解器目标/界属于显式连续域或固定域，灾后安全与完整原文域均未认证。

分类：independent_numerical_verification。API：[`validate_r7_normal_flow`](@ref)。测试：`test/r7_normal_flow.jl` / `R7-F4 budgets frozen values and independent equations`。

## R7-F5

~~~math
C\ge\lambda L^{\mathrm e}+(c_{\mathrm{CHP}}-\lambda)L^{\mathrm h}/r_{\mathrm{CHP}}
\tag{R7-F5}
~~~

仅有一台常热电比CHP及理想电池、平电价、零散热、正常电池和各管热库存周期恢复时，守恒固定CHP总发电及电池净充电。启动和吞吐费用非负，故得到下界。API只核验可行见证；scripts/audit_r7_normal_flow.jl核对前提并计算解析界，不能把解析界写成求解器新返回的界。分时电价拒绝套用。

分类：derived_conservation_bound_and_embedded_feasible_witness。API：[`validate_r7_normal_flow`](@ref)。测试：`scripts/check_r7_normal_flow_audit.jl` / `R7-F5 conservation lower bound and independent witness`。

## R7-F6

~~~math
\Delta t[\sum_gH_{g,t,\omega}-\sum_jH^{\mathrm D}_{j,t}]=\sum_{p,s\in\{\mathrm S,\mathrm R\}}(E_{p,t+1,\omega}^{s}-E_{p,t,\omega}^{s})
\tag{R7-F6}
~~~

无损各管显热收支相加，内部节点质量与焓流两两抵消，得到每时段整网能量恒等式。基准非线性模型已隐含该式，但松弛中未必保留强度。scripts/probe_r7_flow_balance.jl在独立60秒探针中显式添加；后续共同流量节点提供energy_balance=true显式选项，旧调用仍默认false，原九项记录不改写。此行不是新物理假设，不能把单例关闭界缺口写成论文规模速度优势。

分类：derived_redundant_energy_identity_independent_probe。API：[`build_r7_normal_flow`](@ref)。测试：`scripts/check_r7_flow_balance_probe.jl` / `R7-F6 redundant conservation formulation witness`。

## 符号表

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7-F-flow | ``m_{p,t},m^{\mathrm{src}}_{j,t},m^{\mathrm{load}}_{j,t}`` | 正向管流、源注入、负荷取流 | kg/s | `flow_values.pipe/source/load` | pipe/node × time; no scenario axis |
| R7-F-label | ``q_t,C_t,\xi,I_r`` | 归一化通过质量、累计质量、水团标签和标签区间 | 1 | `q / cumulative / outlet_weights / inventory_weights` | time or source interval |
| R7-F-state | ``\theta_t^{\mathrm{in/out}},e_t`` | 归一化入口/出口温度及整管相对显热；不是可回收供热量 | 1 | `theta_in / theta_out / inventory` | pipe × time × scenario |
