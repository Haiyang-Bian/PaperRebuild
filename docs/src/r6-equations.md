# R6统计公式与符号

由sample-out.toml生成；R6-S全部为项目推导编号。

## R6-S1

~~~math
\mathcal D_{\rm tr}\cap\mathcal D_{\rm va}=\mathcal D_{\rm tr}\cap\mathcal D_{\rm te}=\mathcal D_{\rm va}\cap\mathcal D_{\rm te}=\varnothing,\quad T\Delta t=24\ {\rm h}
\tag{R6-S1}
~~~

相交按独立采样身份判断，不要求随机数值绝不重复。只用训练拟合、验证选参数；测试不得参与调参。

API：[`R6Protocol`](@ref)；测试：`R6-SPLIT`。

## R6-S2

~~~math
w_{d,t}=\rho_w w_{d,t-1}+\sqrt{1-\rho_w^2}\xi_{d,t},\quad p_{d,t}^{\rm PV}=\bar p_t\,\sigma(b+s_d z_d+s_w w_{d,t}),\quad a_{d,t}=\tanh(s_a u_{d,t})
\tag{R6-S2}
~~~

u采用独立同形式AR过程；日初w/u与日因子z为独立标准正态。sigma为logistic。全部参数为合成项目设定，p为额定容量比例，a正值上调、负值下调。

API：[`r6_generate_trajectories`](@ref)；测试：`R6-SPLIT`。

## R6-S3

~~~math
U_{k,n}=\begin{cases}1,&k=n,\\p:\ \sum_{j=0}^{k}{n\choose j}p^j(1-p)^{n-j}=\alpha,&k<n,\end{cases}\qquad L_{k,n}=1-U_{n-k,n},\quad\alpha=0.05
\tag{R6-S3}
~~~

两端各自是单侧95%Clopper–Pearson界；不是共同覆盖95%的双侧区间。与A5的Beta分位数定义等价。

API：[`r6_binomial_bounds`](@ref)；测试：`R6-CP`。

## R6-S4

~~~math
L=L_{k,n},\qquad U=U_{k+u,n},\qquad {\rm decision}=\begin{cases}{\rm supported},&U\le\epsilon,\\{\rm rejected},&L>\epsilon,\\{\rm inconclusive},&{\rm otherwise}.\end{cases}
\tag{R6-S4}
~~~

k已知联合违约，u未知；未知全留在n中。上界作最坏计数，不把求解失败当作成功。主要正式风险检验为DRJCC联合室温，其余为比较性结果。

API：[`r6_risk_evidence`](@ref)；测试：`R6-UNKNOWN`。

## R6-S5

~~~math
\Delta C_d=C_d^A-C_d^B,\qquad \widehat{\Delta C}=\frac1n\sum_{d=1}^{n}\Delta C_d
\tag{R6-S5}
~~~

按同一完整轨迹ID配对，自助法重采样整条差值。缺失任一方法费用时保留缺失数量，不生成总体排名与区间。

API：[`r6_paired_costs`](@ref)；测试：`R6-PAIR`。

## R6-S6

~~~math
d(i,j)=\sqrt{\frac1{2T}\sum_t\left[(p_{i,t}^{\rm PV}-p_{j,t}^{\rm PV})^2+\left(\frac{a_{i,t}-a_{j,t}}2\right)^2\right]},\quad q_j=\frac{|\mathcal C_j|}{N_{\rm tr}}
\tag{R6-S6}
~~~

固定无量纲尺度的整轨迹RMS距离；Lloyd中心拟合后选簇内最近的原始观测轨迹。后一步是项目规则，不能冒称作者中心选法。

API：[`r6_fit_representatives`](@ref)；测试：`R6-CLUSTER`。

## 符号

| ID | 符号 | 含义 | 单位 | Julia映射 |
|---|---|---|---|---|
| r6-day | ``d,t`` | 独立日、日内时段索引 | 1 | `values[channel,t,i]` |
| r6-pv | ``p_{d,t}^{\rm PV}`` | PV额定容量出力比例 | 1 | `values[1,t,i]` |
| r6-call | ``a_{d,t}`` | 正上调、负下调的备用调用比例 | 1 | `values[2,t,i]` |
| r6-counts | ``n,k,u`` | 完整轨迹总数、已知联合违约数、未知数 | trajectory | `n, violations, unknown` |
| r6-bounds | ``L,U,\epsilon`` | 违约概率单侧下界、上界及预声明风险上限 | 1 | `lower, upper, epsilon` |
| r6-cost | ``\Delta C_d`` | 同一轨迹两方法总费用A减B | USD | `delta` |

## 原文与采用边界

### R6-A01

PDF98/印刷81，第5.6.1节；状态：`author_reported`。

原文记录：某地区历史数据，k-means生成100个代表性可再生出力场景，1-epsilon=95%。

项目处理：保留100代表场景目标；原历史样本、轨迹、权重与聚类规则未闭合，项目使用显式合成来源。

### R6-A02

PDF101/印刷84，第5.6.3节；状态：`unresolved_sampling_relationship`。

原文记录：Monte Carlo生成1000个场景分析样本外；同页SP解释又说对生成的1000个场景赋予概率。

项目处理：不能据此判断1000训练/测试样本是否相同，也不能断言作者存在数据泄漏。项目明确分离2000训练、500验证、1000测试完整日。

### R6-A03

PDF100–102/印刷83–85，第5.6.3节；状态：`model_detail_missing`。

原文记录：D、SP、RO、DRO、CCP、DRJCC六方案；D一处称只考虑日前而不考虑调用，另一处称采用平均情景。

项目处理：R6采用训练均值PV和零调用的D；SP/CCP采用同一100训练代表的经验分布，RO是该有限支持上的最坏情况，DRO/DRJCC用冻结RMS运输球。是项目可比基准，不声称原文未公开细节已唯一确定。

### R6-A04

PDF100表5-5；PDF102图5-8、表5-6；状态：`confirmed_arithmetic_inconsistency`。

原文记录：表5-5方案5总成本8467.02、日前5105.33、实时3361.21；图5-8和表5-6实时为3361.69。

项目处理：8467.02-5105.33=3361.69。保留两个原值，项目独立核算总/日前/实时费用，不选择有利原值。

### R6-A05

PDF102/印刷85，图5-8；状态：`author_metric_scope`。

原文记录：图注明确样本内/样本外表现比较为实时运行成本。

项目处理：F17同时报告日前、实时与总成本；不能将图5-8实时成本直接与项目总费用比较。

### R6-A06

PDF100/印刷83，图5-6；状态：`author_stress_example`。

原文记录：17:00–22:00的2MW下调需求用于演示响应；涉及CHP下压、EB和P2H增用电及室温变化。

项目处理：持续单向调用另作压力测试；不把该人工压力情景混入独立同分布风险分母。

### R6-A07

PDF98–104，本次完整相关页；状态：`missing_in_inspected_pages`。

原文记录：未获得随机种子、Monte Carlo分布/时序相关参数、明确训练验证划分、半径校准和风险置信区间。

项目处理：统计检验、合成分布与数据隔离是项目新增；不把名义机会约束95%当作已证明样本外95%。

### R6-A08

PDF103–104/印刷86–87，表5-7/5-8；状态：`author_reported_scale`。

原文记录：100场景改进法1224.30s，基准9579.83s；扩大系统为PDN123-DHN32，250/500场景基准超过10000s。

项目处理：R6数据统计不替代规模性能验收；当前小系统不继承这些作者报告的速度优势。
