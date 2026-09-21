# 第7.3节迁移：八聚合商输入与交易模型

这一节点接续[固定流量实验](ch07-fixed.md)，转向“哪些主体供能、交易如何经过网络、收益怎样记账”。
规模输入、模型构造和预算/保存/独立重验接口已经建立，解析例已运行；
**44/38节点的正式交易实验尚未执行**。
第7.2节的对偶/KKT问题保持开放，本节点不使用其梯度或参考调度作初值。

## 1. 从原表到可运行输入

原PDF127–128、132–135及表7-6至7-9的转录保存在`docs/reading/ch07/`。
采用协议是`configs/r9/trading-protocol.toml`，在优化前指定替代规则。
完整原始参数仍缺失，因此案例标记为`synthetic`，不能将拓扑相同称为作者同输入。

| 内容 | 已知原记录 | 本节点采用解释 |
|---|---|---|
| 节点与主体 | 44电节点、38热节点、8聚合商 | 保留原编号；DSO多设备位置与主体节点分别登记 |
| 负荷 | 表7-9合计15.52 MW电、5.53 MW热，正文写1.5倍 | 表列值按放大前解释，只对主体乘一次1.5 |
| 背景负荷 | 总电峰45.67 MVA、热峰7.23 MW；节点分配缺失 | 电力采用项目功率因数0.9；减未放大表值后，余量在其他节点均分 |
| 共用节点 | A4和A8共用热节点26 | 两份主体负荷求和，背景不再在H26重复计入 |
| 资源身份 | 资源栏写HP，参数栏写EB3/4及效率0.94/0.92 | 按数值表转换关系；不另加未列设备或假定COP |
| 储能 | 两组电池各0.5 MW/2 MWh；文字提及储热而未给容量 | 两组储热各0.5 MW/2 MWh为明确合成替代；效率和周期边界逐项登记 |
| 电价/结算 | 原时分电价可读，完整零售/分配细节不足 | 外部电价用原时段表，零售、P2P和服务费用协议中的教学规则 |

背景峰值分别为25.583 MW电、1.70 MW热；主体放大后为23.28 MW电、8.295 MW热。
曲线、功率因数、网络参数和负荷偏好都是替代输入，不能由作者结果反向拟合。
保留7.1的2/3/3 MW光伏，不带入7.2的6 MW扩容；不带入WMM历史或终端温度。
新联络线仅登记为未启用，不在本节点进行重构。

13台设备包括2台CHP、4台电热转换、3组PV、2组电池、2组替代储热。
CHP1保留3 MW电功率下限；CHP2可降至0。不从一条启动费记录自行推断未公开的启停费用模型。

## 2. 为什么主体、设备与网络节点要分开？

旧`R4Case`采用三个主体/节点的微型结构。这里新增`R9TradingCase`，保留旧接口和结果。
主体可以买卖电和热，但两种资源并不处于同一个节点编号。DSO还有多个设备地点。

```math
\begin{aligned}
n_{a,t}^{P}&=\sum_{g:\operatorname{owner}(g)=a}
 (P_{g,t}^{\rm gen}-P_{g,t}^{\rm cons})-P_{a,t}^{D},\\
n_{a,t}^{H}&=\sum_{g:\operatorname{owner}(g)=a}
 (H_{g,t}^{\rm gen}-H_{g,t}^{\rm cons})-H_{a,t}^{D}.
\end{aligned}\tag{R9-T1}
```

净注入为正表示出售余量。网络平衡按设备和负荷的实际电/热节点分别求和，
不把DSO的全部设备集中到一个虚构节点，也不把P2P合同量当作指定线路潮流。

## 3. 设备、偏好与储能

```math
\begin{aligned}
H_{g,t}^{\rm CHP}&=\rho_g P_{g,t}^{\rm CHP},\qquad
H_{g,t}^{\rm P2H}=\eta_gP_{g,t}^{\rm P2H},\\
w_{a,t}^{P}&\ge k_a^{P}(\widehat P_{a,t}-P_{a,t}^{D})^2,\qquad
w_{a,t}^{H}\ge k_a^{H}(\widehat H_{a,t}-H_{a,t}^{D})^2.
\end{aligned}\tag{R9-T2}
```

功率用MW；偏好费用率用CNY/h，系数为CNY/(h·MW²)，乘时长后进入费用。
`k≥0`才是凸二次关系。±10%负荷调节边界不改变偏好中心，当前没有跨时段负荷转移守恒。
源设备的容量用原表对应电/热侧解释，不能把额定热功率直接当电输入容量。

```math
\begin{aligned}
E_{g,t+1}&=(1-\delta_g)^{\Delta t}E_{g,t}
 +\Delta t(\eta_g^{\rm ch}q_{g,t}^{\rm ch}-q_{g,t}^{\rm dis}/\eta_g^{\rm dis}),\\
0\le q_{g,t}^{\rm ch}&\le\overline q_gz_{g,t},\quad
0\le q_{g,t}^{\rm dis}\le\overline q_g(1-z_{g,t}),\quad z_{g,t}\in\{0,1\},\\
E_{g,1}&=E_{g,T+1}=E_g^{\rm initial}.
\end{aligned}\tag{R9-T3}
```

