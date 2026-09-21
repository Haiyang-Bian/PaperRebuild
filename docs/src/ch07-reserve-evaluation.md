# 训练合格之后：新一天的备用与舒适评价

本页接续[同模型紧凑表示](ch07-compact-risk.md)。有限支持训练合格，还不能证明方案遇到新的光伏和备用调用时可靠。
本节点沿用已冻结的测试操作，不重选半径、初值或天气。全部数据仍为合成替代，不能推广到作者实际输入。

## 1. 首先锁定什么？

3A在预算内没有候选，保留`training_candidate_unavailable`。3B/C各100情景候选分别通过原模型、风险及费用回代，
训练费用最优性均未完成。两者的日前购电、上下备用、温区、价格、训练代表及全部舒适分支相同。
保留两个父身份，完整操作数据及哈希相同才共用计算。

```math
x^\star=(P_t^{\mathrm{DA}},R_t^{\mathrm{up}},R_t^{\mathrm{down}})_{t=1}^{T},
\qquad z_j^\star\in\{0,1\}.
\tag{R9-OS1}
```

MW原值和`z⋆`来自保存的训练解。不能将很小的备用裁成零、给3A注入共同见证，或用测试结果重选解。
固定原教学价格及CNY币种，没有重新策略出清。这里是项目操作解释，不冒用论文新式号。

## 2. 新一天怎样运行？

每个新日包含24小时的PV比例`a`和有符号调用`u`。沿用原RMS距离，等距取冻结顺序最早代表：
其它不确定字段或同一时段同时上下调用不属于该表示，提取时明确拒绝，不能静默丢掉输入。

```math
j(\xi)=\mathop{\arg\min}_{j}^{\mathrm{first}}
\sqrt{\frac{1}{2T}\sum_{t=1}^{T}
\left[(a_t-a_{jt})^2+\left(\frac{u_t-u_{jt}}{2}\right)^2\right]},
\qquad z(\xi)=z_{j(\xi)}^\star.
\tag{R9-OS2}
```

`z=0`保持原舒适温区；`z=1`使用训练风险模型已声明的较宽物理温区。标签不是实际违约事件，
也不会把有限支持风险保证自动延伸至新日。固定该分支后最小化全天补救费用：

```math
y^\star(\xi)\in\arg\min_y C(x^\star,y;\xi),\qquad
y\in\mathcal F(x^\star,\xi,z(\xi)).
\tag{R9-OS3}
```

`F`沿用固定流量、显式历史的补救物理模型。只替换光伏和调用，不改成交、负荷、设备、价格或边界。
操作知道全天未来轨迹，因此不是在线控制；不执行舒适优先修复或重新分配标签。

## 3. 怎样判断可靠性？

由原变量和原始乘子独立重建物理关系、LP原始/对偶可行性、互补和费用。规定操作完成后，
才按A1的`1e-4 K`判断任一建筑/时段的实际舒适违约。不可行、超时无完整解、对偶缺失或KKT失败均记未知。

```math
N=N_{\mathrm{pass}}+N_{\mathrm{violation}}+N_{\mathrm{unknown}},\qquad
\underline p=\mathrm{CP}_{L}(N_{\mathrm{violation}},N),\quad
\overline p=\mathrm{CP}_{U}(N_{\mathrm{violation}}+N_{\mathrm{unknown}},N).
\tag{R9-OS4}
```

`CP`复用已验证的单侧95%二项界。上界≤5%才支持、下界>5%才拒绝，否则未决。
未知留在分母并全部计入保守上界；完整日是样本，不把小时当独立样本。费用缺失只报已完成日的条件分布。
两个相同操作不是两项独立效果证据。当前备用约1e-13 MW，即使舒适通过，也不能宣称已验证有效备用服务收益。

例如，独立采样的三天没有观测到违约，单侧95%上界仍约63.2%；这说明为什么不能用前三日代替完整验收。
这个计算要求没有未知日；正式批次仍按预声明1000日评价，不按途中显著性提前停止。

```jldoctest
julia> using PaperRebuild

julia> round(r6_binomial_bounds(0, 3).upper; digits=3)
0.632
```

## 4. Julia入口与证据

```@index
Pages = ["ch07-reserve-evaluation.md"]
```

```@docs
R9ReservePolicy
r9_reserve_policy_from_training
r9_reserve_support_label
r9_reserve_evaluation_day
evaluate_r9_reserve_day
validate_r9_reserve_day
save_r9_reserve_day
read_r9_reserve_day
summarize_r9_reserve_days
```

`configs/r9/reserve-evaluation.toml`先锁定三训练槽、1000原测试日、公共源码及环境。
逐日求解与第一次核验共享60秒，装载/存档另报实际耗时；预算超出也保留。默认每次追加50日，
前三日作为同一正式样本的吞吐前缀，不能换样本。断点先核对原字节，完整失败日不重试，最后整体数值重验。
原变量/对偶完整保存；数万条可重建残差保存分组计数及极值，重读再重建全部行核对。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_evaluation.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_evaluation.jl
julia +1.12.6 --startup-file=no --project=. scripts/r9_reserve_evaluation.jl freeze results/summaries/r9-common-input-20260921-v2 results/summaries/r9-compact-input-20260921-v1 results/summaries/r9-compact-evidence-20260921-v1 results/summaries/new-r9-heldout-input
julia +1.12.6 --startup-file=no --project=. scripts/r9_reserve_evaluation.jl run results/summaries/new-r9-heldout-input results/runs/new-r9-heldout 3
julia +1.12.6 --startup-file=no --project=. scripts/r9_reserve_evaluation.jl run results/summaries/new-r9-heldout-input results/runs/new-r9-heldout 50
julia +1.12.6 --startup-file=no --project=. scripts/r9_reserve_evaluation.jl check results/summaries/new-r9-heldout-input results/runs/new-r9-heldout
```

解析测试覆盖两种开放求解器、CNY、时间步、不可行/未知、缺失对偶和篡改拒绝。
正式输入`results/summaries/r9-heldout-input-20260922-v2`已核验并冻结全部训练槽和1000原测试日。
首3日均通过model/KKT/cost/实际室温检查，保存后完整重验一致；其余997日正在按原顺序执行。
三日调用总能量分别仅约1e-12 MWh，不能将舒适合格解释成有效备用容量收益。
这还不是1000日风险结论。只读统计命令为：

```sh
julia +1.12.6 --startup-file=no --project=. scripts/report_r9_evaluation.jl results/summaries/r9-heldout-input-20260922-v2 results/runs/r9-heldout-20260922-v1 results/summaries/new-heldout-report
```

报告会核验完整原值；部分运行时未执行日仍写unknown，`formal_test_complete=false`。
实际进度由当前状态和
`docs/agent/tasks/2026-09-22-r9-reserve-evaluation.md`记录；R9其它规模范围及全文覆盖仍未完成。
