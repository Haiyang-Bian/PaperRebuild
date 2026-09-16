```@raw html
<!-- GENERATED: scripts/ch02_docs.jl; edit docs/reading/ch02 and current Julia sources. -->
```

# [第 2 章公式索引](@id ch02-generated)

此页由权威 TOML 生成，并校验当前源码标记与测试名称。已实现公式直接链接到 Julia docstring 的 API 条目；核查状态不代表科学验收通过，数值证据见 [本批状态](@ref ch02-status)。

## 公式逐条清单

每组首式列出共同假设；各式的完整独立记录仍保存在权威 TOML 中。

### [式（2-1）：CHP 热电关系](@id eq-ch02-001)

```math
H_t^{CHP}=P_t^{CHP}(1-\eta_t^G-\eta^{loss})/\eta^G
\tag{2-1}
```

出处：PDF 30 / 正文 13；核查：`visual_checked_open_issue`；实现：`special_case`。

本组共同假设：常效率近似与变效率多项式分开；式 2-1 分母下标歧义未解除。

疑点：**C01**，见 [核查边界](@ref ch02-issues)。

符号：[P_CHP](@ref symbol-P_CHP)、[H_CHP](@ref symbol-H_CHP)、[eta_G](@ref symbol-eta_G)、[eta_loss](@ref symbol-eta_loss)、[alpha_CHP](@ref symbol-alpha_CHP)、[P_CHP_bounds](@ref symbol-P_CHP_bounds)、[H_CHP_bounds](@ref symbol-H_CHP_bounds)、[time_index](@ref symbol-time_index)。

API：[`chp_heat`](@ref) · [实现与测试映射](@ref source-eq-ch02-001)。

### [式（2-2）：CHP 电出力界](@id eq-ch02-002)

```math
\underline P^{CHP}\le P_t^{CHP}\le\overline P^{CHP}
\tag{2-2}
```

出处：PDF 30 / 正文 13；核查：`visual_checked`；实现：`implemented`。

符号：[P_CHP](@ref symbol-P_CHP)、[H_CHP](@ref symbol-H_CHP)、[eta_G](@ref symbol-eta_G)、[eta_loss](@ref symbol-eta_loss)、[alpha_CHP](@ref symbol-alpha_CHP)、[P_CHP_bounds](@ref symbol-P_CHP_bounds)、[H_CHP_bounds](@ref symbol-H_CHP_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-3）：CHP 热出力界](@id eq-ch02-003)

```math
\underline H^{CHP}\le H_t^{CHP}\le\overline H^{CHP}
\tag{2-3}
```

出处：PDF 30 / 正文 13；核查：`visual_checked`；实现：`implemented`。

符号：[P_CHP](@ref symbol-P_CHP)、[H_CHP](@ref symbol-H_CHP)、[eta_G](@ref symbol-eta_G)、[eta_loss](@ref symbol-eta_loss)、[alpha_CHP](@ref symbol-alpha_CHP)、[P_CHP_bounds](@ref symbol-P_CHP_bounds)、[H_CHP_bounds](@ref symbol-H_CHP_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-4）：CHP 三次效率](@id eq-ch02-004)

```math
\eta_t^G=\alpha_0+\alpha_1(P_t^{CHP}/\overline P^{CHP})+\alpha_2(P_t^{CHP}/\overline P^{CHP})^2+\alpha_3(P_t^{CHP}/\overline P^{CHP})^3
\tag{2-4}
```

出处：PDF 30 / 正文 13；核查：`visual_checked`；实现：`evaluated`。

符号：[P_CHP](@ref symbol-P_CHP)、[H_CHP](@ref symbol-H_CHP)、[eta_G](@ref symbol-eta_G)、[eta_loss](@ref symbol-eta_loss)、[alpha_CHP](@ref symbol-alpha_CHP)、[P_CHP_bounds](@ref symbol-P_CHP_bounds)、[H_CHP_bounds](@ref symbol-H_CHP_bounds)、[time_index](@ref symbol-time_index)。

API：[`chp_efficiency`](@ref) · [实现与测试映射](@ref source-eq-ch02-004)。

### [式（2-5）：光伏可用功率](@id eq-ch02-005)

```math
P^{PV}=f^{PV}P^{rated}(A^{real}/A^{STC})[1+\alpha^{power}(\tau-\tau^{STC})]
\tag{2-5}
```

出处：PDF 31 / 正文 14；核查：`visual_checked`；实现：`evaluated`。

本组共同假设：式号右缘局部裁切，按上下文序号定位；风电原式不修正。

符号：[P_PV](@ref symbol-P_PV)、[P_PV_available](@ref symbol-P_PV_available)、[f_PV](@ref symbol-f_PV)、[P_rated](@ref symbol-P_rated)、[A_irradiance](@ref symbol-A_irradiance)、[alpha_power](@ref symbol-alpha_power)、[tau_PV](@ref symbol-tau_PV)、[P_WT](@ref symbol-P_WT)、[v_wind](@ref symbol-v_wind)、[time_index](@ref symbol-time_index)。

