# 第4章原式清单

<!-- GENERATED: scripts/ch04_docs.jl -->

原式规范化转录保留疑点，不等同于采用模型。见[模型说明](ch04-models.md)。

## [（4-1）聚合商目标](@id ch04-001)

```math
\max U_i^0=-\sum_t(C_{i,t}^{DER}+C_{i,t}^{Retail}+C_{i,t}^{sat})
\tag{4-1}
```

PDF 64；adopted_scope；疑点：R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-2）设备成本](@id ch04-002)

```math
C_{i,t}^{DER}=c_i^{CHP}P_{i,t}^{CHP}+c_i^{RE}P_{i,t}^{RE}+c_i^{BS}(P_{i,t}^{BS,ch}+P_{i,t}^{BS,dis})
\tag{4-2}
```

PDF 64；adopted_scope；疑点：R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-3）零售成本](@id ch04-003)

```math
C_{i,t}^{Retail}=-\lambda_{i,t}^{P,sell}P_{i,t}^{sell}+\lambda_{i,t}^{P,buy}P_{i,t}^{buy}-\lambda_{i,t}^{H,sell}H_{i,t}^{sell}+\lambda_{i,t}^{H,buy}H_{i,t}^{buy}
\tag{4-3}
```

PDF 64；adopted_scope；疑点：R4-C02.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-4）不满意度](@id ch04-004)

```math
C_{i,t}^{sat}=\rho_i^{P,sat,0}+\rho_i^{P,sat,1}P_{i,t}^{D}+\rho_i^{P,sat,2}(P_{i,t}^{D})^2+\rho_i^{Q,sat,0}+\rho_i^{H,sat,1}H_{i,t}^{D}+\rho_i^{H,sat,2}(H_{i,t}^{D})^2
\tag{4-4}
```

PDF 64；adopted_scope；疑点：R4-C06, R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-5）AG0电平衡](@id ch04-005)

```math
P_{i,t}^{sell}-P_{i,t}^{buy}=P_{i,t}^{CHP}+P_{i,t}^{RE}-P_{i,t}^{BS,ch}+P_{i,t}^{BS,dis}-P_{i,t}^{D}-P_{i,t}^{EB/HP}
\tag{4-5}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-6）AG0热平衡](@id ch04-006)

```math
H_{i,t}^{sell}-H_{i,t}^{buy}=H_{i,t}^{CHP}+H_{i,t}^{EB/HP}-H_{i,t}^{D}
\tag{4-6}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-7）热电转换](@id ch04-007)

```math
H_{i,t}^{CHP}=\eta_i^{CHP}P_{i,t}^{CHP},\quad H_{i,t}^{EB/HP}=COP_i^{EB/HP}P_{i,t}^{EB/HP}
\tag{4-7}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-8）设备容量](@id ch04-008)

```math
P_i^{k,min}\le P_{i,t}^{k}\le P_i^{k,max},\quad k\in\{CHP,HP,EB,GT,RE\}
\tag{4-8}
```

PDF 64；adopted_scope；疑点：R4-C06.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-9）储能功率](@id ch04-009)

```math
0\le P_{i,t}^{BS,ch/dis}\le P_i^{BS,max}
\tag{4-9}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-10）储能能量](@id ch04-010)

```math
E_i^{BS,min}\le E_{i,t}^{BS}\le E_i^{BS,max}
\tag{4-10}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-11）储能状态原式](@id ch04-011)

```math
E_{i,t}^{BS}=E_{i,t}^{BS}+\eta_i^{BS}P_{i,t}^{BS,ch}-P_{i,t}^{BS,dis}/\eta_i^{BS}
\tag{4-11}
```

PDF 64；adopted_scope；疑点：R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-12）电负荷边界](@id ch04-012)

```math
(1-\zeta)\widehat P_{i,t}^{D}\le P_{i,t}^{D}\le(1+\zeta)\widehat P_{i,t}^{D}
\tag{4-12}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-13）热负荷边界](@id ch04-013)

```math
(1-\zeta)\widehat H_{i,t}^{D}\le H_{i,t}^{D}\le(1+\zeta)\widehat H_{i,t}^{D}
\tag{4-13}
```

PDF 64；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-14）P2P个体效用](@id ch04-014)

