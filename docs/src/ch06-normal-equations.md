# R7正常条件调度：方程、符号与边界

<!-- generated: r7-normal -->

权威来源：`docs/reading/ch06/normal-dispatch.toml`。给定正向管流、固定电拓扑的正常条件调度与事件状态连接；不是完整变流量灾前最优或嵌套C&CG。

## 原式6-14

~~~math
E_{g,t+1,\omega}^{\rm BES}-E_{g,t,\omega}^{\rm BES}=(\eta_g^{\rm BES,C}P_{g,t,\omega}^{\rm BES,C}-P_{g,t,\omega}^{\rm BES,D}/\eta_g^{\rm BES,D})\Delta t
\tag{6-14}
~~~

PDF108：E[t]是区间t开始状态；原6-15为E[1]=E[T+1]。原6-12为充放功率之和界，不能改称互斥。

## 原式6-26

~~~math
\sum_{g\in\mathcal G_j^{\rm CHP}}H_{g,t,\omega}^{\rm CHP}+\sum_{g\in\mathcal G_j^{\rm EB}}H_{g,t,\omega}^{\rm EB}=c_wm_{j,t}(\tau_{j,t,\omega}^{\rm S}-\tau_{j,t,\omega}^{\rm R})
\tag{6-26}
~~~

PDF109：原热功率含流量与温差乘积；给定流量后才对温度线性。采用MW版本显式把J/s除以1e6。

## 原式6-34

~~~math
\Phi_{j,t}^{\rm R}-\Phi_{k,t}^{\rm R}=\mu_{jk}(m_{jk,t})^2+\Phi_{jk,t}^{\rm val}
\tag{6-34}
~~~

PDF109：原页按此方向保留。项目用同一供水边i→j标识一对管，实际回水j→i，压降沿回水实际方向重写；原反向索引解释仍需全章一致核查。

## R7-D1

~~~math
C=\sum_g c_g^{\rm SU}\sum_t\nu_{g,t}^{\rm on}+\Delta t\sum_{t,\omega}\pi_\omega[\lambda_tP_{t,\omega}^{\rm PCC}+\sum_g c_g P_{g,t,\omega}+\sum_{g\in\mathcal G^{\rm BES}}c_g(P^{\rm ch}_{g,t,\omega}+P^{\rm dis}_{g,t,\omega})]
\tag{R7-D1}
~~~

期望正常费用，启动一次收费不再乘场景数或时长。非电池设备费用以各自声明电功率计；EB若有额外费用是项目参数，不称原6-1已给出。手算例无EB。CHP综合电当量费用沿用R7-N5。

原式：6-1、6-8、6-9、6-10、6-11；分类`unit_completion_and_explicit_cost_input`。

实现：[`build_r7_normal`](@ref)。测试：`test/r7_normal.jl` / `R7-D1 normal hand cost and physical energy`。

## R7-D2

~~~math
u^{\rm event}_{g,k}=u^{\rm normal}_{g,t_s+k-1},\quad P_g^{\rm before}=P_{g,t_s-1}^{\rm normal},\quad E_g^{\rm before}=E_{g,t_s}^{\rm normal},\quad \bar\tau_p^{\rm before}=M_p^{-1}\int_0^{M_p}\tau_p(y,t_s^-)\,dy
\tag{R7-D2}
~~~

功率取前一区间，电池E[t_s]取当前区间起点，管道完成t_s-1步后积分。t_s=1用显式原始边界；不跨场景平均、不把出口当空间均温。事件生成必须同时通过正常模型和连续输运回放。严格输入边界外至多8个Float64 ULP的尾差允许显式映射到同一声明界，原值/继承值/差值全部存档；不按A1带宽裁剪真实越界。

原式：6-4、6-5、6-14、6-60、6-61、6-90；分类`time_index_and_state_completion`。

实现：[`r7_normal_event`](@ref)。测试：`test/r7_normal.jl` / `R7-D2 battery and CHP event time`。

## R7-D3

~~~math
\Phi_i^{\rm S}-\Phi_j^{\rm S}=\mu_p^{\rm S}m_p^2+\Phi_p^{\rm val,S},\qquad\Phi_j^{\rm R}-\Phi_i^{\rm R}=\mu_p^{\rm R}m_p^2+\Phi_p^{\rm val,R}
\tag{R7-D3}
~~~

以供水i→j标识，回水反向；给定正流时水力等式为仿射。Pa与有限压力/阀门上界显式，归一化压力残差沿用无量纲A1。泵供压能力只由边界表达，没有泵电耗、温度依赖密度或水力动态。

原式：6-30、6-31、6-32、6-33、6-34、6-35、6-36；分类`physical_direction_and_finite_bound_completion`。

实现：[`build_r7_normal`](@ref)。测试：`test/r7_normal.jl` / `R7-D3 adopted directions and required inputs`。

## R7-D4

~~~math
\boldsymbol\tau_p^{\rm out}=A_p(\boldsymbol m)\boldsymbol\tau_p^{\rm in}+b_{p,\omega},\qquad\boldsymbol E_p=B_p(\boldsymbol m)\boldsymbol\tau_p^{\rm in}+e_{p,\omega}
\tag{R7-D4}
~~~

给定流量及初始温度分布后，连续平流散热是仿射温度算子。基准加单位脉冲提取矩阵，不计算最优值导数。验证器直接回放水团与独立热损耗，不读取系数矩阵。作者节点法版本另用恒流K/J作出口关系，库存仍注明连续参考；不一致时禁止事件桥接。

