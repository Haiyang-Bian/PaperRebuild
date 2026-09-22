# 日前承诺怎样同时满足多个调用情景？

## 1. 从固定成交到共同决策

此前把市场成交交给IES，发现“账面中标但设备无法交付”的容量反例。
现在把日前购电和上下备用容量放入优化，让所有声明情景共同限制这些量。
同一个日前决定只能作一次；情景发生后，燃机、电锅炉、供热及建筑温度调度才分别调整。

本批`r5_shared_commitment_checked_v1`采用原（5-5）—（5-8）的期望费用结构，
物理关系沿用[确定性补救采用版](ch05-dispatch.md)。价格固定、概率给定、舒适逐情景硬约束。
完整的策略报价、分布鲁棒和联合机会约束仍在后续范围内。
两阶段共有变量与情景变量的建模结构也可对照[JuMP官方教程](https://jump.dev/JuMP.jl/stable/tutorials/applications/two_stage_stochastic/)。

## 2. 目标与信息结构

~~~math
\min_{x,\{w_s\}} C^{DA}(x)+\sum_s p_s Q_s(x),\qquad
Q_s(x)=\min_{w_s}\{c_s^\mathsf Tw_s:A_sw_s\bowtie b_s+B_sx\}.
\tag{R5-SC1}
~~~

日前支付计一次，设备费、实时结算和交付罚款按情景加权。
这里优化的是市场支付后的净费用，不是全系统社会资源成本。
外生价格下选择的容量也不自动成为市场实际中标量。

实时调度知道该情景的**完整时间轨迹**，因此是两阶段基准。它没有保证逐时在线决策只能看到过去。
情景共享初始设备状态、管温历史、网络、容量和边界；仅显式列入`uncertain_fields`的未来轨迹可不同。
概率严格为正、总和为1，不自动删除零概率情景或重标定不合法的概率。

## 3. 一个可以完全手算的例子

冻结合成单时段输入：电负荷0.1MW，电锅炉维持室温需要0.042MW，燃机容量0.2MW且边际费用130。
日前电价100，实时电价80，上下备用容量价均为100；容量上限均0.08MW，时间步1h。
容量价格是用于检验共同承诺机制的教学参数，并非作者数据。
无调用、全额上调用、全额下调用的概率分别为0.5、0.25、0.25；不允许交付误差。

各情景需要的实际购电依次为P、P−U、P+D。无向外售电、非负燃机出力与总电需求0.142MW给出：

~~~math
0\le U\le P,\quad P+D\le0.142,\quad 0\le U,D\le0.08.
\tag{R5-SC-hand1}
~~~

消去燃机后，总费用为

~~~math
J=18.46-30P-87.5U-112.5D.
\tag{R5-SC-hand2}
~~~

先取P=0.142−D，再得到J=14.2−87.5U−82.5D、U+D≤0.142。
因此U=0.08、D=0.062、P=0.08，J=2.085合成美元。三个情景燃机分别为0.062、0.142、0MW。
改用0.25h稳态单步，功率结论保持，费用变为0.52125，历史长度须对应物理输运时间重新提供。

无备用时费用14.2。若只考虑无调用情景，则可选择U=D=0.08并得到−1.8净费用，
但该决定不能交付所有上/下调用。负净支出包含容量收入，不是负发电成本。
这种对照检验的是情景覆盖与共同决策，不是样本外可靠率。

## 4. 怎样证明共同模型没有拼错？

[`build_r5_commitment`](@ref)复用已逐系数对照原JuMP模型的补救系数表。
每个情景的结果仍交给旧的独立物理回放器检查；测试还在同一共同承诺下，
用原`build_r5_dispatch`接口分别重求条件子问题，核对费用与可行性。

联合LP里的情景乘子带有概率尺度：

~~~math
y_s=\lambda_s/p_s,\qquad
\nabla C^{DA}+\sum_s p_s g_s-F^\mathsf T\nu=0.
\tag{R5-SC-KKT}
~~~

[`validate_r5_commitment`](@ref)同时保留原始联合乘子和按概率换算的条件乘子，
核验条件LP、共同变量驻点、一阶段界互补以及整体原对偶费用差。
只证明每个条件问题最优还不够：共同承诺仍可能选得很差。
原A1、A2及1e-6 KKT门槛保留；缺失可信乘子时不伪造完整最优性认证。

原式（5-4）的容量分母未更换。更大备用既改变请求，也改变误差预算，
导数必须保留两条路径，见[补救灵敏度](ch05-recourse-duality.md)。
公开的符号与采用解释见[项目台账](ch05-commitment-equations.md)。

## 5. 冻结范围与运行入口

`configs/r5/commitment/study.toml`在本批首次优化前冻结10套输入、22项规则：
手算、0.25h、无备用、固定可行承诺、固定过量承诺、容量分母、仅无调用、不同概率、
四时段及四时段未来轨迹变化；HiGHS/Clarabel各10项，Gurobi另做2项对照。
固定过量承诺在下调用时要求购电0.16MW，超过不可外送的0.142MW需求，是预先保留的不可行例。

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/test_r5_commitment.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r5_commitment.jl
julia +1.12.6 --startup-file=no --project=. scripts/study_r5_commitment.jl r5-commitment-new
julia +1.12.6 --startup-file=no --project=. scripts/report_r5_commitment.jl results/runs/r5/r5-commitment-new/study.toml results/summaries/r5-commitment-replay
julia +1.12.6 --startup-file=no --project=docs scripts/plot_r5_commitment.jl results/summaries/r5-commitment-replay
julia +1.12.6 --startup-file=no --project=. scripts/check_r5_commitment_artifacts.jl results/summaries/r5-commitment-replay --seal
~~~

[`load_r5_commitment_case`](@ref)读取嵌入所有情景的输入，
[`solve_r5_commitment`](@ref)使用一次共享预算求解，
[`save_r5_commitment_run`](@ref)/[`read_r5_commitment_run`](@ref)分别存档和独立重读。
构建、求解、验证分开，读档不重新优化，失败运行也保留。

137项专项和完整2396项回归通过。概率分裂、情景排序不改变解的费用；
分别提前为每个情景选择承诺得到−1.35的完美信息下界，不能把它作为共同承诺可实施费用。
科学节点44431fd后的22项正式对照现已完成：20候选通过、2条预设不可行记录保留；
原值、图表及解释见[正式结果](ch05-commitment-results.md)。开发数学测试与正式批次数量分开记录。
