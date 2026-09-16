```@raw html
<!-- GENERATED: scripts/ch02_docs.jl; edit docs/reading/ch02 and current Julia sources. -->
```

# [符号权威表](@id ch02-symbols)

分组列出，避免宽表挤压。每个稳定 ID 可单独链接。公式引用见 [逐式索引](@ref ch02-generated)。

### [时段和集合](@id symbol-time_index)

```math
t,\mathcal T
```

- ID / ASCII 别名：`time_index` / `time_index`
- 类别：index；上下标：时段下标；状态另用 0:T。
- 单位：h / 1；定义域：t=1:T; 状态0:T。
- Julia / 配置映射：`t, T, Δt`；维度：标量。
- 来源 PDF 页：14;32;43；状态：`visual_checked_with_scope_notes`。

### [CHP 发电功率](@id symbol-P_CHP)

```math
P_t^{CHP}
```

- ID / ASCII 别名：`P_CHP` / `P_CHP`
- 类别：variable；上下标：CHP 类别；t 时段。
- 单位：MW；定义域：非负且受界。
- Julia / 配置映射：`P_CHP`；维度：T。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [CHP 产热功率](@id symbol-H_CHP)

```math
H_t^{CHP}
```

- ID / ASCII 别名：`H_CHP` / `H_CHP`
- 类别：variable；上下标：CHP 类别；t 时段。
- 单位：MW；定义域：非负且受界。
- Julia / 配置映射：`H_CHP`；维度：T。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [发电效率](@id symbol-eta_G)

```math
\eta_t^G,\eta^G
```

- ID / ASCII 别名：`eta_G` / `eta_G`
- 类别：parameter；上下标：t 表示变效率；无 t 为作者近似。
- 单位：1；定义域：0<η≤1。
- Julia / 配置映射：`η_G; chp_efficiency`；维度：标量/函数。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [CHP 燃料能量损耗比例](@id symbol-eta_loss)

```math
\eta^{loss}
```

- ID / ASCII 别名：`eta_loss` / `eta_loss`
- 类别：parameter；上下标：loss 描述性上标。
- 单位：1；定义域：0≤η; η_G+η_loss≤1。
- Julia / 配置映射：`η_loss`；维度：标量。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [效率三次多项式系数](@id symbol-alpha_CHP)

```math
\alpha_0,\alpha_1,\alpha_2,\alpha_3
```

- ID / ASCII 别名：`alpha_CHP` / `alpha_CHP`
- 类别：parameter；上下标：0:3 为次数。
- 单位：1；定义域：实数。
- Julia / 配置映射：`α`；维度：4；Julia α[1] 对应 α_0。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [电出力上下界](@id symbol-P_CHP_bounds)

```math
\underline P^{CHP},\overline P^{CHP}
```

- ID / ASCII 别名：`P_CHP_bounds` / `P_CHP_bounds`
- 类别：parameter；上下标：下横线下界，上横线上界。
- 单位：MW；定义域：0≤min≤max。
- Julia / 配置映射：`P_CHP_min, P_CHP_max`；维度：标量；配置 devices。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [热出力上下界](@id symbol-H_CHP_bounds)

```math
\underline H^{CHP},\overline H^{CHP}
```

- ID / ASCII 别名：`H_CHP_bounds` / `H_CHP_bounds`
- 类别：parameter；上下标：下/上横线。
- 单位：MW；定义域：0≤min≤max。
- Julia / 配置映射：`H_CHP_min, H_CHP_max`；维度：标量；配置 devices。
- 来源 PDF 页：30；状态：`visual_checked_with_scope_notes`。

### [光伏实际调度功率](@id symbol-P_PV)

```math
P_t^{PV}
```

- ID / ASCII 别名：`P_PV` / `P_PV`
- 类别：variable；上下标：PV 类别。
- 单位：MW；定义域：0≤P≤可用值。
- Julia / 配置映射：`P_PV`；维度：T。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [光伏可用功率](@id symbol-P_PV_available)

```math
\overline P_t^{PV}
```

- ID / ASCII 别名：`P_PV_available` / `P_PV_available`
- 类别：parameter；上下标：上横线为天气可用界。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`P_PV_available`；维度：T；显式外部输入。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [光伏降额因子](@id symbol-f_PV)

```math
f^{PV}
```

- ID / ASCII 别名：`f_PV` / `f_PV`
- 类别：parameter；上下标：类别。
- 单位：1；定义域：[0,1]。
- Julia / 配置映射：`f_PV`；维度：标量。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [PV/WT 额定功率（各自作用域）](@id symbol-P_rated)

```math
P^{rated},P_r
```

- ID / ASCII 别名：`P_rated` / `P_rated`
- 类别：parameter；上下标：rated/r 表额定。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`P_rated`；维度：标量。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [实际/标准辐照度](@id symbol-A_irradiance)

```math
A^{real},A^{STC}
```