原式：6-39、6-40、6-41、6-42、6-43、6-44、6-45、6-46、6-90；分类`prescribed_flow_special_case_and_project_continuous_reference`。

实现：[`validate_r7_normal`](@ref)。测试：`test/r7_normal.jl` / `R7-D4 transport superposition and node difference`。

## R7-D5

~~~math
(\sum_{p\to j}m_p+m_j^{\rm src})\tau_j^{\rm S,mix}=\sum_{p\to j}m_p\tau_p^{\rm S,out}+m_j^{\rm src}\tau_j^{\rm src},\quad(\sum_{j\to p}m_p+m_j^{\rm load})\tau_j^{\rm R,mix}=\sum_{j\to p}m_p\tau_p^{\rm R,out}+m_j^{\rm load}\tau_j^{\rm load}
\tag{R7-D5}
~~~

源、荷端口分为非负量，避免将净负流率当混合权重。热源出口与混合供温不同，负荷出口与混合回温不同。源热为c m_src(T_src-T_Rmix)，负荷热为c m_load(T_Smix-T_load)。正常期不削负荷。

原式：6-16、6-26、6-28、6-30、6-37、6-38；分类`port_and_mixing_interpretation`。

实现：[`build_r7_normal`](@ref)。测试：`test/r7_normal.jl` / `R7-D5 failures budgets and frozen values`。

## R7-D6

~~~math
u_{1,2}=1\ \Longrightarrow\ P_{1,2}^{\rm CHP}\geq0.2\ {\rm MW},\qquad P_{1,2}^{\rm CHP}=0
\tag{R7-D6}
~~~

合成normal-hand案例中，第2小时PCC与唯一内部电线均断开，CHP孤岛没有电负荷/电池/消纳端。继承开启与最小出力和节点电力守恒冲突。四小时周期总热量2.52 MWh又超过少开一小时的2.4 MWh供热上界；此输入仅调正常启停无法消除冲突。该推导不是作者案例的不可行证明。

原式：6-3、6-16、6-18、6-19、6-60、6-61；分类`project_synthetic_infeasibility_witness`。

实现：[`r7_normal_event`](@ref)。测试：`scripts/test_r7_normal_evidence.jl` / `R7-D6 isolated committed CHP and saved evidence`。

## 原文与采用解释

### ND01

原文：PDF108采用线性电压幅值潮流；6-18根PCC简记不列根上设备；6-23出现开关z，6-24/25原页非负上下界不含z。

采用：固定连接树上所有节点统一守恒，PCC仅在根注入；闭合线路执行线性压降，断开备用线流量为零。有限PCC上下界显式。不开启正常重构，不把z语义尚未完整闭合记成已经证明原式错误。

状态：`fixed_topology_conditional_model_implemented_switch_semantics_open`。

### ND02

原文：PDF109原管流允许有符号，且正常温度输运/水力含非线性；6.3恢复阶段才采用双水箱。

采用：本子问题固定严格正向流量，允许连续参考的逐时变化；节点法只支持恒流。完整变流量/方向/正常拓扑优化仍待完成；模型MOI为MILP不证明原正常模型MILP。

状态：`conditional_block_implemented_full_normal_domain_open`。

### ND03

原文：PDF108原电池E[1]=E[T+1]；本批核查页未给出正常管库存周期等式。

采用：电池保留原周期边界。热末端free/pipe_inventory_initial为显式项目对照，后者只固定每管供回相对库存，不证明整管温度分布周期恢复。

状态：`explicit_project_boundary`。

### ND04

原文：原6-90仅给单一管温初始化恢复库存，未在该式闭合空间积分。

采用：用原正常轨迹的水团分布积分，保留全部分段温度/质量和父结果哈希；恢复模型仍为已声明Taylor双水箱，不将源状态核算通过当作灾后详细热网认证。

状态：`conditional_state_handoff_implemented_recovery_abstraction_retained`。

## 符号表

| ID | 数学符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7-D-cost | ``C,\lambda_t,c_g`` | 正常期望费用、PCC电价、设备电功率计费系数 | USD; USD/MWh | `solver_objective_USD / price_USD_MWh / cost_P_USD_MWh` | scalar; T; device |
| R7-D-state | ``E^{\rm BES}_{g,t,\omega},E^{\rm S/R}_{p,t,\omega}`` | 区间起点电池能量、管道相对侧别最低温度的显热 | MWh | `E_BES / E_pipe_S / E_pipe_R` | device or pipe × (T+1) × scenario |
| R7-D-temperature | ``\tau^{\rm S,mix},\tau^{\rm R,mix},\tau^{\rm src},\tau^{\rm load},\tau_p^{\rm out}`` | 供回水混合、源出口、荷出口及管出口平均温度 | K | `τ_S / τ_R / τ_source / τ_load / τ_pipe_S / τ_pipe_R` | node or pipe × T × scenario |
| R7-D-flow | ``m_p,m_j^{\rm src},m_j^{\rm load}`` | 给定正向管流和非负源荷端口流；跨场景共用 | kg/s | `normal_flow_kg_s / source_flow_kg_s / load_flow_kg_s` | pipe or node × T |
| R7-D-pressure | ``\Phi_j^{\rm S},\Phi_j^{\rm R},\Phi_p^{\rm val},\mu_p`` | 压力、非负阀门压降和平方流阻系数；物理方向分开 | Pa; Pa s²/kg² | `Φ_S / Φ_R / Φ_val_S / Φ_val_R / mu_S_Pa_s2_kg2 / mu_R_Pa_s2_kg2` | node or pipe × T; pipe |