API：[`pv_available`](@ref) · [实现与测试映射](@ref source-eq-ch02-005)。

### [式（2-6）：光伏调度出力界](@id eq-ch02-006)

```math
0\le P_t^{PV}\le\overline P_t^{PV}
\tag{2-6}
```

出处：PDF 31 / 正文 14；核查：`visual_checked`；实现：`implemented`。

符号：[P_PV](@ref symbol-P_PV)、[P_PV_available](@ref symbol-P_PV_available)、[f_PV](@ref symbol-f_PV)、[P_rated](@ref symbol-P_rated)、[A_irradiance](@ref symbol-A_irradiance)、[alpha_power](@ref symbol-alpha_power)、[tau_PV](@ref symbol-tau_PV)、[P_WT](@ref symbol-P_WT)、[v_wind](@ref symbol-v_wind)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-7）：风机分段，详见疑点 C02](@id eq-ch02-007)

```math
P^{WT}(v)=\{0;\ P_r(v^3-v_{co}^3)/(v_{co}^3-v_{ci}^3);\ P_r\}
\tag{2-7}
```

出处：PDF 31 / 正文 14；核查：`visual_checked_open_issue`；实现：`blocked`。

疑点：**C02**，见 [核查边界](@ref ch02-issues)。

符号：[P_PV](@ref symbol-P_PV)、[P_PV_available](@ref symbol-P_PV_available)、[f_PV](@ref symbol-f_PV)、[P_rated](@ref symbol-P_rated)、[A_irradiance](@ref symbol-A_irradiance)、[alpha_power](@ref symbol-alpha_power)、[tau_PV](@ref symbol-tau_PV)、[P_WT](@ref symbol-P_WT)、[v_wind](@ref symbol-v_wind)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-8）：电锅炉转换](@id eq-ch02-008)

```math
H_t^{EB}=P_t^{EB}COP^{EB}
\tag{2-8}
```

出处：PDF 32 / 正文 15；核查：`visual_checked`；实现：`implemented`。

本组共同假设：输入效率为比值；储能能量单位 MWh；补显式 Δt；z 无 t 下标。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-9）：电锅炉容量](@id eq-ch02-009)

```math
0\le P_t^{EB}\le\overline P^{EB}
\tag{2-9}
```

出处：PDF 32 / 正文 15；核查：`visual_checked`；实现：`implemented`。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-10）：热泵转换](@id eq-ch02-010)

```math
H_t^{HP}=P_t^{HP}COP^{HP}
\tag{2-10}
```

出处：PDF 32 / 正文 15；核查：`visual_checked`；实现：`implemented`。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-11）：热泵容量](@id eq-ch02-011)

```math
0\le P_t^{HP}\le\overline P^{HP}
\tag{2-11}
```

出处：PDF 32 / 正文 15；核查：`visual_checked`；实现：`implemented`。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-12）：电池状态，原式无 Δt](@id eq-ch02-012)

```math
E_{t+1}^{BS}=E_t^{BS}+\eta^{BS,ch}P_t^{BS,ch}-P_t^{BS,dis}/\eta^{BS,dis}
\tag{2-12}
```

出处：PDF 32 / 正文 15；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C03**，见 [核查边界](@ref ch02-issues)。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`battery_step`](@ref) · [实现与测试映射](@ref source-eq-ch02-012)。

### [式（2-13）：电池互斥](@id eq-ch02-013)

```math
0\le P_t^{BS,ch}\le z^{BS}\overline P^{BS},\quad0\le P_t^{BS,dis}\le(1-z^{BS})\overline P^{BS}
\tag{2-13}
```

出处：PDF 32 / 正文 15；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C04**，见 [核查边界](@ref ch02-issues)。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-14）：电池能量界](@id eq-ch02-014)

```math
0\le E_t^{BS}\le\overline E^{BS}
\tag{2-14}
```

出处：PDF 32 / 正文 15；核查：`visual_checked`；实现：`implemented`。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-15）：电池周期条件](@id eq-ch02-015)

```math
E_T^{BS}=E_0^{BS}
\tag{2-15}
```

出处：PDF 32 / 正文 15；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C03**，见 [核查边界](@ref ch02-issues)。

符号：[P_EB](@ref symbol-P_EB)、[H_EB](@ref symbol-H_EB)、[COP_EB](@ref symbol-COP_EB)、[P_HP](@ref symbol-P_HP)、[H_HP](@ref symbol-H_HP)、[COP_HP](@ref symbol-COP_HP)、[E_BS](@ref symbol-E_BS)、[P_BS_ch](@ref symbol-P_BS_ch)、[P_BS_dis](@ref symbol-P_BS_dis)、[eta_BS](@ref symbol-eta_BS)、[z_BS](@ref symbol-z_BS)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-16）：热储能原式，效率方向存疑](@id eq-ch02-016)

```math
E_{t+1}^{HS}=\eta^{HS,loss}E_t^{HS}+H_t^{HS,ch}/\eta^{HS,ch}-\eta^{HS,dis}H_t^{HS,dis}
\tag{2-16}
```