- ID / ASCII 别名：`A_irradiance` / `A_irradiance`
- 类别：parameter；上下标：非管截面 A。
- 单位：kW/m²；定义域：实际≥0;标准>0。
- Julia / 配置映射：`A_real, A_STC`；维度：标量。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [PV 温度功率系数](@id symbol-alpha_power)

```math
\alpha^{power}
```

- ID / ASCII 别名：`alpha_power` / `alpha_power`
- 类别：parameter；上下标：power 描述性。
- 单位：1/K；定义域：实数；百分数除100。
- Julia / 配置映射：`α_power`；维度：标量。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [组件温度与标准温度](@id symbol-tau_PV)

```math
\tau,\tau^{STC}
```

- ID / ASCII 别名：`tau_PV` / `tau_PV`
- 类别：parameter；上下标：原文环境/电池板温度称谓需区分。
- 单位：K；定义域：>0；温差与°C同值。
- Julia / 配置映射：`τ, τ_STC`；维度：标量。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [风电可用/调度出力](@id symbol-P_WT)

```math
P^{WT}(v),P_t^{WT}
```

- ID / ASCII 别名：`P_WT` / `P_WT`
- 类别：variable；上下标：WT 类别。
- 单位：MW；定义域：原式可能负，调度禁用。
- Julia / 配置映射：`wind_ramp_paper; P_WT`；维度：标量/T=零。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [风速、切入、额定、切出速度](@id symbol-v_wind)

```math
v,v_{ci},v_r,v_{co}
```

- ID / ASCII 别名：`v_wind` / `v_wind`
- 类别：parameter；上下标：与电压平方 v 不同作用域。
- 单位：m/s；定义域：0≤ci<r<co。
- Julia / 配置映射：`v, v_ci, v_r, v_co`；维度：标量。
- 来源 PDF 页：31；状态：`visual_checked_with_scope_notes`。

### [电锅炉耗电](@id symbol-P_EB)

```math
P_t^{EB}
```

- ID / ASCII 别名：`P_EB` / `P_EB`
- 类别：variable；上下标：EB 类别。
- 单位：MW；定义域：[0,P_EB_max]。
- Julia / 配置映射：`P_EB`；维度：T。
- 来源 PDF 页：32；状态：`visual_checked_with_scope_notes`。

### [电锅炉产热](@id symbol-H_EB)

```math
H_t^{EB}
```

- ID / ASCII 别名：`H_EB` / `H_EB`
- 类别：variable；上下标：EB 类别。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_EB`；维度：T。
- 来源 PDF 页：32；状态：`visual_checked_with_scope_notes`。

### [电锅炉 COP 与电容量](@id symbol-COP_EB)

```math
COP^{EB},\overline P^{EB}
```

- ID / ASCII 别名：`COP_EB` / `COP_EB`
- 类别：parameter；上下标：COP=热/电比，不直接填百分值。
- 单位：1 / MW；定义域：COP>0;容量≥0。
- Julia / 配置映射：`COP_EB, P_EB_max`；维度：标量；配置 devices。
- 来源 PDF 页：32;16；状态：`visual_checked_with_scope_notes`。

### [热泵耗电](@id symbol-P_HP)

```math
P_t^{HP}
```

- ID / ASCII 别名：`P_HP` / `P_HP`
- 类别：variable；上下标：HP 类别。
- 单位：MW；定义域：[0,P_HP_max]。
- Julia / 配置映射：`P_HP`；维度：T。
- 来源 PDF 页：32；状态：`visual_checked_with_scope_notes`。

### [热泵产热](@id symbol-H_HP)

```math
H_t^{HP}
```

- ID / ASCII 别名：`H_HP` / `H_HP`
- 类别：variable；上下标：HP 类别。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_HP`；维度：T。
- 来源 PDF 页：32；状态：`visual_checked_with_scope_notes`。

### [热泵 COP 与电容量](@id symbol-COP_HP)

```math
COP^{HP},\overline P^{HP}
```

- ID / ASCII 别名：`COP_HP` / `COP_HP`
- 类别：parameter；上下标：COP 可大于1，不是效率损失。
- 单位：1 / MW；定义域：COP>0;容量≥0。
- Julia / 配置映射：`COP_HP, P_HP_max`；维度：标量；配置 devices。
- 来源 PDF 页：32;16；状态：`visual_checked_with_scope_notes`。

### [电池储存能量](@id symbol-E_BS)

```math
E_t^{BS}
```

- ID / ASCII 别名：`E_BS` / `E_BS`
- 类别：variable；上下标：t 状态边界；不是 SOC。
- 单位：MWh；定义域：[0,E_BS_max]。
- Julia / 配置映射：`E_BS`；维度：0:T；保存向量位置 t+1。
- 来源 PDF 页：14;32；状态：`visual_checked_with_scope_notes`。

### [电池充电功率](@id symbol-P_BS_ch)

```math
P_t^{BS,ch}
```

