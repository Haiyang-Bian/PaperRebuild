# 报价怎样进入Benders分解

已有[连续策略模型](ch05-strategic-model.md)把市场、所有情景的内部调度一次性交给求解器。
本节拆开其中的内部调度，仍求同一套明确采用的乐观模型。
新版本为`r5_strategic_benders_checked_v1`；数据仍是合成输入。
开发验证和正式实验分开记录，不能据小系统检查宣称论文规模加速。

## 从物理问题到主问题

IES先报价，市场给出购电和备用成交，之后设备需要在每个情景下兑现。
主问题负责“报什么价、接受哪些成交、哪些情景允许舒适下降”；
情景子问题负责“具体设备怎样运行、这份承诺是否能交付、补救费用是多少”。

原PDF93的(5-72)明确包括下层市场KKT；PDF94–97的(5-85)至(5-102)给出分解及关键情景流程。
所以不能在原固定价格Benders外套一个新名字就算策略报价已经接入。
这里复用完整市场KKT/SOS1、[支付恒等式](ch05-strategic.md)和三个成交桥接等式。
市场原始量、选择出的乘子及独立LP求解器原始乘子分别保存。

~~~math
\min\ \underbrace{\Pi^{\mathrm{IES}}}_{\text{市场净支付}}
    +\underbrace{\rho\lambda^Q+\sum_j\widehat p_j\nu_j^Q}_{\text{最坏补救费用上图}},
\qquad \lambda^Q D_{ij}+\nu_j^Q\ge\theta_i .
\tag{R5-SB1}
~~~

完整公式、变量单位与作者原式对应见[台账](ch05-strategic-benders-equations.md)。
风险模型内的日前价格必须为零，市场支付在外部只计一次。没有给市场乘子添加任意上界。

## 为什么旧条件割仍能使用

固定购电、上备用、下备用承诺和舒适开关后，情景补救仍是既有的同一个参数LP；
报价和市场价格没有作为新参数进入内部物理方程。因此可沿用
[条件Benders推导](ch05-benders.md)的原始对偶、有限盒及保护割。

每个情景都独立求解，包括最坏分布赋予零概率的情景。只有条件LP明确不可行，
才求有界弹性诊断。诊断可以生成可行性割或决定加入哪个关键情景，
但诊断解不是可交付调度，未通过KKT的乘子也不能生成可信割。

三条路线继续并列：

| 路线 | 可行性处理 | 界的范围 |
|---|---|---|
| `cuts` | 条件可行性割 | 完整声明的市场/风险域 |
| `critical` | 加入关键情景完整物理关系 | 完整声明的市场/风险域 |
| `paper_critical` | 再固定非关键情景舒适开关为零 | 关键集未覆盖全部情景时为受限域 |

所有路线从空割、空关键集开始。直接模型仅作事后参照，不提供初值、互补分支或割。
开放测试的固定互补分支另有显式标签；它们的收敛不是完整市场MPEC的证书。

## 怎样形成可信上下界

主问题的`theta`是补救费的估计，它可能还不足以支持实际调度。因此要依次检查：

1. 所选报价和成交满足市场原始/对偶关系、支付恒等式及桥接。
2. 所有情景的实际设备调度通过独立验算。
3. 费用最坏分布与风险最坏分布各自通过独立运输原对偶检查。
4. 独立市场LP在相同报价下得到相同最优值；不强迫退化市场给出相同成交。

这之后，市场净支付加实际最坏补救费才成为上界。选择最佳候选也按这个总数进行，
不能按内部补救费单项选择。下界保留主问题求解器原始值；
分项检查时临时扣除支付，不把扣除后的数值伪装成另一个求解器证书。

~~~math
U_k=\min_{j\in\mathcal V,\ j\le k}\left(\Pi_j+\sup_{p\in\mathcal P}
\sum_i p_iQ_i(x^j,z_i^j)\right),\qquad L_k=\max_{j\le k}L_j^{\mathrm{MP}}.
\tag{R5-SB3}
~~~

上式下界累计只适用于不变的完整声明域；受限舒适域扩张之前的界不能累计为完整域界。
部分割主问题无界也不能推出完整策略模型无界。这类结果保留原始状态，
不通过限价、限制乘子或参考解注入让它变成成功。

## 当前开发核验

完整SOS1开发对照中，六项完整域方法与后置独立直接模型通过同模型A2：

| 输入及路线 | 轮数 | IES净费用（合成USD） | 证书范围 |
|---|---:|---:|---|
| 竞争供给，cuts / critical | 3 / 3 | 2.085 | 完整采用MPEC |
| 热风险，critical | 5 | 1.36648 | 完整采用MPEC |
| 四时段，critical | 9 | −13.5508906216 | 完整采用MPEC |
| 阶梯连续报价 / 固定报价，critical | 3 / 3 | 7.46 / 14.2 | 各自完整采用MPEC |
| 竞争供给，paper_critical | 3 | 2.085 | 受限舒适域，不提升证书范围 |
| 容量不足，critical | 2 | 无候选 | 主问题证明对应完整域不可行 |
| 稀缺价格，critical | 1 | 无候选 | 仅主问题松弛报告DUAL_INFEASIBLE |

36项本机断言通过；完整R1–R5回归及追加记录审计后的113项开放专项通过。开发目录为
`results/runs/r5-strategic-benders-development-ready-20260919`；
完整市场和固定互补开放测试分别记录。
首轮因Julia延迟加载求解器的world-age错误未进入优化，错误与源码另存，
调整加载位置后才得到上述结果；没有改动数学模型或门槛。

**这些是开发验证，正式冻结批次尚待完成。**
它们证明现有小系统上市场与分解能够正确连接，不能证明论文规模加速，
也没有改变乐观成交选择的执行边界。负费用表示IES净收入，不是负资源消耗。

## Julia入口与验收

- [构建主问题](@ref build_r5_strategic_benders_master)：不求解、不写文件。
- [执行分解](@ref solve_r5_strategic_benders)：所有建模、求解及检查共享至多600秒。
- [独立重验](@ref validate_r5_strategic_benders)：不调用求解器，重建完整迭代和割的证据链。
- [保存](@ref save_r5_strategic_benders_run)与[重读](@ref read_r5_strategic_benders_run)：
  冻结源码、环境与哈希；拒绝覆盖和篡改。
- [比较](@ref compare_r5_strategic_benders_runs)：要求同输入、同域后才判断A2。

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/check_r5_strategic_benders.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r5_strategic_benders.jl
julia +1.12.6 --startup-file=no --project=. scripts/r5_strategic_benders_task.jl run configs/r5/strategic/competitive_hard_zero.toml critical
julia +1.12.6 --startup-file=no --project=. scripts/r5_strategic_benders_task.jl verify <运行目录>
~~~

本机完整市场需要原生SOS1；开放测试使用预声明互补分支和HiGHS/Clarabel。
这些解析例检查算法和费用，尚未替代正式批次、独立测试集、作者原始输入或论文规模实验。
执行规则与乐观选择的区别继续见[上一批对照](ch05-execution-results.md)；
本批不会把最小范数规则暗中混入被比较的策略模型。