出处：PDF 33 / 正文 16；核查：`visual_checked_open_issue`；实现：`special_case`。

本组共同假设：HS/TS 为同义异形；2-16 充放效率方向存疑；2-20 漏 EB。

疑点：**C05**，见 [核查边界](@ref ch02-issues)。

符号：[E_HS](@ref symbol-E_HS)、[H_HS_ch](@ref symbol-H_HS_ch)、[H_HS_dis](@ref symbol-H_HS_dis)、[eta_HS](@ref symbol-eta_HS)、[z_HS](@ref symbol-z_HS)、[P_net](@ref symbol-P_net)、[Q_net](@ref symbol-Q_net)、[device_sets](@ref symbol-device_sets)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`heat_storage_step_paper`](@ref) · [实现与测试映射](@ref source-eq-ch02-016)。

### [式（2-17）：热储能互斥](@id eq-ch02-017)

```math
0\le H_t^{HS,ch}\le z^{HS}\overline H^{HS},\quad0\le H_t^{HS,dis}\le(1-z^{HS})\overline H^{HS}
\tag{2-17}
```

出处：PDF 33 / 正文 16；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C04**，见 [核查边界](@ref ch02-issues)。

符号：[E_HS](@ref symbol-E_HS)、[H_HS_ch](@ref symbol-H_HS_ch)、[H_HS_dis](@ref symbol-H_HS_dis)、[eta_HS](@ref symbol-eta_HS)、[z_HS](@ref symbol-z_HS)、[P_net](@ref symbol-P_net)、[Q_net](@ref symbol-Q_net)、[device_sets](@ref symbol-device_sets)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-18）：热储能能量界](@id eq-ch02-018)

```math
0\le E_t^{HS}\le\overline E^{HS}
\tag{2-18}
```

出处：PDF 33 / 正文 16；核查：`visual_checked`；实现：`implemented`。

符号：[E_HS](@ref symbol-E_HS)、[H_HS_ch](@ref symbol-H_HS_ch)、[H_HS_dis](@ref symbol-H_HS_dis)、[eta_HS](@ref symbol-eta_HS)、[z_HS](@ref symbol-z_HS)、[P_net](@ref symbol-P_net)、[Q_net](@ref symbol-Q_net)、[device_sets](@ref symbol-device_sets)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-19）：热储能周期条件](@id eq-ch02-019)

```math
E_T^{HS}=E_0^{HS}
\tag{2-19}
```

出处：PDF 33 / 正文 16；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C03**，见 [核查边界](@ref ch02-issues)。

符号：[E_HS](@ref symbol-E_HS)、[H_HS_ch](@ref symbol-H_HS_ch)、[H_HS_dis](@ref symbol-H_HS_dis)、[eta_HS](@ref symbol-eta_HS)、[z_HS](@ref symbol-z_HS)、[P_net](@ref symbol-P_net)、[Q_net](@ref symbol-Q_net)、[device_sets](@ref symbol-device_sets)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-20）：节点有功注入，原式未列 EB](@id eq-ch02-020)

```math
P_t^{net}=\sum P_t^{GT}+\sum P_t^{CHP}+\sum P_t^{PV}+\sum P_t^{WT}-\sum P_t^{HP}-\sum P_t^{BS,ch}+\sum P_t^{BS,dis}-P_t^D
\tag{2-20}
```

出处：PDF 33 / 正文 16；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C06**，见 [核查边界](@ref ch02-issues)。

符号：[E_HS](@ref symbol-E_HS)、[H_HS_ch](@ref symbol-H_HS_ch)、[H_HS_dis](@ref symbol-H_HS_dis)、[eta_HS](@ref symbol-eta_HS)、[z_HS](@ref symbol-z_HS)、[P_net](@ref symbol-P_net)、[Q_net](@ref symbol-Q_net)、[device_sets](@ref symbol-device_sets)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-21）：节点无功注入](@id eq-ch02-021)

```math
Q_t^{net}=\sum Q_t^{GT}+\sum Q_t^{CHP}-Q_t^D
\tag{2-21}
```

出处：PDF 33 / 正文 16；核查：`visual_checked`；实现：`special_case`。

符号：[E_HS](@ref symbol-E_HS)、[H_HS_ch](@ref symbol-H_HS_ch)、[H_HS_dis](@ref symbol-H_HS_dis)、[eta_HS](@ref symbol-eta_HS)、[z_HS](@ref symbol-z_HS)、[P_net](@ref symbol-P_net)、[Q_net](@ref symbol-Q_net)、[device_sets](@ref symbol-device_sets)、[storage_bounds](@ref symbol-storage_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-22）：节点有功守恒](@id eq-ch02-022)

```math
P_n^{net}=\sum_{b\in\Theta(n)}P_{nb}-(P_{mn}-r_{mn}l_{mn})
\tag{2-22}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`special_case`。

本组共同假设：固定径向拓扑；v 与 l 为平方量；SOCP 是松弛。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-23）：节点无功守恒](@id eq-ch02-023)

```math
Q_n^{net}=\sum_{b\in\Theta(n)}Q_{nb}-(Q_{mn}-x_{mn}l_{mn})
\tag{2-23}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`special_case`。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-24）：电压平方降落](@id eq-ch02-024)

