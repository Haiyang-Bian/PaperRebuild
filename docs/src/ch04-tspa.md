# R4第四批：两阶段分配与网络分歧点

上一批[单阶段分配](ch04-bargaining-results.md)回答了已有节约怎样分配。
原文两阶段TSPA进一步问：聚合商先自行交易以后，加入运营商还有多少增益？
本批采用r4_tspa_checked_v1，按PDF73–74、印刷56–57页恢复结构。
原式及符号见[台账](ch04-tspa-equations.md)；合成输入沿用已冻结四套基线。

## 1. 先联合聚合商，再检验网络

AGNB第一步优化两个聚合商的设备、储能及负荷和显式合同，没有网络变量。
买卖零售价与原AG0相同，聚合商之间的支付相互抵消，卖方服务费只收一次。
令q为A向B的出售量，正的节点注入表示向网络送能：

~~~math
P_{A,t}^{\mathrm{net}}=P_{A,t}^{\mathrm{sell}}-P_{A,t}^{\mathrm{buy}}+q_{P,t},
\quad
P_{B,t}^{\mathrm{net}}=P_{B,t}^{\mathrm{sell}}-P_{B,t}^{\mathrm{buy}}-q_{P,t}.
\tag{R4-T1}
~~~

热合同相同。MW乘小时得到MWh后计费；合同量不是某条支路的物理潮流。
聚合商总费用包括设备、不满意度、与运营商的零售及服务费。
最小化该费用后，用原AG0局部效用作为分歧点，在聚合商之间进行第一阶段Nash分配。
只有允许无限额转移且剩余非负时，这个分解才产生满足个体理性的分配。

原AG0两个局部计划可直接嵌入零P2P合同，作为已知可行候选。
如果数值求解返回的候选独立重算费用更高，选择这个已知候选，
同时保存原求解状态、数值和目标，不把回退结果伪装成求解器最优解。
API：[交易构建](@ref PaperRebuild.build_r4_model)、[交易验算](@ref PaperRebuild.validate_r4_trading)。

## 2. 反事实分歧点需要显式解释

把AGNB的全部设备与负荷控制冻结后，先独立求严格网络调度。
另建DHSO0-r项目解释：只软化节点有功、无功、热能、质量平衡。
设备容量、负荷边界、冻结控制、端口包络、电压降和所选支路关系保持硬约束。
这不是作者未公开实现的逐项等价复写，也不保证任何硬约束冲突都能恢复。

~~~math
B_{k,i,t}(x)=s^+_{k,i,t}-s^-_{k,i,t},\qquad s^\pm\ge0,\quad
\Pi=\delta\,\Delta t_h\sum_{k,i,t}\frac{s^+_{k,i,t}+s^-_{k,i,t}}{\sigma_k}.
\tag{R4-T2}
~~~

B是相应平衡方程的“左侧减右侧”，k分别为P、Q、H、m。
P/Q尺度取至少1MW/Mvar的接网容量；H取至少1MW的全部额定供热能力；
m取至少1kg/s的最大管流容量。罚系数单位为合成美元/h/归一化违反。
尺度由输入冻结，A1验收阈值保持不变。

求解目标为实际资源成本加人工罚项Π。冻结的聚合商费用是常数，
因而该目标与只最小化运营商费用加Π在控制选择上等价。
罚项可以引导减少违反，但有限罚系数不会自动保证原约束成立；
这是[JuMP不可行诊断](https://jump.dev/JuMP.jl/stable/tutorials/getting_started/debugging/#Penalty-relaxation)
中罚松弛与实际可行性需要分开的同一原则。

API：[冻结尺度](@ref PaperRebuild.r4_tspa_scales)、[独立弹性验算](@ref PaperRebuild.validate_r4_elastic)。

## 3. 人工罚项如何影响第二阶段剩余？

第一阶段运营商收入为聚合商零售付款和卖方网络费之和。
原式（4-98）没有明确费用C_DHSO是否包含Π，因此本批并列两种解释：

~~~math
d_0^{\mathrm{excl}}=R_0-C_0,\qquad
d_0^{\mathrm{incl}}=R_0-C_0-\Pi,\qquad
S_2^{\mathrm{incl}}=S_2^{\mathrm{excl}}+\Pi .
\tag{R4-T3}
~~~

两种解释使用完全相同的物理数值。只改变罚项口径就能改变剩余，不能把这部分称为节能收益。
即使合作计划本身满足A1，若分歧点带非零松弛，“资源费用差”也不是两个可执行计划的节约。
第二阶段使用合作计划支付前效用与新分歧点计算**总转移**，替代全部原内部结算。
不能在新总转移之上再加一次第一阶段支付。

手算：聚合商第一阶段新增收益10；运营商反事实收入减资源费用为20。
若合作总效用只有25，而第一阶段三方效用合计30，则第二阶段S=-5，不能让三方都更好。
若把罚项8扣入运营商分歧效用，S变为3。变号来自反事实定义，不表示设备多产生了8单位价值。
代码保留负剩余，不放宽验收或裁零制造分配成功。

## 4. 怎样解读原文稳定性论证？

原式（4-100）把聚合商两次增益相加；（4-102）使用第二阶段剩余非负的前提。
如果第一阶段严格网络计划可行，且合作模型含有该计划并充分求解，
可用可行域包含关系解释总福利不会降低。
但忽略网络并加松弛的分歧计划未必属于合作物理可行域，不能自动使用这一论证。
本批逐项报告前提、分配与原约束通过状态；不认证任意子联盟稳定或博弈核。

四套输入乘两种罚系数为8次流程；同案例两系数显式共享AGNB控制。
罚项进/不进分歧效用是在已保存同一结果上计算的16项核算，不是16次独立物理实验。
集中参考与AG0来自旧批次，输入哈希必须相同，历史结果不改写。

## 5. 运行与验收

~~~julia
spec = R4TSPASpec(penalty=10000.0)
# 使用同输入已保存的independent和central；完整命令由下面脚本提供。
~~~

| 操作 | 仓库根目录命令 |
|---|---|
| 两阶段测试 | julia +1.12.6 --project=. scripts/test_r4_tspa.jl |
| 公式与映射 | julia +1.12.6 --project=. scripts/check_r4_tspa.jl |
| 冻结实验 | julia +1.12.6 --project=. scripts/study_r4_tspa.jl 新批次ID |
| 已存结果报告 | julia +1.12.6 --project=. scripts/report_r4_tspa.jl 路径/study.toml 新报告目录 |
| 只读重绘 | julia +1.12.6 --project=docs scripts/plot_r4_tspa.jl 新报告目录 |

[求解接口](@ref PaperRebuild.solve_r4_tspa)、[整体验收](@ref PaperRebuild.validate_r4_tspa)、
[保存](@ref PaperRebuild.save_r4_tspa_run)、[重读](@ref PaperRebuild.read_r4_tspa_run)均保留失败。
本批仍不含ATC/ADMM、网络重构、热网动态或论文规模。
