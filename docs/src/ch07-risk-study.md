# 第7.4节：三方案风险比较与冻结输入

本批接续[备用输入基准](ch07-reserve.md)，研究相同设备和历史下怎样承诺备用，
以及少量供热舒适性风险是否改变可交付容量和费用。运行结果按本页后续实际记录评价，
不以作者表7-13/14的数值为调参目标。

## 1. 哪些差异属于作者，哪些属于项目

原PDF135–137给出100情景和5%风险阈值，描述3A不牺牲舒适性且100%响应，
3B采用已知概率的机会约束，3C应对概率未知。连续调用集合、逐日数据和概率半径没有完整输入。
本项目采用固定支持对照，保留这些缺口，不将有限个情景的鲁棒性扩大到任意未见调用。

三方案统一`delta=0`，显式覆盖原输入模板的0.1。这使交付容差不成为比较中的额外因素。
3B的“已知”仅指训练代表的经验频数已给定，不表示已经知道真实分布。
3C半径0.01在优化之前声明，尚不是数据校准出的置信半径。

## 2. 从完整日轨迹到场景模型

使用2000训练日、500验证日、1000测试日及不同种子。各日独立生成，日内存在AR相关性；
这是一组假设的合成分布，不是示范区实测历史。PV为共同天气下的额定比例，备用调用为有符号比例：

```math
P_{g,s,t}^{PV,avail}=\bar P_g^{PV}p_{s,t}^{PV},\qquad
\alpha_{s,t}^{up}=\max(a_{s,t},0),\qquad
\alpha_{s,t}^{down}=\max(-a_{s,t},0).
\tag{R9-RK1}
```

正上调表示减少从电网购电；同一时段上下调用不会同时为正。热历史、初始室温、
设备容量、负荷、环境、价格和终端条件均与[基准模板](ch07-reserve.md)相同。
共同备用铭牌盒由设备电功率范围加本地P2H电输入容量得到，它不是可交付能力的认证。

三方案均要求：

```math
\sum_t\Delta t\,\left|P_{s,t}^{delivery}-
 (\alpha_{s,t}^{up}R_t^{up}-\alpha_{s,t}^{down}R_t^{down})\right|\le
\delta\sum_t\Delta t\,(R_t^{up}+R_t^{down})=0.
\tag{R9-RK2}
```

只用训练集聚类，选每簇最接近中心的原始日，概率为簇频数/2000；100个代表的原值与哈希均保存。
验证、测试集不进入聚类、成本调参或半径选择。复用R6的纯抽样/保存函数，
其中六方法字段是旧数据schema的兼容元数据；本批实际只执行3A/3B/3C，不接入策略报价市场。

## 3. 三种优化问题怎样区别

距离为整条PV与调用轨迹的归一化RMS，调用比例先除以跨度2。
对固定代表``\omega_i``，以质量运输定义概率集合：

```math
\mathcal D(\rho)=\left\{q_i=\sum_j\Pi_{ij}:\Pi\ge0,
\ \sum_i\Pi_{ij}=\hat p_j,\ \sum_{ij}d_{ij}\Pi_{ij}\le\rho\right\}.
\tag{R9-RK3}
```

费用和舒适事件分别求各自最坏分布，不能复用费用最坏分布来认证风险。
事件是任一楼宇、任一时段舒适越界；室温的物理域、设备和终端条件仍为硬约束。

```math
\begin{array}{c|cc}
 & \rho & \epsilon\\\hline
3A&\max_{i,j}d_{ij}&0\\
3B&0&0.05\\
3C&0.01&0.05
\end{array}
\qquad
\min_x C^{DA}(x)+\sup_{q\in\mathcal D(\rho)}\sum_s q_sQ_s(x),\quad
\sup_{q\in\mathcal D(\rho)}\sum_s q_sz_s\le\epsilon.
\tag{R9-RK4}
```

所有训练概率严格为正；3A的零风险强制全部代表保持舒适。
半径取支持直径时，任意概率分布均能由经验质量运输得到，因此费用退化为支持上的最大费用。
半径为零时，当前不同轨迹的距离严格为正，退化为经验期望。
这两个极限另有解析测试。

最坏费用、经验期望费用、舒适事件概率、备用容量和交付误差分开报告。
三方案目标口径不同，直接相减最坏目标不能称实现的经济收益；后续使用同日样本外成本作配对比较。

## 4. 先冻结，再测规模

预运行固定取冻结顺序的前4个代表，并按这4项训练频数重标概率。
它只测量构建、求解和独立验算开销，不能用于判断100情景下5%风险预算的收益。
正式运行保持全部100点，不在看过结果后换代表、改容量或修改风险门槛。

每方法独立Julia进程，共享600秒；60秒预留存档。模型、风险、费用界及完整进程预算分别判定。
冻结输入的代码快照独立运行；缺许可、超时和无证书保留状态，不自动改用其他模型。
样本外优化须等待全部训练候选锁定；当前尚未完成该步骤。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_risk.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_risk.jl
julia +1.12.6 --startup-file=no --project=. scripts/r9_reserve_study.jl freeze NEW_STUDY
julia +1.12.6 --startup-file=no --project=. scripts/r9_reserve_study.jl check NEW_STUDY
julia +1.12.6 --startup-file=no --project=. NEW_STUDY/code/scripts/run_r9_reserve_batch.jl NEW_STUDY pilot NEW_PILOT_OUTPUT
julia +1.12.6 --startup-file=no --project=. NEW_STUDY/code/scripts/run_r9_reserve_batch.jl NEW_STUDY full NEW_FULL_OUTPUT
```

所有输出使用新目录。冻结检查不求解、不申请Gurobi许可；批次运行会申请现有本机许可。
实际终止状态与范围见[预运行和规模结果](ch07-risk-results.md)。
原式/项目符号见[台账](ch07-risk-generated.md)。

```@index
Pages = ["ch07-risk-study.md"]
```

```@docs
R9ReserveStudySpec
load_r9_reserve_study
r9_reserve_risk_case
```
