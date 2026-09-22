# 第4章离散选择与精度核查

本批在固定拓扑、静态热能流模型上，覆盖唯一电池的全部逐时充放状态。
它复用[固定模式分布法](ch04-distributed.md)，不把穷举包装成论文的整数分布收敛算法。
本页项目式与API/测试的机器映射见docs/reading/ch04/discrete.toml。

## 1. 从固定模式到离散调度

一组四时段电池有16组模式。状态1允许充电，0允许放电，任一状态都允许闲置。
若电池不动作，多组模式可以产生相同解；这些重复结果不能删去后声称搜索更快。

```math
\mathcal F=\bigcup_{z\in\{0,1\}^T}\mathcal F_z,\qquad
J^*=\min_{z\in\{0,1\}^T}J_z^* .
\tag{R4-E2}
```

模式固定后，每个采用问题为连续凸SOCP。全部模式的并集恢复采用混合整数模型的可行域；
电网原等式和动态热网的性质不能由此推出。枚举只适用于小系统，随时域指数增长。

[r4_battery_patterns](@ref PaperRebuild.r4_battery_patterns)按整数0至15确定顺序，
第一时段为最低位。每项独立使用零通信初值，不读取集中参考或其他模式的解。
[solve_r4_discrete](@ref PaperRebuild.solve_r4_discrete)在600秒共享预算内依次执行，
预算耗尽的模式明确为未运行；不是每种模式再获得600秒。

## 2. 辅助成本与物理控制

显式偏好模型中，不满意度辅助量满足下界，且只以正系数进入费用：

```math
w_{i,t}\ge a_i(D_{i,t}^{ref}-D_{i,t})^2
\quad\Longrightarrow\quad
w_{i,t}\leftarrow a_i(D_{i,t}^{ref}-D_{i,t})^2 .
\tag{R4-E1}
```

给定负荷后，此重构不改变设备、能量、合同或网络量。[reconstruct_r4_cost](@ref PaperRebuild.reconstruct_r4_cost)
另存原始目标/判定与重构目标/判定，逐值核对所有其他变量和实际费用。
旧输入的上图归一化表示也按原模型转换。它不能修复电网等式、边界消息不一致或未收敛的合同。
重构目标标记为解析计算，不能当成求解器新返回的最优值或改写原状态。

## 3. 有效界和选择规则

若每个模式均取得有效集中下界或不可行证据，则可对有限并集组合：

```math
L=\min_z L_z\le J^*\le U=\min_{z:\,\hat x_z\in\mathcal F_z}J(\hat x_z).
\tag{R4-E3}
```

程序仍按A1有限容差判断候选。A2为1e-4，分布相对集中费用A4为1e-3，均不改变。
缺任一模式下界时，不能用剩余模式的最小界代替整个问题界。
分布增广块的目标与系统目标不同，不能放入上式。

分别选择采用模型合格的最低费用、原电网等式也合格的最低费用，平局取最早模式。
两者可能是不同模式；不能用更低松弛费用覆盖已有物理合格候选。
原电网等式参考单独运行，不反馈到模式选择或分布迭代。

## 4. 冻结实验

configs/r4/discrete-study.toml冻结四套旧输入、顺序和预算。每套分别执行：

1. Clarabel分布法全部16模式；显式辅助成本重构。
2. Clarabel集中全部16模式；合并模式下界。
3. Gurobi集中MISOCP，不给定电池模式。
4. Gurobi含原电网等式的整数参考；报告其实际有效界和间隙。

四种方法各共享600秒。全部输入、负荷偏好、边界和成本相同，不根据结果改数据。
另对开放/仅购能两套灵活输入的既有p1，比较Gurobi默认QCP停止设置和1e-9设置，共4项。

根据[Gurobi参数说明](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#parameterbarqcpconvtol)，
BarQCPConvTol单独控制二次约束障碍法的停止。先记录实际参数，再只改变这一项；
它不同于现有FeasibilityTol和OptimalityTol。此对照不改变A1/A2/A4，也不预设一定收敛。
旧运行保持原设置与判定。

## 5. 操作与边界

```powershell
julia +1.12.6 --startup-file=no --project=. scripts/check_r4_discrete.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r4_discrete.jl
julia +1.12.6 --startup-file=no --project=. scripts/study_r4_discrete.jl
```

保存和重读见[save_r4_discrete_run](@ref PaperRebuild.save_r4_discrete_run)、
[read_r4_discrete_run](@ref PaperRebuild.read_r4_discrete_run)；独立核验见
[validate_r4_discrete](@ref PaperRebuild.validate_r4_discrete)。
正式20项方法运行及128条逐模式记录见[结果与边界](ch04-discrete-results.md)。
下一项研究是网络重构，随后进入较大系统和第5章。