```math
v_n=v_m-2(r_{mn}P_{mn}+x_{mn}Q_{mn})+(r_{mn}^2+x_{mn}^2)l_{mn}
\tag{2-24}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`special_case`。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-25）：原非凸电流功率等式](@id eq-ch02-025)

```math
P_{mn}^2+Q_{mn}^2=v_m l_{mn}
\tag{2-25}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`residual_only`。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`validate_r1_solution`](@ref) · [实现与测试映射](@ref source-r1-validate)。

### [式（2-26）：电压平方界](@id eq-ch02-026)

```math
\underline v_m\le v_m\le\overline v_m
\tag{2-26}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`special_case`。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-27）：电流平方界](@id eq-ch02-027)

```math
\underline l_{mn}\le l_{mn}\le\overline l_{mn}
\tag{2-27}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`special_case`。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-28）：支路潮流的二阶锥松弛](@id eq-ch02-028)

```math
\left\lVert\begin{bmatrix}2P_{mn,t}\\2Q_{mn,t}\\l_{mn,t}-v_{m,t}\end{bmatrix}\right\rVert_2\le l_{mn,t}+v_{m,t},\quad\forall n\in\mathcal N,\ (m,n)\in\mathcal B
\tag{2-28}
```

出处：PDF 34 / 正文 17；核查：`visual_checked`；实现：`special_case`。

符号：[P_branch](@ref symbol-P_branch)、[Q_branch](@ref symbol-Q_branch)、[v_squared](@ref symbol-v_squared)、[l_squared](@ref symbol-l_squared)、[r_x](@ref symbol-r_x)、[electric_bounds](@ref symbol-electric_bounds)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-29）：热源换热，原式未列 EB](@id eq-ch02-029)

```math
\sum H^{CHP}+\sum H^{HP}-\sum H^{TS,ch}+\sum H^{TS,dis}=c_w m_j(\tau_j^S-\tau_j^R)
\tag{2-29}
```

出处：PDF 35 / 正文 18；核查：`visual_checked_open_issue`；实现：`special_case`。

本组共同假设：用热节点注入 m 为负；c_w 原单位 kJ/(kg K)。

疑点：**C06**，见 [核查边界](@ref ch02-issues)。

符号：[H_source](@ref symbol-H_source)、[H_D](@ref symbol-H_D)、[c_w](@ref symbol-c_w)、[m_node](@ref symbol-m_node)、[tau_SR](@ref symbol-tau_SR)、[heat_bounds](@ref symbol-heat_bounds)、[time_index](@ref symbol-time_index)。

API：[`heat_power`](@ref) · [实现与测试映射](@ref source-eq-ch02-029)。

### [式（2-30）：热源回水混合](@id eq-ch02-030)

```math
\tau_j^R=\tau_j^{R,mix}
\tag{2-30}
```

出处：PDF 35 / 正文 18；核查：`visual_checked`；实现：`special_case`。

符号：[H_source](@ref symbol-H_source)、[H_D](@ref symbol-H_D)、[c_w](@ref symbol-c_w)、[m_node](@ref symbol-m_node)、[tau_SR](@ref symbol-tau_SR)、[heat_bounds](@ref symbol-heat_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-31）：供水温度界](@id eq-ch02-031)

```math
\underline\tau^S\le\tau_j^S\le\overline\tau^S
\tag{2-31}
```

出处：PDF 35 / 正文 18；核查：`visual_checked`；实现：`special_case`。

符号：[H_source](@ref symbol-H_source)、[H_D](@ref symbol-H_D)、[c_w](@ref symbol-c_w)、[m_node](@ref symbol-m_node)、[tau_SR](@ref symbol-tau_SR)、[heat_bounds](@ref symbol-heat_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-32）：热负荷换热，节点注入为负](@id eq-ch02-032)

```math
h_j^D=-c_wm_j(\tau_j^S-\tau_j^R)
\tag{2-32}
```

出处：PDF 35 / 正文 18；核查：`visual_checked`；实现：`special_case`。

符号：[H_source](@ref symbol-H_source)、[H_D](@ref symbol-H_D)、[c_w](@ref symbol-c_w)、[m_node](@ref symbol-m_node)、[tau_SR](@ref symbol-tau_SR)、[heat_bounds](@ref symbol-heat_bounds)、[time_index](@ref symbol-time_index)。

API：[`heat_power`](@ref) · [实现与测试映射](@ref source-eq-ch02-029)。

### [式（2-33）：回水温度界](@id eq-ch02-033)

```math
\underline\tau^R\le\tau_j^R\le\overline\tau^R
\tag{2-33}
```

出处：PDF 35 / 正文 18；核查：`visual_checked`；实现：`special_case`。