电池使用电功率，储热使用热功率；能量单位都是MWh。状态有T+1个时间点。
损耗参数定义为一小时能量损失比例，非整小时使用显式幂换算。吞吐费用按充电加放电计，
这是对原电池50元/MWh计费口径的项目解释；原文未确认该计费侧。

## 4. 电网原式与热网抽象的边界

采用第4章固定径向支路模型，功率先除以共同MVA基准。

```math
\begin{aligned}
v_{j,t}&=v_{i,t}-2(r_{ij}P_{ij,t}+x_{ij}Q_{ij,t})
 +(r_{ij}^2+x_{ij}^2)\ell_{ij,t},\\
P_{ij,t}^2+Q_{ij,t}^2&\le v_{i,t}\ell_{ij,t}
 \quad\text{或原等式}\quad
P_{ij,t}^2+Q_{ij,t}^2=v_{i,t}\ell_{ij,t}.
\end{aligned}\tag{R9-T4}
```

`electric=:socp`和`:exact`是显式选择。原式版本含非凸二次等式，不能用SOCP结果替它宣称最优。
44/1/20处多电压设备采用协议中的理想额定变压器等值；阻抗、容量由输入包络设计，
不是从原图长度读出来。构建器回报实际约束类型和整数变量是否保留。

热网先采用稳态质量/能量包络。为了不预先排除聚合商反向售热，每个原管对具有两个互斥方向：

```math
\begin{aligned}
y_{p,t}^{+}+y_{p,t}^{-}&=1,\quad y_{p,t}^{\sigma}\in\{0,1\},\\
0\le m_{p,t}^{\sigma}&\le\overline m_p y_{p,t}^{\sigma},\quad
0\le H_{p,t}^{\sigma,\rm in/out}\le\overline H_p y_{p,t}^{\sigma},\\
H_{p,t}^{\sigma,\rm out}&=H_{p,t}^{\sigma,\rm in}-L_p y_{p,t}^{\sigma},\\
10^{-6}c_p\Delta T_{\min}m_{p,t}^{\sigma}
 &\le H_{p,t}^{\sigma,\rm in/out}
 \le10^{-6}c_p\Delta T_{\max}m_{p,t}^{\sigma},\\
L_p&=10^{-6}U_p d_p(S_p^{\rm ref}+R_p^{\rm ref}-2T_p^{\rm amb}).
\end{aligned}\tag{R9-T5}
```

这里cₚ为J/(kg·K)，U为W/(m·K)，长度d为m，L为MW。供回水散热各计一次。
节点的源/荷流量分别非负，再按弧方向施加质量和热量守恒。
固定拓扑不等于固定方向；正反两弧不能同时开放制造循环。

这是保持温热管网的参考散热规则，即使负荷较小也不自动取消管道散热。
入口/出口热功率包络**没有建立共同供回温度、混合、水压或时延状态**；
通过这些检查只说明所声明的稳态抽象成立，后续还要检查温度场相容性。

## 5. 集中、独立运营与账本

`stage=:central`最小化联合资源费用；`stage=:local, actor=a`按零售价优化单个聚合商；
`stage=:network, frozen=plans`冻结全部独立计划，再求运营商网络调度。
冻结用附加等式，保留原容量边界；网络失败不能由悄悄调整聚合商来变成成功。
这三个路径由`solve_r9_trading_case`编排；独立运营保留逐主体原计划及网络阶段的冻结副本。
网络失败时不回到主体阶段重新调整计划。

```math
\begin{aligned}
C_{\rm system}&=\sum_t\Delta t\left[
\pi_t^{\rm grid}P_t^{\rm grid}+\sum_g c_gq_{g,t}
 +\sum_a(w_{a,t}^{P}+w_{a,t}^{H})\right],\\
U_a^{\rm account}&=C_a^{\rm cash}-C_a^{\rm resource}
 -C_a^{\rm discomfort}-C_a^{\rm external},\\
\sum_a C_a^{\rm cash}&=0,\qquad\sum_a U_a^{\rm account}=-C_{\rm system}.
\end{aligned}\tag{R9-T6}
```

其中q按设备类型取发电或充放吞吐；外部电费由DSO承担。
P2P按主体ID依次匹配余缺，剩余量与DSO结算。服务费每笔仅由卖方支付DSO一次。
替代结算价只改变主体现金流，不反向改变物理调度或资源费用。
缺少原文总效用常数时，不能把这里的示例净收支与表7-11绝对收益直接对比，也未完成议价。

## 6. 手算验收与下一步

解析例使用3电/3热节点和2聚合商，与规模输入明确分开：