```math
U_i^{P2P}=U_i^0+\sum_{i'\ne i}\phi_{ii'}-\sum_{i'\ne i}\sum_t(\kappa_{ii'}P_{ii',t}+\varphi_{ii'}H_{ii',t})
\tag{4-14}
```

PDF 64；adopted_scope；疑点：R4-C04.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-15）支付互反](@id ch04-015)

```math
\phi_{ii'}+\phi_{i'i}=0
\tag{4-15}
```

PDF 65；adopted_scope；疑点：.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-16）合同互反](@id ch04-016)

```math
P_{ii',t}+P_{i'i,t}=0,\quad H_{ii',t}+H_{i'i,t}=0
\tag{4-16}
```

PDF 65；adopted_scope；疑点：.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-17）P2P电平衡原式](@id ch04-017)

```math
P_{i,t}^{sell}-P_{i,t}^{buy}=P_{i,t}^{CHP}+P_{i,t}^{RE}-P_{i,t}^{BS,ch}+P_{i,t}^{BS,dis}-P_{i,t}^{D}-P_{i,t}^{EB/HP}+\sum_{i'\ne i}P_{ii',t}
\tag{4-17}
```

PDF 65；adopted_scope；疑点：R4-C01.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-18）P2P热平衡原式](@id ch04-018)

```math
H_{i,t}^{sell}-H_{i,t}^{buy}=H_{i,t}^{CHP}+H_{i,t}^{EB/HP}-H_{i,t}^{D}+\sum_{i'\ne i}H_{ii',t}
\tag{4-18}
```

PDF 65；adopted_scope；疑点：R4-C01.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-19）运营商目标](@id ch04-019)

```math
\max U^{DHSO}=-(C^{EH}+C^{Grid}+C^{NO}-C^{Retail}-C^{NUC})
\tag{4-19}
```

PDF 65；adopted_scope；疑点：.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-20）能源站成本](@id ch04-020)

```math
C^{EH}=\sum_t\{c^{CHP}P_{n',t}^{CHP}+c^{BS}(P_{n',t}^{BS,dis}+P_{n',t}^{BS,ch})\}
\tag{4-20}
```

PDF 65；adopted_scope；疑点：R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-21）外部购电](@id ch04-021)

```math
C^{Grid}=\sum_t\lambda_t^G P_t^{PCC}
\tag{4-21}
```

PDF 65；adopted_scope；疑点：R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-22）网络动作成本](@id ch04-022)

```math
C^{NO}=\sum_t\sum_{(m,n)}c^{SA}a_{mn,t}^{SW}+\sum_{(j,k)}c^{VA}a_{jk}^{VL}
\tag{4-22}
```

PDF 65；documented_not_implemented；疑点：.

## [（4-23）零售收入](@id ch04-023)

```math
C^{Retail}=\sum_t\sum_i(\lambda_{i,t}^{P,buy}\widehat P_{i,t}^{buy}-\lambda_{i,t}^{P,sell}\widehat P_{i,t}^{sell}+\lambda_{i,t}^{H,buy}\widehat H_{i,t}^{buy}-\lambda_{i,t}^{H,sell}\widehat H_{i,t}^{sell})+C^{nonM}
\tag{4-23}
```

PDF 65；adopted_scope；疑点：R4-C06.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-24）网络服务收入](@id ch04-024)

```math
C^{NUC}=\sum_{t,i,i'}\kappa_{ii'}\widehat P_{ii',t}+\sum_{t,i,i'}\varphi_{ii'}\widehat H_{ii',t}
\tag{4-24}
```

PDF 65；adopted_scope；疑点：R4-C04.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-25）节点有功](@id ch04-025)

```math
P_{n,t}^{net*}=\sum_hP_{nh,t}-\sum_m(P_{mn,t}-l_{mn,t}r_{mn})+g_n v_{n,t}
\tag{4-25}
```

PDF 65；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-26）节点无功](@id ch04-026)

```math
Q_{n,t}^{net*}=\sum_hQ_{nh,t}-\sum_m(Q_{mn,t}-l_{mn,t}x_{mn})+b_n v_{n,t}
\tag{4-26}
```

PDF 66；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-27）支路电压降](@id ch04-027)

