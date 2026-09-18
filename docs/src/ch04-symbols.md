# 第4章符号与采用解释

<!-- GENERATED: scripts/ch04_docs.jl -->

主符号和语义标签沿用第2章规则；actor含运营商及聚合商，time为时段，E另含0时刻。

| ID / Julia | 原符号 | 含义 | 单位 | 域 / 维度 |
|---|---|---|---|---|
| `P_net` | ``P_{i,t}^{net}`` | 向电网净注入 | MW | 实数 / actor × time |
| `H_net` | ``H_{i,t}^{net}`` | 向热网净注入 | MW | 实数 / actor × time |
| `P_CHP` | ``P_{i,t}^{CHP}`` | CHP电出力 | MW | 非负 / actor × time |
| `P_PV` | ``P_{i,t}^{RE}`` | 可再生实际出力 | MW | 0至可用出力 / actor × time |
| `P_HP` | ``P_{i,t}^{HP}`` | 热泵用电 | MW | 非负 / actor × time |
| `P_EB` | ``P_{i,t}^{EB}`` | 电锅炉用电 | MW | 非负 / actor × time |
| `H_src` | ``H_{i,t}^{src}`` | 产热端口；实现扩展 | MW | 非负 / actor × time |
| `P_D` | ``P_{i,t}^D`` | 实际电负荷 | MW | 配置界内 / actor × time |
| `H_D` | ``H_{i,t}^D`` | 实际热负荷 | MW | 配置界内 / actor × time |
| `P_ch` | ``P_{i,t}^{BS,ch}`` | 储能充电 | MW | 非负 / actor × time |
| `P_dis` | ``P_{i,t}^{BS,dis}`` | 储能放电 | MW | 非负 / actor × time |
| `E` | ``E_{i,t}^{BS}`` | 储能能量 | MWh | 配置界内 / actor × 0:T |
| `z` | ``z_t^{BS}`` | 充电互斥；项目新增 | 1 | 0或1 / time |
| `P_grid` | ``P_t^{PCC}`` | 运营商外部购电 | MW | 0至购电界 / time |
| `Q_grid` | ``Q_t^{PCC}`` | 外部无功 | Mvar | 配置界内 / time |
| `P_branch` | ``P_{mn,t}`` | 支路有功 | pu | 可正可负 / branch × time |
| `Q_branch` | ``Q_{mn,t}`` | 支路无功 | pu | 可正可负 / branch × time |
| `v` | ``v_{n,t}`` | 电压幅值平方 | pu² | 正 / node × time |
| `ell` | ``l_{mn,t}`` | 电流幅值平方 | pu² | 非负 / branch × time |
| `m_pipe` | ``m_{jk,t}`` | 供水质量流率 | kg/s | 固定方向非负 / pipe × time |
| `m_src` | ``m_{j,t}^{src}`` | 源端口流率；实现扩展 | kg/s | 非负 / actor × time |
| `m_load` | ``m_{j,t}^{load}`` | 荷端口流率；实现扩展 | kg/s | 非负 / actor × time |
| `H_in` | ``H_{jk,t}^{in}`` | 管道入口热功率 | MW | 非负 / pipe × time |
| `H_out` | ``H_{jk,t}^{out}`` | 管道出口热功率 | MW | 非负 / pipe × time |
| `loss` | ``H_{jk,t}^{loss}`` | 冻结管道热损耗 | MW | 非负 / pipe |
| `trade_P` | ``P_{ii',t}`` | 双边出售电量率 | MW | 反对称 / pair × time |
| `trade_H` | ``H_{ii',t}`` | 双边出售热量率 | MW | 反对称 / pair × time |
| `retail_buy` | ``P_{i,t}^{buy},H_{i,t}^{buy}`` | 向运营商购买 | MW | 非负 / carrier × actor × time |
| `retail_sell` | ``P_{i,t}^{sell},H_{i,t}^{sell}`` | 向运营商出售 | MW | 非负 / carrier × actor × time |
| `payment` | ``\phi_{ii'}`` | P2P总收款，正为收到 | USD_synthetic | 实数 / actor |
| `cost` | ``C`` | 资源或效用成本，类别必须注明 | USD_synthetic | 实数 / actor |
| `utility` | ``U`` | 现金收入减资源成本及不满意度 | USD_synthetic | 实数 / actor |
| `eta_CHP` | ``\eta_i^{CHP}`` | 热电比，不是发电效率 | 1 | 非负 / actor |
| `COP_HP` | ``COP_i^{HP}`` | 热泵性能系数 | 1 | 正 / actor |
| `eta_BS` | ``\eta_i^{BS}`` | 充放效率；项目分ch/dis | 1 | 0至1 / actor |
| `cp_J_kgK` | ``c_w`` | 水比热；单位恢复 | J/(kg K) | 正 / scalar |
| `dt_h` | ``\Delta t`` | 时间步；项目显式恢复 | h | 正 / scalar |
| `U_W_mK` | ``U_{jk}`` | 每根管线传热系数；项目定义 | W/(m K) | 非负 / pipe |
| `delta_T` | ``\Delta T`` | 源荷端口温差边界 | K | 正 / role |
| `price` | ``\lambda,\kappa,\varphi`` | 电热价格或服务费，按类别区分 | USD_synthetic/MWh | 非负 / carrier |
| `zeta` | ``\zeta`` | 负荷可调比例 | 1 | 0至1内 / actor |
| `a_sat` | ``a_i^P,a_i^H`` | 凸不满意度系数；项目参数化 | USD_synthetic/(h MW²) | 非负 / actor |
| `indices` | ``i,i',t,m,n,j,k`` | 主体、时段、电节点、热节点 | 1 | 有限整数集合 / sets |

## 采用解释与来源缺口

### R4-C01 交易符号

原式：17, 18, 56, 57；状态：adopted_derivation。

文字出售为正与方程相反。采用P_net=sell-buy+sum(export)，同时变换双方。

验证依据：守恒手算0.2MW出售、0.3MW购买。

### R4-C02 时间与储能

原式：1, 2, 3, 4, 11, 20, 21, 54；状态：adopted_derivation。

恢复Δt与E[t-1]；4-54第二个dis改ch。新增逐时互斥与周期边界。

验证依据：能量单位与一步递推；非原文数值匹配。

### R4-C03 热端口与损耗

原式：43, 46, 47, 55；状态：adopted_derivation。

统一净注入；分源荷非负端口，恢复cp/1e6；SI参考温度损耗；4-55用H。

验证依据：逐管能量守恒、量纲和零损耗极限；不验证动态热网。

### R4-C04 有向服务费

原式：14, 24；状态：adopted_derivation。

对称费率下有向净量可能抵消。按每对实际出售量只收卖方一次。

验证依据：收款方运营商有同额收入，主体效用之和不变。

### R4-C05 固定拓扑与平方量

原式：29, 32, 34, 35, 36, 37, 38, 39, 40, 48, 49, 50, 51；状态：adopted_derivation。

首批仅固定树、l>=0与Imax平方。重构采用N1–N6的连通、开路和动作解释，详见network.toml。

验证依据：旧固定拓扑判定保留。新重构含独立图校验与单时段72项穷举；原电网等式另验。

### R4-C06 不满意度与范围

原式：4, 8, 23；状态：adopted_derivation。

采用凸且递减的二次特例，Q/H混排另记；GT/非市场用户不启用。

验证依据：导数、凸性、边界检查；不包含负荷时移能量守恒。

### R4-C07 第26篇引文

原式：41, 42, 43, 44, 45, 46, 47；状态：source_correspondence_unresolved。

已定位作者接受稿；尚未建立逐管公式与被引文献逐式等价证据。

验证依据：解释与来源缺口分开，采用式不冒称引文已证实。
