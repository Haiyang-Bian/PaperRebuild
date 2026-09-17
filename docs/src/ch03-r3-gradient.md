# [R3 灵敏度与投影梯度](@id ch03-r3-gradient)

本页采用第3章已核查WMM解释，讨论流量变化如何影响固定流量子问题的最优费用。
算法名为 `r3_pg_checked_v1`。论文式（3-61）至（3-66）保留在[原式台账](@ref ch03-algorithm-equations)，
本页补全方程使用独立编号，不能将其当作原文逐字转录。

## 从物理量到最优值导数

流量改变管内水的停留时间，也改变热功率和多入流混合系数。因此，改变一个时段的流量，
可能影响后续多个时段的输运。历史流量是给定输入，不随优化改变。
若第i个时间段只覆盖部分管存水，令前序累计流量为S，则

```math
a_i=\frac{M/\Delta t-S}{m_i},\qquad
\frac{\partial a_i}{\partial m_j}=-\frac1{m_i}\;(j<i),\qquad
\frac{\partial a_i}{\partial m_i}=-\frac{a_i}{m_i}.
\tag{R3-PG-1}
```

完全覆盖和未覆盖段的导数为零。累计质量恰好等于管内质量时是分段切换点，
不能把某侧的导数写成唯一普通导数。权重、停留时间和指数衰减继续使用链式求导。
例如当前流量0.8 kg/s、管水1800 kg、步长3600 s，部分权重为0.625，
对当前流量导数为−0.78125 (kg/s)⁻¹。

实现：[`r3_transport_jacobian`](@ref)。其Jacobian列按当前、前一时段、…排列；
子问题组装只取非历史列。测试：`R3 analytic transport Jacobian`。

## 为什么不能只读一组等式乘子

将约束统一写为F(x,m)属于锥K，最小化问题的MOI约定为

```math
L(x,y;m)=c(x,m)-\sum_i y_i^\top F_i(x,m),\qquad
\nabla_m V=\partial_m c-\sum_i(\partial_m F_i)^\top y_i.
\tag{R3-PG-2}
```

