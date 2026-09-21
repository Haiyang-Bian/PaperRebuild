# 第7.3节：设备接入与网络重构

上一轮在合成固定树上证明了一项容量矛盾，见[原报告](ch07-trading-results.md)。
本批保留该输入，加入图7-6的候选联络线及明确的开关位置，
分别检验接入参数与改变输送路径的作用。这里没有预设重构一定恢复可行或降低费用。

## 1. 原文、采用解释与合成参数

原PDF133–134（印刷116–117），图7-6/7-8说明热联络管6–27、32–16投入运行，
并扩大节点5、15热源的供热范围。原图也标出四条电联络线与部分支路开关。
本次按图中的可辨开关位置建模，未把每条边都变成可控：

| 网络 | 原支路可控位置 | 常开联络位置 |
|---|---|---|
| 电网 | 1–2、1–7、1–13、1–39、20–26、20–28 | 6–38、18–27、25–24、19–33 |
| 热网 | 3–4、9–29 | 6–27、32–16 |

电开关逐时控制，热阀门整日选择，沿用第4章文字解释。
全节点连通树、真实动作异或等推导沿用[第4章采用版本](ch04-network.md)，
不能把原式的索引或动作计数疑点静默恢复进来。
动作费5 CNY/次、两步稳定窗口、每电开关最多两次动作均为项目参数。
输入权威文件为`configs/r9/network-protocol.toml`；图中没有提供这些数值。

## 2. 接入参数怎样确定？

`legacy`保持父输入每条原支路的参数。`equipment`按全部设备额定功率、
实际背景负荷及灵活负荷上界构造节点绝对功率包络，再沿原树累加。
电网沿用明确的平方电压降设计预算，热网由参考温差、流速、密度确定管道截面，
再由圆筒绝热传热关系计算SI散热。所有规则先于规模优化冻结。

**equipment同时改变容量、阻抗和参考散热；跨设计的结果是组合参数差异。**
它不是原工程的扩建方案，也没有计入投资成本。

新电联络线取原树连接两端的路径总阻抗、路径最小功率与电流容量；
热联络管取原路径总长度和最小容量，再按自身设计流量确定截面与传热系数。
选择原路径总长是缺少实际路由时的显式假设，不声称为真实最短路线。

构造测试曾发现，直接相加原路径大管径的UA、同时取最小容量，会制造不相容的联络管：
参考散热可能超过其额定输送量。这一构造在正式优化前被输入检查拒绝，
现采用自身截面的规则。原失败输入和原第7.3节结果没有修改。

## 3. 连接、开关与物理流

对每个载能网络，选择`|N|-1`条边，并从根向每个其他节点发送一单位虚拟商品：

```math
\sum_e u_e=|N|-1,\quad
-(|N|-1)u_e\le F_e\le(|N|-1)u_e,\quad
\sum_{\delta^+(i)}F-\sum_{\delta^-(i)}F=
\begin{cases}|N|-1&i=r\\-1&i\ne r.\end{cases}
\tag{R9-RN1}
```

虚拟商品只证明连通。实际功率允许正负，热流可以逐时反向。
独立验证器另做图遍历，防止只满足边数却形成“孤岛＋环”。

电支路关闭时，P/Q及电流平方为零；电压降等式的放松量来自已知平方电压范围：

```math
\begin{aligned}
|P_{e,t}|&\le\bar P_e u^E_{e,t},&
|Q_{e,t}|&\le\bar Q_e u^E_{e,t},&
0\le\ell_{e,t}&\le\bar\ell_e u^E_{e,t},\\
|v_j-v_i+2(r_eP_{e,t}+x_eQ_{e,t})-(r_e^2+x_e^2)\ell_{e,t}|
&\le(v_{\max}-v_{\min})(1-u^E_{e,t}).
\end{aligned}\tag{R9-RN2}
```

此处v和其上下界都是电压幅值的平方。闭合时右侧为零；开路时没有强制两端电压相等。
SOCP与原支路等式仍由`electric=:socp/:exact`明确选择，独立保存判定。

动作量使用四条XOR线性不等式精确表达，即使动作费为零也必须正确：

