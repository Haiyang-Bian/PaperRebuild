# R7有损输运：方程与符号

<!-- generated: r7-lossy-flow -->

正向与停流的有损连续质量输运；时段平均节点、固定正常电拓扑；原反向控制域尚未接入。

沿已经登记的局部热守恒参考R7-P1/P3/P4推导。Gauss积分为项目数值选择，不是作者节点法(6-42)或其后紧凑MILP；未重新宣称核清全部原式。NIST给积分余项，模型最优界只属于声明积分模型。

参考推导见[逐管参考](ch06-pipe-equations.md)。

## R7-H1

~~~math
\frac{\mathrm d\theta}{\mathrm dt_h}=-\lambda(\theta-a_t),\quad \lambda=\frac{3600UA}{c_wM},\quad \beta_t=\lambda\Delta t_h,\quad q_t=\frac{3600m_t\Delta t_h}{M}
\tag{R7-H1}
~~~

以整管质量归一化输运量，温度统一线性归一化；t_h用h，UA为整管W/K、c_w用J/(kg K)、M用kg。λ是每小时衰减率。每步流率、环境与入口温度恒定，停流仍散热；没有管壁热容和轴向导热。

API：[`add_r7_lossy_mass_transport!`](@ref)。测试：`test/r7_lossy_mass.jl` / `R7-H1/H2 lossy mass coordinates and independent parcels`。

## R7-H2

~~~math
C_t=\sum_{k=1}^{t}q_k,\quad I_t^{\rm out}=[C_{t-1}-1,C_t-1],\quad I_t^{\rm keep}=[C_t-1,C_t],\quad q_j u=\operatorname{clip}(z;C_{j-1},C_j)-C_{j-1},\quad 0\le u\le1
\tag{R7-H2}
~~~

每个出生水团与流出/保留质量区间求精确交集。分别在各自区间上裁剪端点，以避免空交集被错误要求两区间相交。q_j=0时不除以流量，u可不唯一，但交集质量为零、能量贡献也为零。初始空间段按负质量标签登记，不能重新设灾时均温。

API：[`add_r7_lossy_mass_transport!`](@ref)。测试：`test/r7_lossy_mass.jl` / `R7-H1/H2 lossy mass coordinates and independent parcels`。

## R7-H3

~~~math
\theta_j(z,t)=B_{j,t}+(\theta_j^{\rm in}-a_j)e^{-\lambda(t-t_{j-1})+\beta_j u(z)},\quad \theta_j^{\rm out}(z)=a_t+(B_{j,t-1}-a_t)e^{-\beta_t v(z)}+(\theta_j^{\rm in}-a_j)e^{-\lambda(t_{t-1}-t_{j-1})+\beta_j u(z)-\beta_t v(z)}
\tag{R7-H3}
~~~

第一式在步末时刻使用，B是分段环境温度的已知递推；第二式用于此前进入的水团，v是离开时刻在当前步的比例。当前步进入并流出的水团另用a_t+(θ_in-a_t)exp[β_t(u-v)]。初态常温段直接按其存留时间冷却。对交集质量积分得到平均出口和库存，不能用所有水团乘同一个全步衰减。

API：[`add_r7_lossy_mass_transport!`](@ref)。测试：`scripts/test_r7_lossy_mass_gurobi.jl` / `R7-H3 actual flow decision against analytic transport`。

## R7-H4

~~~math
\left|\int_0^1e^{A+Du}\,\mathrm du-\sum_{i=1}^{n}w_i e^{A+Du_i}\right|\le\frac{(n!)^4 e^{\max(A,A+D)}|D|^{2n}}{(2n+1)[(2n)!]^3}
\tag{R7-H4}
~~~

由NIST Gauss余项在[0,1]推导；使用5/10点正权重。实现以最大每步β和全温区跨度给保守单位质量温度误差界，正常/联合规格预先限定不超过1e-10归一化温度。此界只覆盖解析求积截断，浮点、优化及网络误差仍须独立水团回放检验；不放宽A1。

API：[`r7_loss_quadrature_bound`](@ref)。测试：`test/r7_lossy_mass.jl` / `R7-H4 quadrature contract and nonlinear type`。

## R7-H5

~~~math
\Delta t_h\left(\sum_g H_{g,t}-\sum_j H^{\rm delivered}_{j,t}\right)=\Delta E^S_t+\Delta E^R_t+Q^{\rm loss}_t
\tag{R7-H5}
~~~

整网强化必须加入供回水各自散热，不能继续使用无损恒等式。建模损耗由同一采用积分的能量差表达；验证器另以独立水团实际停留时间积分散热，因此不会用平衡式自证。电池原和式域与逐时互斥域显式选择，界只属于采用积分模型。

API：[`build_r7_flow_planning`](@ref)。测试：`test/r7_lossy_flow.jl` / `R7-H5 integrated loss and exclusive batteries`。

## R7-H6

~~~math
C=100E^{\rm el}+(20-100)(E^{\rm heat}+Q^{\rm loss})+C^{\rm BES}+C^{\rm start}=192-80Q^{\rm loss}+C^{\rm BES}+C^{\rm start}
\tag{R7-H6}
~~~

仅用于冻结合成例的正常期费用恒等式：热电比1、CHP20与平购电100 USD/MWh、理想电池、各管库存和电量周期、电网采用无有功损耗表示；期望电负荷3.2与热负荷1.6 MWh。Q_loss为概率加权正常散热MWh，C_BES为吞吐费用。完整审计还保留原浮点库存差项，不裁剪成零。多散热在此模型中允许廉价CHP多发电替代购电，不能据此说一般热损耗有益。

API：[`validate_r7_flow_planning`](@ref)。测试：`scripts/check_r7_lossy_flow_audit.jl` / `R7-H5 independent heat/cost identity and scope`。

## 符号表

| ID | 符号 | 含义 | 单位 | Julia | 维度 |
|---|---|---|---|---|---|
| R7H-decay | ``\lambda,\beta_t`` | 由管道物性和实际步长确定的散热系数 | h^-1; 无量纲 | `decay_per_h / beta` | 每管侧 / 每时段 |
| R7H-fraction | ``u,v,C,q`` | 出生/离开步内比例、累计质量标签和流量积分 | 均以整管质量或步长归一化 | `in_l,in_r,out_l,out_r / cumulative / q` | 水团 × 查询时段 × 端点 |
| R7H-integration | ``B_{j,t},a_t,w_i,u_i`` | 环境响应、归一化环境温度、Gauss权重和节点 | 归一化温度；权重与节点无量纲 | `background / ambient / r7_gauss_unit` | 出生时段 × 查询时段；Gauss阶数 |
| R7H-cost | ``E^{\rm el},E^{\rm heat},Q^{\rm loss},C^{\rm BES},C^{\rm start}`` | 正常期电热需求、概率加权散热、电池吞吐费和启动费；仅用于冻结输入的费用恒等式 | 前三项MWh；后两项USD | `electric_load / heat_load / normal_loss_MWh / battery_cost_USD / startup_cost_USD` | 每项正常规划的时域与场景汇总 |