- ID / ASCII 别名：`P_BS_ch` / `P_BS_ch`
- 类别：variable；上下标：ch 充电。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`P_BS_ch`；维度：T。
- 来源 PDF 页：32；状态：`visual_checked_with_scope_notes`。

### [电池放电功率](@id symbol-P_BS_dis)

```math
P_t^{BS,dis}
```

- ID / ASCII 别名：`P_BS_dis` / `P_BS_dis`
- 类别：variable；上下标：dis 放电。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`P_BS_dis`；维度：T。
- 来源 PDF 页：32；状态：`visual_checked_with_scope_notes`。

### [电池充放效率](@id symbol-eta_BS)

```math
\eta^{BS,ch},\eta^{BS,dis}
```

- ID / ASCII 别名：`eta_BS` / `eta_BS`
- 类别：parameter；上下标：ch/dis 为方向。
- 单位：1；定义域：(0,1]。
- Julia / 配置映射：`η_BS_ch, η_BS_dis`；维度：标量；配置 eta_BS_ch/dis。
- 来源 PDF 页：17;32；状态：`visual_checked_with_scope_notes`。

### [电池互斥状态](@id symbol-z_BS)

```math
z^{BS}
```

- ID / ASCII 别名：`z_BS` / `z_BS`
- 类别：variable；上下标：原式无 t，下标不擅自补。
- 单位：1；定义域：{0,1}。
- Julia / 配置映射：`z_BS`；维度：标量/整个窗口。
- 来源 PDF 页：16;32；状态：`visual_checked_with_scope_notes`。

### [储能容量、初始值和功率界](@id symbol-storage_bounds)

```math
\overline E^{BS},\overline E^{HS},\overline P^{BS},\overline H^{HS}
```

- ID / ASCII 别名：`storage_bounds` / `storage_bounds`
- 类别：parameter；上下标：HS=原符号表TS；E0为显式项目输入。
- 单位：MWh / MW；定义域：非负，初值不超容量。
- Julia / 配置映射：`E_BS_max, E_HS_max, E_BS_initial, E_HS_initial, BS_power_max, HS_power_max`；维度：标量；配置 devices。
- 来源 PDF 页：16;32;33；状态：`visual_checked_with_scope_notes`。

### [热储存能量，同义别名](@id symbol-E_HS)

```math
E_t^{HS},E_t^{TS}
```

- ID / ASCII 别名：`E_HS` / `E_HS`
- 类别：variable；上下标：正文HS/符号表TS。
- 单位：MWh；定义域：[0,E_HS_max]。
- Julia / 配置映射：`E_HS`；维度：0:T；保存位置 t+1。
- 来源 PDF 页：14;33；状态：`visual_checked_with_scope_notes`。

### [充热功率](@id symbol-H_HS_ch)

```math
H_t^{HS,ch},H_t^{TS,ch}
```

- ID / ASCII 别名：`H_HS_ch` / `H_HS_ch`
- 类别：variable；上下标：HS/TS 同义。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_HS_ch`；维度：T。
- 来源 PDF 页：15;33；状态：`visual_checked_with_scope_notes`。

### [放热功率](@id symbol-H_HS_dis)

```math
H_t^{HS,dis},H_t^{TS,dis}
```

- ID / ASCII 别名：`H_HS_dis` / `H_HS_dis`
- 类别：variable；上下标：HS/TS 同义。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_HS_dis`；维度：T。
- 来源 PDF 页：15;33；状态：`visual_checked_with_scope_notes`。

### [热储能充放系数与每步存留率](@id symbol-eta_HS)

```math
\eta^{HS,ch},\eta^{HS,dis},\eta^{HS,loss}
```

- ID / ASCII 别名：`eta_HS` / `eta_HS`
- 类别：parameter；上下标：loss 按乘法存留率解释，非流失比例。
- 单位：1；定义域：ch/dis∈(0,1];loss∈[0,1]。
- Julia / 配置映射：`η_HS_ch, η_HS_dis, η_HS_loss`；维度：标量；耦合案例ch=dis=1。
- 来源 PDF 页：17;33；状态：`visual_checked_with_scope_notes`。

### [热储能互斥状态](@id symbol-z_HS)

```math
z^{HS}
```

- ID / ASCII 别名：`z_HS` / `z_HS`
- 类别：variable；上下标：无 t；整个窗口。
- 单位：1；定义域：{0,1}。
- Julia / 配置映射：`z_HS`；维度：标量。
- 来源 PDF 页：33；状态：`visual_checked_with_scope_notes`。

### [节点净有功注入](@id symbol-P_net)

```math
P^{net}
```

- ID / ASCII 别名：`P_net` / `P_net`
- 类别：expression；上下标：正号向网络注入。
- 单位：MW；定义域：实数。
- Julia / 配置映射：`P_net`；维度：节点2每时段的表达式。
- 来源 PDF 页：33；状态：`visual_checked_with_scope_notes`。

### [节点净无功注入](@id symbol-Q_net)

```math
Q^{net}
```

