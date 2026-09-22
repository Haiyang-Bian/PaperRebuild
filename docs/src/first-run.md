# 第一个可复核案例

这条路线用一个小系统练习**理解输入 → 手算 → 求解 → 独立验证 → 看图 → 判断边界**。
只需要Julia 1.12.6及仓库的开放依赖，不需要论文PDF、DOCX或商业求解器。
首次安装见[工具链](toolchain.md)。从包含本页及相应脚本的版本开始；本地提交不等于远程已经发布。

## 1. 先认识这个物理问题

案例在`configs/r1/micro.toml`：两个电节点、一条配电支路、两个热节点及一对供回水管，
四个15分钟时段。CHP同时发电供热，HP/EB把电转为热，电池、热储能和建筑各有状态。
热水的输运需要时间，因此某一时刻的供热量与同一时刻的负荷不必相等。

输入明确标为`synthetic`。这是为了核对单位和方程而构造的教学系统，
不能据此推断作者系统的节约比例、备用收入或灾害保供能力。
拓扑与各设备含义见[模型详解](@ref ch02-models)及[历史F01–F04](ch02-status.md)。

## 2. 先做一个手算

采用作者常效率近似，CHP电效率为0.4、损耗比例0.1。当电出力为0.2 MW，
燃料输入为0.5 MW，其中热出力应为0.25 MW。若保持15分钟，热能为0.0625 MWh。
对应[式（2-1）及其采用边界](@ref eq-ch02-001)，Julia接口为[`chp_heat`](@ref)。

在VS Code的Julia REPL中执行：

```julia
using PaperRebuild
chp_heat(0.2, 0.4, 0.1) # 0.25 MW
0.25 * 0.25            # 0.0625 MWh
```

功率乘小时才得到能量；不要把15分钟直接作为乘数15。符号、希腊字母输入和数组下标见[符号规范](ch02-naming.md)。

## 3. 恢复环境并运行R1测试

在项目根目录打开终端，逐条执行：

```sh
julia +1.12.6 --startup-file=no --project=. scripts/bootstrap.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_ch02.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r1.jl
```

第一条恢复科学、文档和开发工具三个锁定环境，不改变全局Julia默认版本。
第二条核对公式、符号及实现映射。第三条只运行既有R1科学测试和任务目录选择测试，
VS Code任务名为`PaperRebuild: R1 tests`。
完整项目回归仍使用`scripts/test.jl`及[五组CI入口](quality.md)，不要将入门测试当全项目回归。

## 4. 求解并记下运行目录

```sh
julia +1.12.6 --startup-file=no --project=. scripts/run_r1.jl
```

VS Code也可运行`PaperRebuild: R1 micro case`。终端会打印`Run: results/runs/r1-...`；
这是本次运行的唯一目录。下面把它写成`RUN_DIR`，执行时必须换成刚才打印的真实路径。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/validate_r1.jl RUN_DIR
julia +1.12.6 --startup-file=no --project=. scripts/report_r1.jl RUN_DIR
```

求解入口为[`build_r1_model`](@ref)、[`solve_r1_case`](@ref)；
验证入口[`validate_r1_solution`](@ref)从保存数值重新计算关系，不直接使用JuMP的约束残差。
先看`validation.toml`的`relaxed_pass`与`original_branch_pass`，两项分别对应采用模型和原支路等式。
再在`residuals.csv`中找到失败的位置、单位和阈值。求解器显示最优不能替代这一步。

`PaperRebuild: R1 validate saved`默认按R1元数据的创建时间选最新默认运行，
不会选择R2–R9，也不会跳过失败结果。自定义run ID或者需要复核历史结果时请显式传路径。
若最新记录损坏，任务会报错，不自动换成更早的成功记录。

## 5. 重绘并解释图

下列`NEW_FIGURE_DIR`应是新的输出目录，例如`results/runs/redraw-r1-example`：

```sh
julia +1.12.6 --startup-file=no --project=docs scripts/plot_r1.jl RUN_DIR NEW_FIGURE_DIR
julia +1.12.6 --startup-file=no --project=docs docs/make.jl
```

绘图只读保存的解，不再次优化。每张图有PNG/SVG、CSV图源和`figure-config.toml`；
需要保留旧图时使用新的目录。文档本地预览见[工具链](toolchain.md)。

| 图 | 先观察什么 | 可以核对什么 |
| --- | --- | --- |
| F01 | 设备归属、供回水方向、单位 | 输入的连接关系；不证明水压可行 |
| F02 | CHP可行线段及保存的调度点 | 电热转换；图上重合还须查数值残差 |
| F03 | 管道延迟、室温、储能初末值 | 状态变化；多重最优可以产生不同合格轨迹 |
| F04 | 残差除以固定门槛，红线为1 | 哪些关系通过；零值显示处理见图源说明 |

## 6. 不求解，也能复核一个冻结结果

仓库内`results/summaries/r10-beginner-20260922-v2`保存本次隔离预检的小型证据包。
仅用Julia标准库执行：

```sh
julia +1.12.6 --startup-file=no scripts/r10_beginner_evidence.jl check results/summaries/r10-beginner-20260922-v2
```

也可使用包内`replay.jl check <包目录>`，移到别的路径仍可重验。
程序加载冻结的R1独立验证源码，重新计算235条保存数值残差、成本和图源身份；
不加载JuMP、Clarabel或Gurobi。文件哈希相符只是第一步，篡改后重新签写哈希仍会受到方程检查。
VS Code入口为`PaperRebuild: R10 beginner frozen replay`；对应移位/篡改测试为
`PaperRebuild: R10 beginner replay tests`。

本次预检的来源提交为`10a4c9e`，运行`r1-20260922T051904-b318689c`。
费用24.33235889299821教学货币单位，最大残差/门槛0.0010082611，模型和原支路等式均通过。
三环境恢复、63项既有R1断言、独立验证、重绘和严格Documenter/doctest实际通过；
环境文件和运行原件未被改写，四张PNG已逐图检查。
首版封存器的Julia动态绑定警告已在v2纠正，科学原件和验收不变。

这次克隆没有论文原件和历史运行数据，但复用了现有Julia包缓存，未移除本机商业许可。
因此证据证明的是这条开放入口能够运行；它不是全新操作系统或全文科学验收。
原Gurobi默认精度失败仍在`r1-first-batch`保留，不能被新的成功运行覆盖。

## 7. 下一步怎样进入研究主线

完成本例后，按[逐阶段计划](reproduction-plan.md)进入第3章的变流量和算法，
再进入第4章交易、第5章风险和第6章灾害恢复。
先读每章采用模型及输入边界，再读[跨章结论](reproduction-findings.md)和对应原值包。
当前未完成范围见[全文完成清单](reproduction-coverage.md)。
逐项验收与F01–F23的实际覆盖见[原计划与证据对照](reproduction-evidence-audit.md)。