符号：[H_source](@ref symbol-H_source)、[H_D](@ref symbol-H_D)、[c_w](@ref symbol-c_w)、[m_node](@ref symbol-m_node)、[tau_SR](@ref symbol-tau_SR)、[heat_bounds](@ref symbol-heat_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-34）：负荷供水混合](@id eq-ch02-034)

```math
\tau_j^S=\tau_j^{S,mix}
\tag{2-34}
```

出处：PDF 35 / 正文 18；核查：`visual_checked`；实现：`special_case`。

符号：[H_source](@ref symbol-H_source)、[H_D](@ref symbol-H_D)、[c_w](@ref symbol-c_w)、[m_node](@ref symbol-m_node)、[tau_SR](@ref symbol-tau_SR)、[heat_bounds](@ref symbol-heat_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-35）：节点质量守恒](@id eq-ch02-035)

```math
m_k=\sum_lm_{kl}-\sum_jm_{jk}
\tag{2-35}
```

出处：PDF 36 / 正文 19；核查：`visual_checked`；实现：`deferred`。

本组共同假设：PDF 36 右半页是正文 19；正负流与压降方向必须一致。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-36）：管道流量界](@id eq-ch02-036)

```math
-\overline m_{jk}\le m_{jk}\le\overline m_{jk}
\tag{2-36}
```

出处：PDF 36 / 正文 19；核查：`visual_checked`；实现：`deferred`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-37）：节点流量界](@id eq-ch02-037)

```math
\underline m_k\le m_k\le\overline m_k
\tag{2-37}
```

出处：PDF 36 / 正文 19；核查：`visual_checked`；实现：`deferred`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-38）：供水水压降](@id eq-ch02-038)

```math
\Phi_j^S-\Phi_k^S=\mu_{jk}m_{jk}^2+\Phi_{jk}^{val}
\tag{2-38}
```

出处：PDF 36 / 正文 19；核查：`visual_checked`；实现：`deferred`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-39）：回水压降方向待核](@id eq-ch02-039)

```math
\Phi_j^R-\Phi_k^R=\mu_{jk}m_{jk}^2+\Phi_{jk}^{val}
\tag{2-39}
```

出处：PDF 36 / 正文 19；核查：`visual_checked_open_issue`；实现：`blocked`。

疑点：**C07**，见 [核查边界](@ref ch02-issues)。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-40）：压力非负，原页下标不一致](@id eq-ch02-040)

```math
\Phi^S\ge0,\quad\Phi^R\ge0,\quad\Phi^{val}\ge0
\tag{2-40}
```

出处：PDF 36 / 正文 19；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C07**，见 [核查边界](@ref ch02-issues)。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-41）：供回水压差界](@id eq-ch02-041)

```math
\Delta\underline\Phi\le\Phi_j^S-\Phi_j^R\le\Delta\overline\Phi
\tag{2-41}
```

出处：PDF 36 / 正文 19；核查：`visual_checked`；实现：`deferred`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[Phi](@ref symbol-Phi)、[mu_hydraulic](@ref symbol-mu_hydraulic)、[flow_bounds](@ref symbol-flow_bounds)、[pressure_bounds](@ref symbol-pressure_bounds)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-42）：供水混合](@id eq-ch02-042)

```math
\sum_jm_{jk}\tau_{jk}^{S,out}+m_k\tau_k^S=\tau_k^{S,mix}(\sum_jm_{jk}+m_k)
\tag{2-42}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

本组共同假设：单管正向流条件；PDE 与离散衰减系数疑点分别记录。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`mix_temperature`](@ref) · [实现与测试映射](@ref source-eq-ch02-042)。

### [式（2-43）：回水混合，方向按原页](@id eq-ch02-043)

```math
\sum_lm_{lk}\tau_{lk}^{R,out}+m_k\tau_k^R=\tau_k^{R,mix}(\sum_lm_{lk}+m_k)
\tag{2-43}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`mix_temperature`](@ref) · [实现与测试映射](@ref source-eq-ch02-042)。

### [式（2-44）：供水入口连续](@id eq-ch02-044)

```math
\tau_{jk}^{S,in}=\tau_j^{S,mix}
\tag{2-44}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-45）：回水入口连续](@id eq-ch02-045)

```math
\tau_{lk}^{R,in}=\tau_l^{R,mix}
\tag{2-45}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-46）：管道 PDE，衰减系数量纲疑点](@id eq-ch02-046)

```math
\partial_t\tau+\frac{m}{\rho_w A}\partial_x\tau+\frac{\epsilon}{\rho_w A L}(\tau-\hat\tau^{AM})=0
\tag{2-46}
```

出处：PDF 37 / 正文 20；核查：`visual_checked_open_issue`；实现：`blocked`。

疑点：**C08**，见 [核查边界](@ref ch02-issues)。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-47）：无损节点法历史卷积](@id eq-ch02-047)