```math
v_{n,t}=v_{m,t}-2(r_{mn}P_{mn,t}+x_{mn}Q_{mn,t})+l_{mn,t}(r_{mn}^2+x_{mn}^2)+\Delta v_{mn,t}
\tag{4-27}
```

PDF 66；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-28）电压平方边界](@id ch04-028)

```math
\underline V^2\le v_{n,t}\le\overline V^2
\tag{4-28}
```

PDF 66；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-29）开关电压松弛原式](@id ch04-029)

```math
|\Delta v_{mn,t}|\le(\overline V^2-\underline V^2)u_{mn,t}^{SW}
\tag{4-29}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-30）有功边界](@id ch04-030)

```math
-z_{mn,t}P_{mn}^{max}\le P_{mn,t}\le z_{mn,t}P_{mn}^{max}
\tag{4-30}
```

PDF 66；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-31）无功边界](@id ch04-031)

```math
-z_{mn,t}Q_{mn}^{max}\le Q_{mn,t}\le z_{mn,t}Q_{mn}^{max}
\tag{4-31}
```

PDF 66；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-32）电流平方边界](@id ch04-032)

```math
-z_{mn,t}I_{mn}^{max}\le l_{mn,t}\le z_{mn,t}I_{mn}^{max}
\tag{4-32}
```

PDF 66；adopted_scope；疑点：R4-C05.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-33）电网二阶锥](@id ch04-033)

```math
\|(2P_{mn,t},2Q_{mn,t},l_{mn,t}-v_{m,t})\|_2\le l_{mn,t}+v_{m,t}
\tag{4-33}
```

PDF 66；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-34）电开关与方向](@id ch04-034)

```math
u_{mn,t}^{SW}=z_{mn,t}+z_{nm,t}
\tag{4-34}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-35）非根入边](@id ch04-035)

```math
\sum_{(m,n)}z_{mn,t}\le1,\quad n\in N^E\setminus n_0
\tag{4-35}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-36）根入边](@id ch04-036)

```math
\sum_{(n_0,m)}z_{n_0m,t}=0
\tag{4-36}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-37）拓扑变量](@id ch04-037)

```math
z_{mn,t},z_{nm,t}\in\{0,1\},\quad0\le a_{mn,t}^{SW}\le1
\tag{4-37}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-38）开关动作窗口一](@id ch04-038)

```math
\sum_{t'=t-T^{SA}+1}^{t}u_{mn,t'}^{SW}\le1-a_{mn,t}^{SW}
\tag{4-38}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-39）开关动作窗口二](@id ch04-039)