等式的右侧先移入F；例如固定条件u−m=0贡献为+y。原式（3-61）仅写热耦合乘子，
采用式则核查所有流量相关项，避免漏掉水力等不等式贡献。
依据：[MOI对偶说明](https://jump.dev/MathOptInterface.jl/stable/background/duality/)。

现有实现有两条参数路径：水力/质量关系通过固定变量传递，由其固定等式对偶统一贡献；
热功率、混合和输运已代入数值系数，另加这些系数的偏导。不能再次把水力锥导数重复相加。
诊断的混合与输运松弛系数含流量，非零松弛时也必须求导。

实现：[`r3_value_sensitivity`](@ref)。保存`fixed_rhs/heat/mixing/transport/loss`分项。
测试：`R3 dual signs and complete value sensitivity`。

## 对偶可信度和适用边界

从JuMP原表达式和变量值重算可行性，避免后端桥接移位坐标影响ConstraintPrimal。
检查所有变量界、固定等式、线性约束和二阶锥的原始/对偶可行性、互补性与平稳性。
归一化KKT误差不得超过1e-6，有效对偶间隙不得超过A2的1e-4；只有OPTIMAL且有可行对偶时才可信。
这不替代独立物理A1，也不证明最优解唯一、处处可微或联合流量问题凸。

文献[116]公开预印本为Guo等的critical region projection：其多参数二次规划、
子问题可行和非退化假设不直接适用于当前变流量WMM。
预印本为2016年v1；论文引用2017年期刊版，版本差异保留。
来源：[作者预印本](https://arxiv.org/pdf/1606.04037)。

## 投影为什么还有辅助调度变量

删除热功率、混合和输运耦合后，仍保留设备容量、电网、水力锥、节点质量守恒与边界。
在这个凸外松弛中，给定流量必须**存在**满足剩余关系的调度x；不能固定上一轮x来投影。
代码明确删除3-17、3-27/28/30/31/33/34/35/36，保留的关系另用独立数值核回代。
设D为流量上下界跨度矩阵、z为归一化流量、q为相同尺度下的梯度：

```math
z=(m-m^{\min})/D,\quad q=D\nabla_m V/C,\quad
z^*=\arg\min_{z,x\in D_{MP}}\|z-(z^K-q)\|_2^2.
\tag{R3-PG-3}
```

式中除法逐分量进行，跨度为零的分量直接固定。C为预先冻结的目标尺度；诊断目标已经无量纲，C=1。
项目成本尺度由输入电价、购电上限、设备费用及容量给出，取至少1，不按已优化结果调整。
实现：[`build_r3_projection`](@ref)；二阶锥上图表示距离，因此实际模型仍为连续SOCP。

## 不可行分支和局部半空间

诊断最优值φ(m)大于零说明当前固定流量无法同时满足规定热关系，不意味着所有流量都不可行。
式（3-64）的原文符号问题保留，本项目只试探：

```math
\phi(z^K)+q_K^\top(z-z^K)\le0,\qquad \|z-z^K\|_\infty\le0.1.
\tag{R3-PG-4}
```

它是局部线性预测，没有全局割证明。每轮仅试一次局部投影，失败则丢弃；
后续对候选方向最多回溯12次，以实际求解的诊断下降或进入可行分支为准。下一轮不继承该半空间。
可行分支要求费用下降且子问题仍可行；回溯初始步1、缩减0.5、Armijo系数1e-4。
实现：[`solve_r3_projected_gradient`](@ref)。不调用`repair_r3_flow`。

## 分段边界与停止

累计质量切换仅在涉及决策流量时标记；纯历史质量恰好命中不算决策空间中的切换。
切换点先试探归一化全分量正/负方向，再按数组索引试探坐标正/负方向；每轮至多12个候选。
扰动1e-5，经凸域投影保持守恒；位移不足5e-6不接受为有效单侧探测。
只接受实际改善，随后在新点重算导数。记录活跃集签名变化，并清零小变化累计次数。

连续三次接受更新的相对费用变化≤1e-6且投影梯度映射≤1e-4，才记录光滑数值停止。
`line_search_stalled`、`nonsmooth_stalled`、`untrusted_sensitivity`、轮数或时间上限分别保留；
它们不代表已证明无解或收敛。最好的子问题候选与物理A1候选分开保存。
最终只在固定候选流量下补做必要的原电网等式调度，不能用直接流量修正冒充外层成功。

## 初学者运行路线

从项目根目录依次执行；也可使用VS Code中`PaperRebuild: R3 PG ...`任务。

```sh
julia +1.12.6 --project=. scripts/test_r3_pg.jl
julia +1.12.6 --project=. scripts/experiment_r3_pg.jl single-source-case_fixed --open
julia +1.12.6 --project=tools/solvers scripts/experiment_r3_pg.jl
julia +1.12.6 --project=. scripts/r3_pg_task.jl validate RESULTS_RUN_DIRECTORY
julia +1.12.6 --project=docs scripts/r3_pg_task.jl plot RESULTS_RUN_DIRECTORY
julia +1.12.6 --project=docs scripts/report_r3_pg.jl RESULTS_STUDY_TOML
```

将占位参数换成终端实际打印的路径。重绘只读保存结果；已有图目录不会覆盖。
预算每例600秒，外层共享前540秒，预留60秒物理求解。低预算开发按相同比例预留，建模/回溯计时。
从box初值开始的预投影也计入该例预算。完整原始对偶/试探/源码在本地保留，公开摘要保留哈希、
冻结案例、最终数值、逐轮数据与图源CSV。

F04显示残差相对A1阈值，F05比较流量/温度/热功率及独立回放，F06分开画费用与诊断值，
拒绝试探用红叉标记。费用不能和诊断量相加；诊断阶段的费用不是可执行调度费用。

## 商用求解器对偶的边界

开发对照中Gurobi原始目标接近Clarabel，但水力锥的返回对偶未通过KKT。
单独收紧`BarQCPConvTol=1e-10`后仍不满足，因此不输出Gurobi梯度，外层使用Clarabel可信对偶。
这不是已经确认的Gurobi引擎错误；桥接/对偶提取或数值退化的来源尚未完全隔离。
Gurobi仍用于SCHPD初始化、原始目标对照和非凸最终物理调度。
依据：[QCP专用容差说明](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#parameterbarqcpconvtol)。

正式对照的原始目标相对差如下。目标相近并不保证乘子可靠；归一化互补残差门槛为1e-6，四组均未通过。

| 案例／目标 | 原始目标相对差 | Gurobi互补残差 | 对偶用于梯度 |
| --- | --- | --- | --- |
| 单源／费用 | 5.03e-11 | 0.007997 | 否 |
| 单源／诊断 | 3.21e-11 | 0.030419 | 否 |
| 双源／费用 | 1.09e-9 | 0.010053 | 否 |
| 双源／诊断 | 2.40e-10 | 0.018064 | 否 |

紧凑数值及原始记录SHA见`results/summaries/r3-pg/r3-pg-20260917T071031-7eafbab9-fb56a669/solver-reference.toml`。
从原件提取使用`scripts/report_r3_pg_reference.jl SOURCE_TOML OUTPUT_TOML`，不重新求解。

## 本批证据与后续入口

[16例正式结果与F04–F06](ch03-r3-pg-results.md)分别报告物理可行、费用和外层停止。
原始数值均来自保存运行；当前14例通过物理A1，只有免费购电边界例满足数值停止条件。
容量反例、时延切换残差及未可信的商用对偶保留在`docs/reading/ch03/r3-pg-issues.toml`。
后续先处理这些边界与乘子质量问题，再扩大到论文规模；本批不继承文献[116]的全局收敛结论。