- ID / ASCII 别名：`Q_net` / `Q_net`
- 类别：expression；上下标：合成案例非发电设备单位功率因数。
- 单位：Mvar；定义域：实数。
- Julia / 配置映射：`-Q_D[t]`；维度：T；合成简化。
- 来源 PDF 页：33；状态：`visual_checked_with_scope_notes`。

### [按类型分类的设备集合](@id symbol-device_sets)

```math
\mathcal G^{GT},\mathcal G^{CHP},\mathcal G^{PV},\mathcal G^{WT},\mathcal G^{HP},\mathcal G^{BS},\mathcal G^{TS}
```

- ID / ASCII 别名：`device_sets` / `device_sets`
- 类别：set；上下标：g 设备索引，后续多设备时加第一维。
- 单位：1；定义域：有限集合。
- Julia / 配置映射：`本批各类至多1台，无 GT/WT`；维度：每类一台；未来[g,t]。
- 来源 PDF 页：14；状态：`visual_checked_with_scope_notes`。

### [支路首端有功/根购电](@id symbol-P_branch)

```math
P_{mn,t},P_t^{grid}
```

- ID / ASCII 别名：`P_branch` / `P_branch`
- 类别：variable；上下标：m→n；本批等于根购电。
- 单位：MW；定义域：本例非负；通用模型可反向。
- Julia / 配置映射：`P_grid`；维度：T；显式除 S_base_MVA 转标幺。
- 来源 PDF 页：15;34；状态：`visual_checked_with_scope_notes`。

### [支路首端无功/根无功](@id symbol-Q_branch)

```math
Q_{mn,t},Q_t^{grid}
```

- ID / ASCII 别名：`Q_branch` / `Q_branch`
- 类别：variable；上下标：m→n。
- 单位：Mvar；定义域：本例非负。
- Julia / 配置映射：`Q_grid`；维度：T。
- 来源 PDF 页：15;34；状态：`visual_checked_with_scope_notes`。

### [电压幅值平方](@id symbol-v_squared)

```math
v_m=V_m^2
```

- ID / ASCII 别名：`v_squared` / `v_squared`
- 类别：variable；上下标：不是风速 v。
- 单位：pu²；定义域：正；根=1。
- Julia / 配置映射：`v`；维度：T，节点2；根常量。
- 来源 PDF 页：15;34；状态：`visual_checked_with_scope_notes`。

### [电流幅值平方](@id symbol-l_squared)

```math
l_{mn}=I_{mn}^2
```

- ID / ASCII 别名：`l_squared` / `l_squared`
- 类别：variable；上下标：原符号表 I 释义误写电压，不能照用。
- 单位：pu²；定义域：[0,l_max_pu]。
- Julia / 配置映射：`l`；维度：T；不是 I。
- 来源 PDF 页：15;34；状态：`visual_checked_with_scope_notes`。

### [线路电阻/电抗](@id symbol-r_x)

```math
r_{mn},x_{mn}
```

- ID / ASCII 别名：`r_x` / `r_x`
- 类别：parameter；上下标：同一基值的标幺阻抗。
- 单位：pu；定义域：本例非负。
- Julia / 配置映射：`r_pu, x_pu`；维度：标量；Z_base=V_base_kV²/S_base_MVA Ω。
- 来源 PDF 页：17;34；状态：`visual_checked_with_scope_notes`。

### [电压电流平方界与项目基值](@id symbol-electric_bounds)

```math
\underline v,\overline v,\underline l,\overline l
```

- ID / ASCII 别名：`electric_bounds` / `electric_bounds`
- 类别：parameter；上下标：配置电压给幅值，代码实际平方。
- 单位：pu²; kV; MVA；定义域：正基值，有序界。
- Julia / 配置映射：`V_min_pu, V_max_pu, l_max_pu, V_base_kV, S_base_MVA`；维度：标量；配置 electric。
- 来源 PDF 页：34；状态：`visual_checked_with_scope_notes`。

### [电节点、线路、出边终节点集合](@id symbol-electric_sets)

```math
\mathcal N,\mathcal B,\Theta(m)
```

- ID / ASCII 别名：`electric_sets` / `electric_sets`
- 类别：set；上下标：m/n 为节点。
- 单位：1；定义域：本批节点[1,2]，边1→2。
- Julia / 配置映射：`nodes, from, to, root`；维度：固定索引；配置 electric。
- 来源 PDF 页：14;34;42；状态：`visual_checked_with_scope_notes`。

### [热源总注入](@id symbol-H_source)

```math
\sum H^{CHP}+\sum H^{HP}-H^{TS,ch}+H^{TS,dis}
```

- ID / ASCII 别名：`H_source` / `H_source`
- 类别：expression；上下标：项目显式加入EB。
- 单位：MW；定义域：由设备决定。
- Julia / 配置映射：`H_source`；维度：T。
- 来源 PDF 页：35；状态：`visual_checked_with_scope_notes`。

### [负荷节点从热网取热](@id symbol-H_D)

```math
h_j^D,H_t^D
```