```math
\tau_t^{out,*}=\sum_{\zeta=1}^tK_{t,\zeta}\tau_\zeta^{in}+\hat\tau_t^{out,*}
\tag{2-47}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-48）：节点法热损耗](@id eq-ch02-048)

```math
\tau_t^{out}=\hat\tau_t^{AM}+J_t(\tau_t^{out,*}-\hat\tau_t^{AM})
\tag{2-48}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-49）：入口质量权重，分段条件见模型说明](@id eq-ch02-049)

```math
K_{t,\zeta}=\{(m_t\Delta T-S_t+\rho_wAL)/(m_t\Delta T);\ m_\zeta\Delta T/(m_t\Delta T);\ (R_t-\rho_wAL)/(m_t\Delta T);\ 0\}
\tag{2-49}
```

出处：PDF 37 / 正文 20；核查：`visual_checked`；实现：`special_case`。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-50）：节点法温度衰减因子](@id eq-ch02-050)

```math
J_t=\exp[-\epsilon\Delta T/(c_w\rho_w A)(\chi_t+1/2+(S_t-R_t)/(m_{t-\chi_t}\Delta T))]
\tag{2-50}
```

出处：PDF 37 / 正文 20；核查：`visual_checked_open_issue`；实现：`special_case`。

疑点：**C08**，见 [核查边界](@ref ch02-issues)。

符号：[m_node](@ref symbol-m_node)、[m_pipe](@ref symbol-m_pipe)、[tau_SR](@ref symbol-tau_SR)、[tau_mix](@ref symbol-tau_mix)、[tau_in_out](@ref symbol-tau_in_out)、[tau_AM](@ref symbol-tau_AM)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[epsilon_pipe](@ref symbol-epsilon_pipe)、[K](@ref symbol-K)、[J](@ref symbol-J)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-51）：不含当前时段的回溯](@id eq-ch02-051)

```math
\psi_t=\min\{T_m:\sum_{t'=t-T_m}^{t-1}m_{t'}\Delta T\ge\rho_wAL\}
\tag{2-51}
```

出处：PDF 38 / 正文 21；核查：`visual_checked`；实现：`special_case`。

本组共同假设：当前批只推导恒定正流量特例；初始温度历史必需。

符号：[m_pipe](@ref symbol-m_pipe)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-52）：包含当前时段的回溯](@id eq-ch02-052)

```math
\chi_t=\min\{T_n:\sum_{t'=t-T_n}^{t}m_{t'}\Delta T\ge\rho_wAL\}
\tag{2-52}
```

出处：PDF 38 / 正文 21；核查：`visual_checked`；实现：`special_case`。

符号：[m_pipe](@ref symbol-m_pipe)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-53）：累计质量 R](@id eq-ch02-053)

```math
R_t=\sum_{t'=t-\chi_t}^{t}m_{t'}\Delta T
\tag{2-53}
```

出处：PDF 38 / 正文 21；核查：`visual_checked`；实现：`special_case`。

符号：[m_pipe](@ref symbol-m_pipe)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-54）：累计质量 S](@id eq-ch02-054)

```math
S_t=\{\sum_{t'=t-\psi_t+1}^{t}m_{t'}\Delta T\ \text{if }\psi_t\ge\chi_t+1;\ R_t\ \text{otherwise}\}
\tag{2-54}
```

出处：PDF 38 / 正文 21；核查：`visual_checked`；实现：`special_case`。

符号：[m_pipe](@ref symbol-m_pipe)、[rho_w](@ref symbol-rho_w)、[A_pipe](@ref symbol-A_pipe)、[L_pipe](@ref symbol-L_pipe)、[psi_chi](@ref symbol-psi_chi)、[R_S](@ref symbol-R_S)、[DeltaT](@ref symbol-DeltaT)、[time_index](@ref symbol-time_index)。

API：[`fixed_flow_kernel`](@ref) · [实现与测试映射](@ref source-eq-ch02-047)。

### [式（2-55）：电力市场申报成本](@id eq-ch02-055)

```math
\min \rho^\top P^G
\tag{2-55}
```

出处：PDF 39 / 正文 22；核查：`visual_checked`；实现：`deferred`。

本组共同假设：基础 DC 市场模型，非本批教学成本；2-59 下界项遗漏负荷。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-56）：总发用电平衡，P^D 此处为总量](@id eq-ch02-056)

```math
\mathbf1^\top P^G=P^D
\tag{2-56}
```

出处：PDF 39 / 正文 22；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C09**，见 [核查边界](@ref ch02-issues)。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-57）：发电出力界](@id eq-ch02-057)

```math
\underline P^G\le P^G\le\overline P^G
\tag{2-57}
```

出处：PDF 39 / 正文 22；核查：`visual_checked`；实现：`deferred`。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-58）：PTDF 线路容量，此处 P^D 为向量](@id eq-ch02-058)

```math
\underline P^L\le T(P^G-P^D)\le\overline P^L
\tag{2-58}
```

出处：PDF 39 / 正文 22；核查：`visual_checked`；实现：`deferred`。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-59）：拉格朗日式，下限潮流项缺负荷；τ形乘子非温度](@id eq-ch02-059)

