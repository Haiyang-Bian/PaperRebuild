# [R3可比基线与差异归因](@id ch03-r3-baseline)

本批回答“哪些差异能解释作者与项目结果不同”，不预设作者或项目实现有错。
论文依据为PDF53–55、57、60（印刷36–38、40、43），逐项清单保存在
`docs/reading/ch03/r3-baseline-differences.toml`。正式结果另页发布。

## 1. 比较的对象

`r3_paper_structure_v1`复用已经核查的WMM、SCHPD解释、原始模型与验证器。
其结构遵循3-60/61/63/65/66：固定流量求子问题，利用对偶与输运导数计算灵敏度，
再投影更新流量。它不是作者源码的等价实现，也不代表literal版本的阻断已经消失。

外层不调用v2局部方向、v3物理恢复、全变量直接修正或参考解初始化。
原等式调度仅在末尾单独核验；结果不会反馈外层，失败也不抹掉已有A1候选。
缺可信对偶及无法可靠求导的输运切换均形成负结果，不通过放宽门槛续做。

## 2. 流量坐标为什么会影响更新？

记流量边界跨度为对角矩阵D，物理坐标梯度为g。固定分量不参与运算。
论文式3-63/66采用kg/s坐标欧氏距离，现有实现则使用归一化流量距离。
两种目标度量不同，不能因两者都称“投影梯度”就假定数值轨迹相同：

```math
\begin{aligned}
d_{\mathrm{physical}}&=-g,&
 m^+&=\arg\min_{m,x\in\mathcal D}\|m-(m^k+\gamma d)\|_2^2,\\
d_{\mathrm{normalized}}&=-D^2g,&
 m^+&=\arg\min_{m,x\in\mathcal D}\|D^{-1}(m-(m^k+\gamma d))\|_2^2.
\end{aligned}
\tag{R3-B1}
```

两种几何均同时优化投影辅助调度变量。保留设备、电网、水力锥、质量守恒和模式约束；
删除由固定流量子问题处理的非凸热耦合。实现：[`build_r3_projection`](@ref)。

为了公平控制初始步幅，两种几何都按未投影最大归一化位移δ确定标量步长：

```math
\gamma_0=\frac{\delta}{\|D^{-1}d\|_\infty},\qquad
J(m^+)\le J(m^k)+10^{-4}g^\mathsf T(m^+-m^k).
\tag{R3-B2}
```

δ默认0.1；专项另取0.01和1。回溯最多12次，每次γ减半并重新投影。
J为冻结尺度归一化费用或弹性诊断值；诊断转为可行调度也可接受。
上述步幅、回溯及Armijo常数是项目补充，不冒称作者设置。
单位一致变换时，梯度随坐标逆变换；解析测试同时检查步幅映回原单位的一致性。

手算：目标流量(1.4,1.6)，约束第二管比第一管至少多0.5 kg/s。
物理欧氏投影为(1.25,1.75)；跨度分别为1和2时，归一化欧氏投影为(1.34,1.84)。
测试`R3 baseline geometry, evidence and compatibility`在真实凸投影域中验证这两个解。

## 3. 边界对照

| 版本 | 改变 | 可作出的判断 |
|---|---|---|
| legacy_tail | 不改变既有尾段 | 原反例与历史边界 |
| bounded_return_tail | 仅解除尾段负荷回温参考等式 | 判断该等式是否参与冲突；末状态仍须检查 |
| core_only | 截取4个核心时段 | 判断添加尾段的影响；不能比较公平周期收益 |

核心负荷、价格、设备和历史由同一输入派生并计算共同核心哈希；有尾段两组输入文件相同，
差异只在运行约定。新规则由[`R3OperationSpec`](@ref)显式传入。
旧缺省规则和序列化哈希保留；[`r3_boundary_case`](@ref)不修改原案例。

固定控制恢复，不意味着管内历史立即恢复。末端有效记忆窗口的流量、入口温度和独立出口回放
仍按原A1检查。core_only的终端状态标为“不要求”，不伪装成恢复通过。

## 4. 停止与最终检查

论文步骤2.b比较相邻费用绝对差，ε数值尚未确认。项目并列审计三个预先声明阈值：

```math
|c^{k}-c^{k-1}|\le\epsilon,\qquad
\epsilon\in\{10^{-6},10^{-4},10^{-2}\}.
\tag{R3-B3}
```

命中时只保存候选，不提前截断真实轨迹。原有三次小变化加可信归一化梯度映射条件仍用于
项目停止；原始投影度量与用于旧判据的归一化映射分别记录。活跃集变化重置小变化计数。
诊断目标不混入费用序列，重求核验和拒绝步不增加接受次数。

末尾对首次模型可行、三个ε首命中和最低模型费用候选按流量哈希去重，均分最多60秒。
原物理A1、原等式重求是否成功和费用优化是否结束分别保存；求解器报告不可行不能单独
证明全部流量或模式无解。没有值用缺失状态，不填零。

## 5. 运行与保存

```julia
using PaperRebuild, Clarabel
c = load_r2_case("configs/r2/single-source.toml")
m = reduce(vcat, permutedims.([p["fixed_flow"] for p in c.data["heat"]["pipes"]]))
r = solve_r3_baseline(c; initial_flow=m, convex_optimizer=Clarabel.Optimizer,
    spec=R3BaselineSpec(geometry=:physical_euclidean), max_iterations=2, budget_sec=60)
```

该开放示例不提供非凸优化器，末尾原等式检查明确记录未执行，不自动申请许可。
正式批次使用Clarabel对偶和Gurobi独立详细求解。运行保存沿用[`save_r3_run`](@ref)、
[`read_r3_run`](@ref)；配对入口[`compare_r3_baselines`](@ref)拒绝未声明的额外因素变化。

正式设计为20项初值/几何、12项尾段/几何、4项步幅及6项独立参考，共42次。
每次600秒；历史初值生成耗时与当前外层分开，不作作者加速比复现。
所有图从保存结果重绘；最终结论区分支持、排除和未决，不要求每例变为成功状态。

## 6. Julia与VS Code操作入口

在仓库根目录执行。冻结命令拒绝覆盖内容不同的文件；正式实验会新建运行目录。
干净克隆可直接使用已提交的baseline-study.toml及baseline-inputs运行实验，无须重新冻结。
冻结来源审计和历史v3审计需要本地保存的旧运行目录；这些原始运行不随公开仓库分发。

```sh
julia +1.12.6 --project=. scripts/check_r3_baseline.jl
julia +1.12.6 --project=. scripts/test_r3_baseline.jl
julia +1.12.6 --project=. scripts/freeze_r3_baseline.jl
julia +1.12.6 --project=. scripts/experiment_r3_baseline.jl
julia +1.12.6 --project=. scripts/compare_r3_baseline.jl <运行批次/study.toml>
julia +1.12.6 --project=. scripts/report_r3_baseline.jl <运行批次/study.toml>
julia +1.12.6 --project=docs scripts/plot_r3_baseline.jl <报告目录>
```

VS Code“运行任务”中的`PaperRebuild: R3 baseline ...`提供对应入口。
表格摘要可用`scripts/summarize_r3_baseline.jl <报告目录>`重算；
`audit_r3_baseline_history.jl`只审计已有24项v3主运行，不重新执行历史优化。
查看[本批正式结果](ch03-r3-baseline-results.md)，从结论链接到具体图源、阶段和哈希。