- ID / ASCII 别名：`H_D` / `H_D`
- 类别：variable；上下标：原文 h/H 大小写别名。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_D`；维度：T。
- 来源 PDF 页：35;44；状态：`visual_checked_with_scope_notes`。

### [水的比热](@id symbol-c_w)

```math
c_w
```

- ID / ASCII 别名：`c_w` / `c_w`
- 类别：parameter；上下标：原式/符号表用kJ；热核转J。
- 单位：kJ/(kg K)；定义域：正，合成4.2。
- Julia / 配置映射：`c_w`；维度：标量。
- 来源 PDF 页：16;35；状态：`visual_checked_with_scope_notes`。

### [节点质量注入](@id symbol-m_node)

```math
m_j,m_k
```

- ID / ASCII 别名：`m_node` / `m_node`
- 类别：parameter；上下标：热源正，负荷负。
- 单位：kg/s；定义域：本批+m,-m。
- Julia / 配置映射：`m`；维度：标量，流量作为已给运行点。
- 来源 PDF 页：15;35;36；状态：`visual_checked_with_scope_notes`。

### [管道质量流率](@id symbol-m_pipe)

```math
m_{jk,t}
```

- ID / ASCII 别名：`m_pipe` / `m_pipe`
- 类别：parameter；上下标：供水1→2，回水2→1分别正向。
- 单位：kg/s；定义域：固定正值；不接受逆流。
- Julia / 配置映射：`m`；维度：标量，本批同流量供回水。
- 来源 PDF 页：15;36；状态：`visual_checked_with_scope_notes`。

### [节点供回水温度](@id symbol-tau_SR)

```math
\tau_j^S,\tau_j^R
```

- ID / ASCII 别名：`tau_SR` / `tau_SR`
- 类别：variable；上下标：S供水R回水，不是时间t。
- 单位：K；定义域：>0且受界。
- Julia / 配置映射：`τ_S_in, τ_S_out, τ_R_in, τ_R_out`；维度：T；保存键tau_*。
- 来源 PDF 页：15;35；状态：`visual_checked_with_scope_notes`。

### [供回水温度界](@id symbol-heat_bounds)

```math
\underline\tau^S,\overline\tau^S,\underline\tau^R,\overline\tau^R
```

- ID / ASCII 别名：`heat_bounds` / `heat_bounds`
- 类别：parameter；上下标：本例四端点统一界是附加假设。
- 单位：K；定义域：正且下界<上界。
- Julia / 配置映射：`tau_min, tau_max`；维度：标量；配置 heat。
- 来源 PDF 页：17;35；状态：`visual_checked_with_scope_notes`。

### [供回水压力与阀压降](@id symbol-Phi)

```math
\Phi_j^S,\Phi_j^R,\Phi_{jk}^{val}
```

- ID / ASCII 别名：`Phi` / `Phi`
- 类别：variable；上下标：S/R/val类型。
- 单位：kPa；定义域：非负。
- Julia / 配置映射：`未实现`；维度：节点/管道×时段。
- 来源 PDF 页：15;36；状态：`visual_checked_with_scope_notes`。

### [管阻系数](@id symbol-mu_hydraulic)

```math
\mu_{jk}
```

- ID / ASCII 别名：`mu_hydraulic` / `mu_hydraulic`
- 类别：parameter；上下标：与市场乘子 μ 不同。
- 单位：kPa/(kg/s)²；定义域：非负。
- Julia / 配置映射：`未实现`；维度：管道。
- 来源 PDF 页：36；状态：`visual_checked_with_scope_notes`。

### [节点与管道流量界](@id symbol-flow_bounds)

```math
\underline m_j,\overline m_j,\overline m_{jk}
```

- ID / ASCII 别名：`flow_bounds` / `flow_bounds`
- 类别：parameter；上下标：原式允许双向管流。
- 单位：kg/s；定义域：有序。
- Julia / 配置映射：`未实现`；维度：节点/管道。
- 来源 PDF 页：36；状态：`visual_checked_with_scope_notes`。

### [供回水压差界](@id symbol-pressure_bounds)

```math
\Delta\underline\Phi,\Delta\overline\Phi
```

- ID / ASCII 别名：`pressure_bounds` / `pressure_bounds`
- 类别：parameter；上下标：Δ 为差值操作。
- 单位：kPa；定义域：有序。
- Julia / 配置映射：`未实现`；维度：节点。
- 来源 PDF 页：36；状态：`visual_checked_with_scope_notes`。

### [节点混合温度](@id symbol-tau_mix)

```math
\tau_j^{S,mix},\tau_j^{R,mix}
```

- ID / ASCII 别名：`tau_mix` / `tau_mix`
- 类别：expression；上下标：按真实入流质量加权。
- 单位：K；定义域：总入流>0。
- Julia / 配置映射：`mix_temperature`；维度：输入支路向量→标量。
- 来源 PDF 页：15;37；状态：`visual_checked_with_scope_notes`。

### [管道入口出口温度](@id symbol-tau_in_out)

```math
\tau_{jk,t}^{S,in},\tau_{jk,t}^{S,out},\tau_{jk,t}^{R,in},\tau_{jk,t}^{R,out}
```

- ID / ASCII 别名：`tau_in_out` / `tau_in_out`
- 类别：variable；上下标：in/out为空间端点；S/R供回。
- 单位：K；定义域：受案例温度边界。
- Julia / 配置映射：`τ_in, τ_out; tau_S_in/out, tau_R_in/out`；维度：T；history最早→0。
- 来源 PDF 页：15;37；状态：`visual_checked_with_scope_notes`。

### [给定环境温度](@id symbol-tau_AM)

```math
\hat\tau_t^{AM}
```

- ID / ASCII 别名：`tau_AM` / `tau_AM`
- 类别：parameter；上下标：帽号外生；与建筑温度不同。
- 单位：K；定义域：>0。
- Julia / 配置映射：`τ_AM; tau_AM`；维度：建筑T，热管环境本批常数。
- 来源 PDF 页：17;37;43；状态：`visual_checked_with_scope_notes`。

### [水密度](@id symbol-rho_w)

```math
\rho_w
```

- ID / ASCII 别名：`rho_w` / `rho_w`
- 类别：parameter；上下标：与价格ρ区分作用域。
- 单位：kg/m³；定义域：>0。
- Julia / 配置映射：`ρ_w; rho_w`；维度：标量。
- 来源 PDF 页：37；状态：`visual_checked_with_scope_notes`。

### [管道横截面积](@id symbol-A_pipe)

```math
A_{jk}
```

- ID / ASCII 别名：`A_pipe` / `A_pipe`
- 类别：parameter；上下标：不是PV辐照度A。
- 单位：m²；定义域：>0。
- Julia / 配置映射：`A`；维度：标量。
- 来源 PDF 页：16;37；状态：`visual_checked_with_scope_notes`。

### [管道长度](@id symbol-L_pipe)

```math
L_{jk}
```

- ID / ASCII 别名：`L_pipe` / `L_pipe`
- 类别：parameter；上下标：与市场拉格朗日函数不同。
- 单位：m；定义域：>0。
- Julia / 配置映射：`L`；维度：标量。
- 来源 PDF 页：16;37；状态：`visual_checked_with_scope_notes`。

### [单位长度温差传热系数](@id symbol-epsilon_pipe)

```math
\epsilon_{jk}
```

- ID / ASCII 别名：`epsilon_pipe` / `epsilon_pipe`
- 类别：parameter；上下标：不得同概率风险ε混写。
- 单位：W/(m K)；定义域：≥0。
- Julia / 配置映射：`ε; epsilon_W_mK`；维度：标量。
- 来源 PDF 页：17;37；状态：`visual_checked_with_scope_notes`。

### [入口温度的质量权重](@id symbol-K)

```math
K_{t,\zeta}
```

- ID / ASCII 别名：`K` / `K`
- 类别：expression；上下标：t出口时段，ζ入口时段。
- 单位：1；定义域：非负；含历史总和1。
- Julia / 配置映射：`kernel.weights, kernel.lags`；维度：恒定流量只需两个非零权重。
- 来源 PDF 页：37；状态：`visual_checked_with_scope_notes`。

### [节点法热损耗衰减](@id symbol-J)

```math
J_t
```

- ID / ASCII 别名：`J` / `J`
- 类别：expression；上下标：无量纲因子。
- 单位：1；定义域：(0,1]。
- Julia / 配置映射：`kernel.J`；维度：恒定流量标量。
- 来源 PDF 页：37；状态：`visual_checked_with_scope_notes`。

### [两个回溯整数](@id symbol-psi_chi)

```math
\psi_t,\chi_t
```

- ID / ASCII 别名：`psi_chi` / `psi_chi`
- 类别：expression；上下标：分别不含/包含当前时段。
- 单位：时段数；定义域：整数≥0。
- Julia / 配置映射：`ceil(Int, delay), ceil(Int, delay)-1`；维度：恒流标量。
- 来源 PDF 页：38；状态：`visual_checked_with_scope_notes`。

### [回溯累计流过质量](@id symbol-R_S)

```math
R_t,S_t
```

- ID / ASCII 别名：`R_S` / `R_S`
- 类别：expression；上下标：不是供水S标记。
- 单位：kg；定义域：≥管内质量。
- Julia / 配置映射：`本批等于ceil(delay)*m*ΔT`；维度：标量等价推导，不独立变量。
- 来源 PDF 页：38；状态：`visual_checked_with_scope_notes`。

### [热网离散时间步长](@id symbol-DeltaT)

```math
\Delta T
```

- ID / ASCII 别名：`DeltaT` / `DeltaT`
- 类别：parameter；上下标：热核秒；储能Δt小时。
- 单位：s / h；定义域：>0。
- Julia / 配置映射：`ΔT=3600Δt`；维度：标量。
- 来源 PDF 页：37;38；状态：`visual_checked_with_scope_notes`。

### [市场机组出力及界](@id symbol-P_G_market)

```math
P^G,\underline P^G,\overline P^G
```

- ID / ASCII 别名：`P_G_market` / `P_G_market`
- 类别：variable；上下标：G集合，不是CHP效率G。
- 单位：MW；定义域：出力受界。
- Julia / 配置映射：`未实现`；维度：机组向量。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [市场负荷](@id symbol-P_D_market)

```math
P^D
```

- ID / ASCII 别名：`P_D_market` / `P_D_market`
- 类别：parameter；上下标：2-56总量，2-58节点向量，原文重名。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`未实现；后续显式sum`；维度：标量/节点向量。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [线路潮流与容量界](@id symbol-P_L_market)

```math
P^L,\underline P^L,\overline P^L
```

- ID / ASCII 别名：`P_L_market` / `P_L_market`
- 类别：variable；上下标：L线路类别。
- 单位：MW；定义域：实数。
- Julia / 配置映射：`未实现`；维度：线路向量。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [市场申报价格](@id symbol-rho_market)

```math
\rho
```

- ID / ASCII 别名：`rho_market` / `rho_market`
- 类别：parameter；上下标：不是密度ρ_w。
- 单位：货币/MWh；定义域：由报价机制定义。
- Julia / 配置映射：`未实现`；维度：机组向量。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [功率传输分布矩阵](@id symbol-PTDF)

```math
T
```

- ID / ASCII 别名：`PTDF` / `PTDF`
- 类别：parameter；上下标：不是时段总数T。
- 单位：1；定义域：实矩阵。
- Julia / 配置映射：`未实现；拟用T_PTDF`；维度：线路×节点。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [市场约束对偶乘子](@id symbol-dual_market)

```math
\lambda,\hat\mu,\tilde\mu,\hat\tau,\tilde\tau
```

- ID / ASCII 别名：`dual_market` / `dual_market`
- 类别：variable；上下标：τ形乘子非温度；公式清单待字形复核。
- 单位：货币/MWh；定义域：平衡自由，其余非负。
- Julia / 配置映射：`未实现`；维度：标量/线路/机组向量。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [节点边际价格](@id symbol-p_market)

```math
p_n
```

- ID / ASCII 别名：`p_market` / `p_market`
- 类别：expression；上下标：n节点。
- 单位：货币/MWh；定义域：实数。
- Julia / 配置映射：`未实现`；维度：节点向量。
- 来源 PDF 页：39；状态：`visual_checked_with_scope_notes`。

### [无向开关状态](@id symbol-u_SW)

```math
u_{mn,t}^{SW}
```

- ID / ASCII 别名：`u_SW` / `u_SW`
- 类别：variable；上下标：SW开关。
- 单位：1；定义域：本段需结合z解释。
- Julia / 配置映射：`未实现`；维度：边×时段。
- 来源 PDF 页：42；状态：`visual_checked_with_scope_notes`。

### [有向父边和初始状态](@id symbol-z_parent)

```math
z_{mn,t},\hat z_{mn,0}
```

- ID / ASCII 别名：`z_parent` / `z_parent`
- 类别：variable；上下标：与储能z分作用域。
- 单位：1；定义域：{0,1}。
- Julia / 配置映射：`未实现`；维度：有向边×时段。
- 来源 PDF 页：42；状态：`visual_checked_with_scope_notes`。

### [合闸动作辅助量](@id symbol-a_SW)

```math
a_{mn,t}^{SW}
```

- ID / ASCII 别名：`a_SW` / `a_SW`
- 类别：variable；上下标：不是完整动作次数等式。
- 单位：1；定义域：[0,1]。
- Julia / 配置映射：`未实现`；维度：有向边×时段。
- 来源 PDF 页：42；状态：`visual_checked_with_scope_notes`。

### [热节点、管道、相邻集合](@id symbol-heat_sets)

```math
\mathcal J,\mathcal C,\Xi(j)
```

- ID / ASCII 别名：`heat_sets` / `heat_sets`
- 类别：set；上下标：j/k 热节点。
- 单位：1；定义域：本批[1,2]供回各一管。
- Julia / 配置映射：`nodes, supply_from, return_from`；维度：配置 heat。
- 来源 PDF 页：14;43；状态：`visual_checked_with_scope_notes`。

### [阀门状态](@id symbol-u_VL)

```math
u_{jk}^{VL}
```

- ID / ASCII 别名：`u_VL` / `u_VL`
- 类别：variable；上下标：VL阀门，一天一次配置。
- 单位：1；定义域：由ν解释。
- Julia / 配置映射：`未实现`；维度：管道。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [热网有向父边与初态](@id symbol-nu_parent)

```math
\nu_{jk},\hat\nu_{jk,0}
```

- ID / ASCII 别名：`nu_parent` / `nu_parent`
- 类别：variable；上下标：希腊ν不是电压v。
- 单位：1；定义域：{0,1}。
- Julia / 配置映射：`未实现`；维度：管道。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [阀动作辅助量](@id symbol-a_VL)

```math
a_{jk}^{VL}
```

- ID / ASCII 别名：`a_VL` / `a_VL`
- 类别：variable；上下标：2-71印为mn待澄清。
- 单位：1；定义域：[0,1]。
- Julia / 配置映射：`未实现`；维度：管道。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [室内温度](@id symbol-tau_IN)

```math
\tau_t^{IN}
```

- ID / ASCII 别名：`tau_IN` / `tau_IN`
- 类别：variable；上下标：IN室内，t时段边界。
- 单位：K；定义域：舒适区间。
- Julia / 配置映射：`τ_IN; 保存键tau_IN`；维度：0:T。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [建筑总供热需求](@id symbol-H_D_hat)

```math
\hat H_t^D
```

- ID / ASCII 别名：`H_D_hat` / `H_D_hat`
- 类别：variable；上下标：帽号原文保留，本模型可调。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_D_hat`；维度：T。
- 来源 PDF 页：43;44；状态：`visual_checked_with_scope_notes`。