```math
\mathcal L=\rho^\top P^G+\lambda(\mathbf1^\top P^G-P^D)+\hat\mu^\top[T(P^G-P^D)-\overline P^L]-\tilde\mu^\top(TP^G-\underline P^L)+\hat\tau^\top(P^G-\overline P^G)-\tilde\tau^\top(P^G-\underline P^G)
\tag{2-59}
```

出处：PDF 39 / 正文 22；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C09**，见 [核查边界](@ref ch02-issues)。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-60）：驻点条件；τ形乘子与温度分作用域](@id eq-ch02-060)

```math
\rho_n+\lambda+\sum_l T_{ln}(\hat\mu_l-\tilde\mu_l)+\hat\tau_n-\tilde\tau_n=0
\tag{2-60}
```

出处：PDF 39 / 正文 22；核查：`visual_checked`；实现：`deferred`。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-61）：节点边际价格](@id eq-ch02-061)

```math
p_n=-\lambda-\sum_lT_{ln}(\hat\mu_l-\tilde\mu_l)
\tag{2-61}
```

出处：PDF 39 / 正文 22；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C09**，见 [核查边界](@ref ch02-issues)。

符号：[P_G_market](@ref symbol-P_G_market)、[P_D_market](@ref symbol-P_D_market)、[P_L_market](@ref symbol-P_L_market)、[rho_market](@ref symbol-rho_market)、[PTDF](@ref symbol-PTDF)、[dual_market](@ref symbol-dual_market)、[p_market](@ref symbol-p_market)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-62）：开关无向状态与有向父边](@id eq-ch02-062)

```math
u_{mn,t}^{SW}=z_{mn,t}+z_{nm,t}
\tag{2-62}
```

出处：PDF 42 / 正文 25；核查：`visual_checked`；实现：`deferred`。

本组共同假设：至多一个父节点约束本身不保证连通与无环。

符号：[u_SW](@ref symbol-u_SW)、[z_parent](@ref symbol-z_parent)、[a_SW](@ref symbol-a_SW)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-63）：非根最多一条父边](@id eq-ch02-063)

```math
\sum_m z_{mn,t}\le1,\ n\ne root
\tag{2-63}
```

出处：PDF 42 / 正文 25；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C10**，见 [核查边界](@ref ch02-issues)。

符号：[u_SW](@ref symbol-u_SW)、[z_parent](@ref symbol-z_parent)、[a_SW](@ref symbol-a_SW)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-64）：根无父边](@id eq-ch02-064)

```math
\sum_mz_{m,root,t}=0
\tag{2-64}
```

出处：PDF 42 / 正文 25；核查：`visual_checked`；实现：`deferred`。

符号：[u_SW](@ref symbol-u_SW)、[z_parent](@ref symbol-z_parent)、[a_SW](@ref symbol-a_SW)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-65）：电网重构变量域](@id eq-ch02-065)

```math
z_{mn,t}\in\{0,1\},\quad0\le a_{mn,t}^{SW}\le1
\tag{2-65}
```

出处：PDF 42 / 正文 25；核查：`visual_checked`；实现：`deferred`。

符号：[u_SW](@ref symbol-u_SW)、[z_parent](@ref symbol-z_parent)、[a_SW](@ref symbol-a_SW)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-66）：合闸动作下界](@id eq-ch02-066)

```math
z_{mn,t}-z_{mn,t-1}\le a_{mn,t}^{SW},\quad z_{mn,1}-\hat z_{mn,0}\le a_{mn,1}^{SW}
\tag{2-66}
```

出处：PDF 42 / 正文 25；核查：`visual_checked`；实现：`deferred`。

符号：[u_SW](@ref symbol-u_SW)、[z_parent](@ref symbol-z_parent)、[a_SW](@ref symbol-a_SW)、[electric_sets](@ref symbol-electric_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-67）：阀状态与有向父边](@id eq-ch02-067)

```math
u_{jk}^{VL}=\nu_{jk}+\nu_{kj}
\tag{2-67}
```

出处：PDF 43 / 正文 26；核查：`visual_checked`；实现：`deferred`。

本组共同假设：热阀状态以天为窗口；2-71 右侧下标印为 mn。

符号：[u_VL](@ref symbol-u_VL)、[nu_parent](@ref symbol-nu_parent)、[a_VL](@ref symbol-a_VL)、[heat_sets](@ref symbol-heat_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-68）：热网非根父边](@id eq-ch02-068)

```math
\sum_j\nu_{jk}\le1,\ k\ne root
\tag{2-68}
```

出处：PDF 43 / 正文 26；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C10**，见 [核查边界](@ref ch02-issues)。

符号：[u_VL](@ref symbol-u_VL)、[nu_parent](@ref symbol-nu_parent)、[a_VL](@ref symbol-a_VL)、[heat_sets](@ref symbol-heat_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-69）：热源根无父边](@id eq-ch02-069)

```math
\sum_j\nu_{j,root}=0
\tag{2-69}
```

出处：PDF 43 / 正文 26；核查：`visual_checked`；实现：`deferred`。