```math
\sum_{t'=t-T^{SA}+1}^{t}u_{mn,t'}^{SW}\le1-a_{mn,t-T^{SA}}^{SW}
\tag{4-39}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-40）开关变化](@id ch04-040)

```math
z_{mn,t}-z_{mn,t-1}\le a_{mn,t}^{SW},\quad z_{mn,t-1}-z_{mn,t}\le a_{mn,t}^{SW}
\tag{4-40}
```

PDF 66；documented_not_implemented；疑点：R4-C05.

## [（4-41）热质量流率边界](@id ch04-041)

```math
-v_{jk}M_{jk}^{max}\le m_{jk,t}\le v_{jk}M_{jk}^{max}
\tag{4-41}
```

PDF 66；adopted_scope；疑点：R4-C07.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-42）热节点质量守恒](@id ch04-042)

```math
m_{j,t}=\sum_{(j,k)}m_{jk,t}-\sum_{(l,j)}m_{lj,t}
\tag{4-42}
```

PDF 66；adopted_scope；疑点：R4-C07.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-43）热节点能量原式](@id ch04-043)

```math
H_{k,t}^{net*}=\sum_jH_{jk,t}^{in}-\sum_lH_{kl,t}^{out}
\tag{4-43}
```

PDF 66；adopted_scope；疑点：R4-C07, R4-C03.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-44）管道热量差](@id ch04-044)

```math
H_{jk,t}^{out}=H_{jk,t}^{in}-H_{jk,t}^{loss}
\tag{4-44}
```

PDF 66；adopted_scope；疑点：R4-C07.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-45）热支路容量](@id ch04-045)

```math
-v_{jk,t}H_{jk}^{max}\le H_{jk,t}^{in/out}\le v_{jk,t}H_{jk}^{max}
\tag{4-45}
```

PDF 66；adopted_scope；疑点：R4-C07.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-46）端口热量原式](@id ch04-046)

```math
m_{k,t}\Delta\tau^{min}\le H_{k,t}^{net*}\le m_{k,t}\Delta\tau^{max}
\tag{4-46}
```

PDF 66；adopted_scope；疑点：R4-C07, R4-C03.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-47）冻结损耗原式](@id ch04-047)

```math
H_{jk,t}^{loss}=u_{jk,t}^{VL}(\widehat\tau_{jk}^{S,in}+\widehat\tau_{jk}^{R,in}-2\widehat\tau_t^{AM})\frac{\epsilon_{jk}L_{jk}}{A\rho_w}
\tag{4-47}
```

PDF 67；adopted_scope；疑点：R4-C07, R4-C03.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-48）阀门与方向](@id ch04-048)

```math
u_{jk}^{VL}=v_{jk}+v_{kj}
\tag{4-48}
```

PDF 67；documented_not_implemented；疑点：R4-C05.

## [（4-49）热网非根入边](@id ch04-049)

```math
\sum_{(j,k)}v_{jk}\le1,\quad k\in N^H\setminus k_0
\tag{4-49}
```

PDF 67；documented_not_implemented；疑点：R4-C05.

## [（4-50）热网根入边](@id ch04-050)

```math
\sum_{(k_0,j)}v_{k_0j}=0
\tag{4-50}
```

PDF 67；documented_not_implemented；疑点：R4-C05.

## [（4-51）阀门变化](@id ch04-051)

```math
|v_{jk}-\widehat v_{jk,0}|\le a_{jk}^{VL},\quad v_{jk},v_{kj},a_{jk}^{VL}\in\{0,1\}
\tag{4-51}
```

PDF 67；documented_not_implemented；疑点：R4-C05.

## [（4-52）电计划一致](@id ch04-052)

```math
P_{n,t}^{net*}=P_{n,t}^{net}
\tag{4-52}
```

PDF 67；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-53）热计划一致](@id ch04-053)

```math
H_{k,t}^{net*}=H_{k,t}^{net}
\tag{4-53}
```

PDF 67；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-54）能源站电注入原式](@id ch04-054)

```math
P_{n',t}^{net}=P_{n',t}^{CHP}-P_{n',t}^{EB}+P_{n',t}^{BS,dis}-P_{n',t}^{BS,dis}
\tag{4-54}
```

PDF 67；adopted_scope；疑点：R4-C02.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-55）能源站热注入原式](@id ch04-055)

```math
P_{k',t}^{net}=H_{k',t}^{CHP}+H_{k',t}^{EB}
\tag{4-55}
```

PDF 67；adopted_scope；疑点：R4-C03.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-56）聚合商电注入原式](@id ch04-056)

```math
P_{n,t}^{net}=P_{i,t}^{sell}-P_{i,t}^{buy}-\sum_{i'\ne i}P_{ii',t}
\tag{4-56}
```

PDF 67；adopted_scope；疑点：R4-C01.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-57）聚合商热注入原式](@id ch04-057)

```math
H_{k,t}^{net}=H_{i,t}^{sell}-H_{i,t}^{buy}-\sum_{i'\ne i}H_{ii',t}
\tag{4-57}
```

PDF 67；adopted_scope；疑点：R4-C01.

采用范围对应API：`r4_ledger`；测试：`R4 model and ledger`。

## [（4-58）集中资源成本](@id ch04-058)

```math
\min C^{EH}+C^{Grid}+C^{NO}+\sum_i(C_i^{DER}+C_i^{sat})
\tag{4-58}
```

PDF 67；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。

## [（4-59）集中约束集](@id ch04-059)

```math
(4\!-\!7)\text{--}(4\!-\!13),\ (4\!-\!16)\text{--}(4\!-\!18),\ (4\!-\!25)\text{--}(4\!-\!57)
\tag{4-59}
```

PDF 67；adopted_scope；疑点：.

采用范围对应API：`build_r4_model`；测试：`R4 model and ledger`。