### [建筑离散供热增温系数](@id symbol-eta_H)

```math
\eta^H
```

- ID / ASCII 别名：`eta_H` / `eta_H`
- 类别：parameter；上下标：已包含参考步长；不同于效率η_DH。
- 单位：K/MW；定义域：>0。
- Julia / 配置映射：`η_H; 配置eta_H`；维度：标量。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [建筑离散散热系数](@id symbol-U_building)

```math
U_t
```

- ID / ASCII 别名：`U_building` / `U_building`
- 类别：parameter；上下标：若直接读为W/K则原式量纲不合。
- 单位：1；定义域：≥0。
- Julia / 配置映射：`U`；维度：标量；本批常值。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [舒适界与显式初始温度](@id symbol-building_bounds)

```math
\underline\tau^{IN},\overline\tau^{IN},\tau_0^{IN}
```

- ID / ASCII 别名：`building_bounds` / `building_bounds`
- 类别：parameter；上下标：原式没有末温回归条件。
- 单位：K；定义域：正、有序、初温在界内。
- Julia / 配置映射：`tau_min, tau_max, tau_initial`；维度：标量；配置 building。
- 来源 PDF 页：43；状态：`visual_checked_with_scope_notes`。

### [总电负荷](@id symbol-P_D)

```math
P_t^D
```

