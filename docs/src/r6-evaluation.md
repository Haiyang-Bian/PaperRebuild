# R6：训练之外的新一天怎样运行？

目前已经实现两个清楚区分的接口：正式策略外推 `r6_support_nearest_v1` 和独立舒适诊断
`r6_comfort_priority_v1`。本节点先验证操作定义与解析例；**尚未执行正式100代表训练、
500日验证选参或1000日测试**。上一批六方法结果仍是[开发实验](r6-pilot-results.md)。

## 为什么不能直接拿训练目标比较？

训练会选出日前购电、上调备用和下调备用，还会为每个训练代表安排实时设备出力。
但新一天的光伏和备用调用通常不与代表完全相同。原先的设备出力不能直接照抄，
而机会约束中的舒适开关也只定义在训练代表上。

原论文PDF101（印刷84页）报告1000个蒙特卡洛场景的样本外比较，但此页没有给出完整的新日执行映射。
本项目先声明操作再测试，避免在看到新日结果以后挑选更有利的调度方式。
下面的外推及诊断都属于项目补充，不能冒称作者源码的等价实现。

## 正式策略外推

1. 读取核验通过的训练结果，冻结日前成交、所选市场价格和每个代表的舒适开关。
2. 用共同的整日轨迹距离找到最近训练代表；等距时取冻结顺序最早项。
3. 开关为0时保持原舒适温度界；开关为1时使用训练中同样的较宽物理温度界。
4. 在真实新日的光伏和调用下最小化实时费用，保持设备、容量、交付预算、历史和终端规则。
5. 独立重算物理、原始乘子、费用与实际室温事件。失败或未完成保留为未知。

对应[项目式R6-E4](r6-evaluation-equations.md#R6-E4)与
[`evaluate_r6_policy_day`](@ref)。新日不会重新报价、重新选择价格或更换舒适分支。
这里仍知道完整未来轨迹，不能称为逐时在线控制。若同一费用最优面有多种调度，
保存预声明求解器实际选出的原值；不宣称最优调度或其风险事件必然唯一。

一个训练开关为1的日子，也可能恰好没有温度越界。因此始终分别保存 `trained_label`
和 `comfort_outcome`，后者才进入日事件统计。有限支持上的风险上限不会自动变成新日风险上限。

## 独立诊断：有没有能力保持舒适？

[`evaluate_r6_day`](@ref)回答另一个问题：给定同样的日前成交，是否存在保持舒适的调度？
它先解硬舒适费用问题；仅明确不可行时，最小化整日最大温度越界，再在该最小值加
`1e-8 K` 的数值面内优化费用。硬件、物理温度、交付和终端约束始终保持。

这个优先级可能改变机会约束策略的经济选择，故诊断只能单列。
正式策略失败而诊断成功时，仍保存正式策略失败；不能以诊断费用代替正式样本外费用。
若硬舒适被报告不可行而宽域诊断得到几乎零越界，记录状态冲突，不自动判为成功。

## 一个可以手算的温度例子

教学夹具固定供热为0.042 MW，热损失系数为0.0042 MW/K，热容量为0.01 MWh/K，
初始室温293.15 K、室外温度281.15 K，步长1 h。由既有后向离散建筑关系：

```math
\tau_t=\frac{0.01\tau_{t-1}+0.042+0.0042\times281.15}{0.0142},
\qquad 293.15-\tau_t=2\left[1-\left(\frac{1}{1.42}\right)^t\right].
\tag{R6-X1}
```

第一小时越界约0.591549 K；24小时后趋近2 K。硬舒适分支不可行，宽温度分支可以运行，
但它的实际舒适事件是违约。两种状态的差别来自明确的温度规则，不能统称“求解成功”。
这是解析测试夹具，终端为free，**不修改正式日模板的initial终端**，也不进入正式统计。

## Julia调用与保存

以下代码假设 `physical`、`training_case`、`training_result` 来自同一已核验训练，
`trajectory` 为2×24矩阵：第一行PV可用比例，第二行有符号备用调用。

```julia
using PaperRebuild, JuMP, HiGHS
optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance" => 1e-9,
    "dual_feasibility_tolerance" => 1e-9,
)
policy = r6_policy_from_training(physical, training_case, training_result)
result = evaluate_r6_policy_day(policy, trajectory;
    id="example_new_day", optimizer, budget_sec=60)
save_r6_policy_day(policy, trajectory, result, "results/runs/example-new-day")
saved = read_r6_policy_day("results/runs/example-new-day")
saved.validation["comfort_outcome"]
```

保存目录必须不存在。记录含成交来源、日轨迹、阶段原值、原始乘子、费用、源码与环境哈希。
`current_source_matches` 表示当前验算依赖与运行当时是否相同；目录内 `code/replay.jl`
可加载冻结源码只读重验，不再次求解。完整日的未知结果保留在风险分母，配对费用缺失时不生成总体排名。

## 三种费用和两个分母

- 日前净支付：固定成交量乘所选市场价格，只计一次。
- 实时净费用：设备成本、实时结算及交付罚项。
- 总净费用：上述两项之和，可以为负；它不是系统资源消耗。

原论文式（5-4）的交付误差限额按成交备用容量累计量计算。本节点保持这个定义，
另外报告“未满足调用量/实际调用量”；零调用时该比例为未定义，不填成0。
室温违约按完整日统计，不将24个小时当作24个独立样本。

## 当前检查与后续

本节点新增125项解析、双求解器、失败传播及冻结重读检查通过，完整R1–R6回归通过。
这些是接口与数学例子的验收，尚不是500验证日或1000测试日的结果。

```powershell
julia +1.12.6 --startup-file=no --project=. scripts/test_r6_evaluation.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r6.jl
julia +1.12.6 --startup-file=no --project=. scripts/r6_pilot_replay.jl check results/summaries/r6-pilot-replay-v2
```

VS Code提供对应评估测试、公式映射和旧证据重放任务。新日记录只读入口为
`scripts/check_r6_evaluation.jl <directory>`；诊断记录使用额外参数 `--diagnostic`。

正式运行前还须冻结半径候选、验证选择准则、同分规则、失败处理和预算；之后才训练全部100代表，
在500验证日选择参数并锁定，最后使用1000独立测试日比较。实际风险按A5单侧95%界报告。
舒适诊断另列，第5章线性电网、固定流量热网、乐观市场和完整未来信息的边界继续保留。