符号：[u_VL](@ref symbol-u_VL)、[nu_parent](@ref symbol-nu_parent)、[a_VL](@ref symbol-a_VL)、[heat_sets](@ref symbol-heat_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-70）：热网重构变量域](@id eq-ch02-070)

```math
\nu_{jk}\in\{0,1\},\quad0\le a_{jk}^{VL}\le1
\tag{2-70}
```

出处：PDF 43 / 正文 26；核查：`visual_checked`；实现：`deferred`。

符号：[u_VL](@ref symbol-u_VL)、[nu_parent](@ref symbol-nu_parent)、[a_VL](@ref symbol-a_VL)、[heat_sets](@ref symbol-heat_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-71）：原式右侧 mn 与 jk 不一致](@id eq-ch02-071)

```math
\nu_{jk,1}-\hat\nu_{jk,0}\le a_{mn}^{VL}
\tag{2-71}
```

出处：PDF 43 / 正文 26；核查：`visual_checked_open_issue`；实现：`deferred`。

疑点：**C11**，见 [核查边界](@ref ch02-issues)。

符号：[u_VL](@ref symbol-u_VL)、[nu_parent](@ref symbol-nu_parent)、[a_VL](@ref symbol-a_VL)、[heat_sets](@ref symbol-heat_sets)、[time_index](@ref symbol-time_index)。

本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。

### [式（2-72）：建筑隐式温度状态](@id eq-ch02-072)

```math
\eta^H\hat H_t^D+U_t(\hat\tau_t^{AM}-\tau_t^{IN})=\tau_t^{IN}-\tau_{t-1}^{IN}
\tag{2-72}
```

出处：PDF 43 / 正文 26；核查：`visual_checked_open_issue`；实现：`special_case`。

本组共同假设：隐式离散温度；η_H、U 的时间步长与量纲需要项目明确。

疑点：**C12**，见 [核查边界](@ref ch02-issues)。

符号：[tau_IN](@ref symbol-tau_IN)、[tau_AM](@ref symbol-tau_AM)、[H_D_hat](@ref symbol-H_D_hat)、[eta_H](@ref symbol-eta_H)、[U_building](@ref symbol-U_building)、[building_bounds](@ref symbol-building_bounds)、[time_index](@ref symbol-time_index)。

API：[`building_step`](@ref) · [实现与测试映射](@ref source-eq-ch02-072)。

### [式（2-73）：舒适温度界](@id eq-ch02-073)

```math
\underline\tau^{IN}\le\tau_t^{IN}\le\overline\tau^{IN}
\tag{2-73}
```

出处：PDF 43 / 正文 26；核查：`visual_checked`；实现：`implemented`。

符号：[tau_IN](@ref symbol-tau_IN)、[tau_AM](@ref symbol-tau_AM)、[H_D_hat](@ref symbol-H_D_hat)、[eta_H](@ref symbol-eta_H)、[U_building](@ref symbol-U_building)、[building_bounds](@ref symbol-building_bounds)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-74）：基础电负荷加户用电热](@id eq-ch02-074)

```math
P_t^D=\hat P_t^D+P_t^{D,H}
\tag{2-74}
```

出处：PDF 44 / 正文 27；核查：`visual_checked`；实现：`special_case`。

本组共同假设：户用电热转换，需求帽号与网络需求分开。

符号：[P_D](@ref symbol-P_D)、[P_D_hat](@ref symbol-P_D_hat)、[H_D](@ref symbol-H_D)、[H_D_hat](@ref symbol-H_D_hat)、[P_DH](@ref symbol-P_DH)、[H_DH](@ref symbol-H_DH)、[eta_DH](@ref symbol-eta_DH)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-75）：网络供热与户用供热分摊](@id eq-ch02-075)

```math
H_t^D=\hat H_t^D-H_t^{D,H}
\tag{2-75}
```

出处：PDF 44 / 正文 27；核查：`visual_checked`；实现：`implemented`。

符号：[P_D](@ref symbol-P_D)、[P_D_hat](@ref symbol-P_D_hat)、[H_D](@ref symbol-H_D)、[H_D_hat](@ref symbol-H_D_hat)、[P_DH](@ref symbol-P_DH)、[H_DH](@ref symbol-H_DH)、[eta_DH](@ref symbol-eta_DH)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。

### [式（2-76）：户用电热转换](@id eq-ch02-076)

```math
0\le P_t^{D,H}\le\overline P^{D,H},\quad H_t^{D,H}=\eta^{D,H}P_t^{D,H}
\tag{2-76}
```

出处：PDF 44 / 正文 27；核查：`visual_checked`；实现：`implemented`。

符号：[P_D](@ref symbol-P_D)、[P_D_hat](@ref symbol-P_D_hat)、[H_D](@ref symbol-H_D)、[H_D_hat](@ref symbol-H_D_hat)、[P_DH](@ref symbol-P_DH)、[H_DH](@ref symbol-H_DH)、[eta_DH](@ref symbol-eta_DH)、[time_index](@ref symbol-time_index)。

API：[`build_r1_model`](@ref) · [实现与测试映射](@ref source-r1-model)。