- ID / ASCII 别名：`P_D` / `P_D`
- 类别：expression；上下标：含电热；配置P_D为基础负荷。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`demand.P_D + P_DH`；维度：T。
- 来源 PDF 页：44；状态：`visual_checked_with_scope_notes`。

### [基础不可调电负荷](@id symbol-P_D_hat)

```math
\hat P_t^D
```

- ID / ASCII 别名：`P_D_hat` / `P_D_hat`
- 类别：parameter；上下标：帽号外生。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`demand.P_D`；维度：T；ASCII配置省帽需注意映射。
- 来源 PDF 页：44；状态：`visual_checked_with_scope_notes`。

### [户用电热耗电](@id symbol-P_DH)

```math
P_t^{D,H}
```

- ID / ASCII 别名：`P_DH` / `P_DH`
- 类别：variable；上下标：D,H负荷侧电热。
- 单位：MW；定义域：[0,P_DH_max]。
- Julia / 配置映射：`P_DH`；维度：T。
- 来源 PDF 页：44；状态：`visual_checked_with_scope_notes`。

### [户用电热产热](@id symbol-H_DH)

```math
H_t^{D,H}
```

- ID / ASCII 别名：`H_DH` / `H_DH`
- 类别：variable；上下标：D,H负荷侧。
- 单位：MW；定义域：非负。
- Julia / 配置映射：`H_DH`；维度：T。
- 来源 PDF 页：44；状态：`visual_checked_with_scope_notes`。

### [户用转换系数及电容量](@id symbol-eta_DH)

```math
\eta^{D,H},\overline P^{D,H}
```

- ID / ASCII 别名：`eta_DH` / `eta_DH`
- 类别：parameter；上下标：热/电比与容量。
- 单位：1 / MW；定义域：>0 / ≥0。
- Julia / 配置映射：`eta_DH, P_DH_max`；维度：标量；配置 building。
- 来源 PDF 页：44；状态：`visual_checked_with_scope_notes`。

### [项目教学电能单价](@id symbol-teaching_cost)

```math
c^{CHP},\rho_t^{grid}
```

- ID / ASCII 别名：`teaching_cost` / `teaching_cost`
- 类别：parameter；上下标：不是作者第2章市场优化的结果。
- 单位：货币/MWh；定义域：非负。
- Julia / 配置映射：`CHP_per_MWh, grid_per_MWh`；维度：标量/T；配置 cost。
- 来源 PDF 页：项目新增；状态：`visual_checked_with_scope_notes`。