```math
a^E_{e,t}=|u^E_{e,t}-u^E_{e,t-1}|,\quad
\sum_{k=\max(1,t-d+1)}^t a^E_{e,k}\le1,\quad
\sum_ta^E_{e,t}\le A_e^{\max},\qquad
a^H_p=|u^H_p-u^H_{p,0}|.
\tag{R9-RN3}
```

初始网络此前至少稳定d−1步；热阀门只相对初始状态计一次。
整日阀门状态不妨碍管内参考方向逐时改变。

```math
y^+_{p,t}+y^-_{p,t}=u^H_p,\quad
0\le m^\sigma_{p,t}\le\bar m_p y^\sigma_{p,t},\quad
0\le H^{\sigma,\mathrm{in/out}}_{p,t}\le\bar H_p y^\sigma_{p,t},\quad
H^{\sigma,\mathrm{out}}_{p,t}=H^{\sigma,\mathrm{in}}_{p,t}-L_p y^\sigma_{p,t}.
\tag{R9-RN4}
```

关闭阀门时两弧质量、热量、参考散热均为零；开启时只对一个方向计损耗。
端口和管道的热功率—质量流量包络、节点质量/能量守恒继续施加。
这些约束不认证完整温度混合、水压和动态暖管过程。

## 4. 费用与公平比较

```math
C_{\mathrm{system}}=C_{\mathrm{devices}}+C_{\mathrm{external}}+
C_{\mathrm{discomfort}}+
c^{SA}\sum_{e,t}a^E_{e,t}+c^{VA}\sum_pa^H_p.
\tag{R9-RN5}
```

动作费由运营商承担，单位是CNY/次，不额外乘时间步长。内部现金流仍两两抵消；
新增电热通道不会凭空产生记账收益。原始设备资源费用、外部购电和动作费用应分别核算。
终端拓扑自由，因此不宣称周期运行收益。

正式清单包含2种设计×2种拓扑策略×2种运营方式×2种电网形式，共16项。
同一设计内fixed/joint的支路参数与全部核心输入完全相同。
不同设计的结果只作参数组合对照，不称单纯拓扑收益；独立网络失败时不计算可实施协同收益率。
固定拓扑的零动作解属于允许重构的域；自由策略较差的候选应结合界和时限解释。

输入、源码、环境和方法顺序冻结后才启动求解。每方法共用600秒，
保留所有不可行、限时和数值未通过结果；直接集中求解不是PG、分布式或议价。
原固定树热割仅适用于原模型，不能把候选图中关闭管道的散热计入必须承担的损耗。

## 5. Julia与验证入口

```julia
parent = r9_trading_case("docs/reading/ch07", "configs/r9/trading-protocol.toml")
case = r9_reconfiguration_case(parent, "configs/r9/network-protocol.toml";
                              design=:equipment, policy=:joint)
model = build_r9_trading_model(case; electric=:socp) # 只建模
```

原`R9TradingCase`、建模、求解、保存与重读接口继续使用；
新输入版本为`r9-trading-case-v2`，旧版本不自动升级。
若使用开放求解器进行固定整数对照，必须完整提供储能、热方向、u_E及u_H的计划；
不能遗漏新开关后将整数模型当连续SOCP。
科学调用详见[交易API](ch07-trading.md)。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_network.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_network.jl
julia +1.12.6 --startup-file=no --project=. scripts/r9_network_study.jl freeze NEW_STUDY
julia +1.12.6 --startup-file=no --project=. NEW_STUDY/code/scripts/run_r9_network_batch.jl NEW_STUDY
```

16项正式运行已完成，见[结果与独立供热缺口](ch07-network-results.md)：
四个equipment集中候选通过本批检查；八项独立网络计划失败，且有全网供热上界矛盾。
没有候选实施拓扑切换，不宣称重构收益。构建与单元测试不是这些科学判定的替代品。
公式、符号和限制见[机器台账索引](ch07-network-generated.md)。

```@index
Pages = ["ch07-network.md"]
```

```@docs
r9_reconfiguration_case
validate_r9_network
```