- 2 MW光伏供两份各1 MW电负荷，另由电网供1 MW、效率为1的电热转换设备，
  满足1 MW热负荷。运行1小时、电价100元/MWh，资源费用应为100元。
- 将热源移动到末端并把热负荷移动到首端后，反向输热应保持同一守恒费用。
- 两个管对每对损耗0.00012 MW时，供热为1.00024 MW，费用应为100.024元。
- 半小时两时段、价差10/100元/MWh，理想电池从0.5 MWh充至1再回到0.5，
  可将前述两时段费用从55元降至10元。这是解析测试，不是规模储能收益。
- 人为增加零阻抗线路的电流平方量，SOCP仍可能通过，但原电流关系必须失败。
  修改独立冻结负荷、储能末态或管道出口热量也必须被独立检查发现。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_trading.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_trading.jl
julia +1.12.6 --startup-file=no --depwarn=error --project=. scripts/test_r9_trading_runs.jl
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/test_r9_trading_runs.jl --gurobi NEW_TEST_DIRECTORY
```

下一节点先冻结规模运行的完整输入、源码及方法规则，
再执行独立运营网络校核、集中SOCP及原电网等式参考。完整方法的进程/JIT时间也须记录，
不能只把求解器报告时间当作总预算。
同输入调度可实施后再迁移分布式协调、重构和议价；本节点不以成功构建14989个变量的模型代替规模实验。

## 7. 如何运行、保存和解释结果？

新增67项开放运行/存档检查通过。本机Gurobi另有22项小例检查通过：
集中与独立运营的SOCP/原等式四项资源费用都是100元，原等式两项通过原支路检查；
SOCP两项保留原等式未通过的判定。该零阻抗解析例不能用来推断规模松弛是否紧。

运行接口用同一个截止时间连接建模、各主体局部调度和网络校核。总预算不超过600秒；
各局部阶段不超过60秒，并为最终独立回代保留总预算的10%（至多60秒）。
可用`deadline`传入外层脚本启动时确定的更早截止时间，以覆盖加载与JIT。
本节点没有测得规模计算时间或算法加速比。

示意调用如下；规模整数模型需要在可选求解环境中显式提供工厂`optimizer`，
普通包导入与结果重验不加载商业求解器。Clarabel仅用于明确固定全部整数选择的连续小例。

```julia
result = solve_r9_trading_case(case; optimizer, operation=:independent,
                              electric=:socp, budget_sec=600.0)
path = save_r9_trading_run(case, result; directory="results/runs/NEW_BATCH",
                           run_id="independent-socp")
checked = read_r9_trading_run(path)
```

保存目录必须不存在。每个运行包含原始输入、逐阶段候选/状态/界、CSV残差、完整Julia源码与锁文件。
独立计划与网络冻结控制逐值相等；不因网络校核失败而删除先前的局部成功。
保存前后科学源码必须一致。默认重读运行自己的源码版本，先查完整清单/哈希，再逐式回代；
后续代码变化不会静默改写历史判定。哈希用于完整性核对，不是作者身份或数字签名。

| 字段 | 应怎样理解 |
|---|---|
| `status` | 求解停止事实；限时有候选、限时无候选、已证明不可行、许可或数值失败分别记录 |
| `model_pass` | 所选模型与全部冻结计划通过独立检查 |
| `electric_original_pass` | 原支路等式通过；SOCP通过不能替代此项 |
| `heat_energy_mass_pass` | 稳态能量/质量包络通过；不是完整温度场认证 |
| `ledger_pass` | 内部现金流、费用与收支恒等式通过 |
| `cost_optimization_complete` | 原停止状态、模型检查与有效费用界均通过；局部计划的界也不能缺失 |
| `wall_budget_pass` | 记录的总耗时是否在可用预算内，独立于模型是否可行 |

测试中的容量反例让两个聚合商局部成功后，运营商网络报告不可行；
该运行没有可实施系统费用，也不能报告集中协调的收益率。
同输入、同固定整数选择的两个已验证候选才允许计算资源费用差，
不同固定储能选择不能只因都写着“固定整数”而混比。
费用差仍是候选差，不是全局最优性间隙。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_trading_runs.jl check RUN_DIRECTORY
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_trading_runs.jl compare AG0_DIRECTORY CENTRAL_DIRECTORY
```

退出成功表示存档可核对、原判定可重现；即使原记录是不可行，检查脚本也可成功重验这一事实。
没有科学新结果时不生成新的收益曲线；正式规模图表仍在下一节点。

公式和符号权威清单见[台账索引](ch07-trading-generated.md)。

```@index
Pages = ["ch07-trading.md"]
```

```@docs
R9TradingCase
load_r9_trading_case
r9_trading_case
build_r9_trading_model
validate_r9_trading_solution
r9_trading_ledger
solve_r9_trading_case
validate_r9_trading_run
save_r9_trading_run
read_r9_trading_run
compare_r9_trading_runs
```
