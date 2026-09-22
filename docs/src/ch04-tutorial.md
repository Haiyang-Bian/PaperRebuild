# R4：从自调度到收益账本

## 1. 主体与资源

输入在configs/r4/。DSO位于节点1，有CHP、EB和电网接入；A位于节点2，有PV、HP和电池；
B位于节点3，有CHP、EB。两张网络都是1→2→3，四时段，每段1小时。
所有费用为合成美元，不能解释为某地区真实电价或论文原参数。

先读[采用模型与编号公式](ch04-models.md)、[59式台账](ch04-equations.md)和[符号表](ch04-symbols.md)。
输入经[load_r4_case](@ref PaperRebuild.load_r4_case)检查有限边界、单位、凸性和归属，首次求解前由freeze_r4.jl固化。
冻结脚本只接受相同内容；已存在且不同则拒绝，不能看到收益后改写原数据。

## 2. 交易和物理潮流

某时段A向B出售0.1 MW电力，时长0.5 h，则合同交付0.05 MWh。
按130美元/MWh，B付A 6.5美元；按5美元/MWh，A付DSO 0.25美元。
三者现金净收入为：DSO +0.25、A +6.25、B −6.5，总和为零。
此账本没有指定电力必须沿哪条线流动，支路潮流由节点平衡决定。

源码入口是[r4_ledger](@ref PaperRebuild.r4_ledger)，测试为test/r4.jl的“R4 model and ledger”。
独立验证使用保存的数值重新计算现金流，不调用建模器的目标或约束表达式。

## 3. 两种调度

[build_r4_model](@ref PaperRebuild.build_r4_model)只构造；[solve_r4_case](@ref PaperRebuild.solve_r4_case)才求解：

- independent：各聚合商按零售价求局部最优，再冻结出力、负荷和电池，交DSO做网络校核。
- central：联合优化设备和网络，只计真实资源、外部购电及不满意度。
- socp：电网使用锥松弛，另外回代原支路等式。
- exact：显式使用原支路等式，使用非凸求解器，保留实际界和状态。

源/荷端口用非负流量，温差上下界形成热功率包络。管道热损耗按参考温度冻结。
质量、热量和容量检查通过，只说明这一稳态能量流模型通过，不证明动态温度可实现。
输入热管损耗为每条0.0018 MW，四时段总损耗0.0144 MWh。损耗所需能量已由实际出力供给，不再重复加费。

## 4. Julia与VS Code入口

从仓库根目录执行；VS Code任务使用同样入口：

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/check_ch04.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r4.jl
julia +1.12.6 --startup-file=no --project=. scripts/run_r4.jl base central_socp clarabel
julia +1.12.6 --startup-file=no --project=. scripts/run_r4.jl base independent_exact gurobi
julia +1.12.6 --startup-file=no --project=. scripts/run_r4.jl base central_exact gurobi
~~~

Clarabel仅在显式枚举四时段16种电池状态时求解连续凸子问题，不处理非凸原电网等式。
Gurobi许可只在脚本调用时申请，普通导入模块不申请。每个模式600秒共享预算，包含内部子问题。

运行会输出保存目录。将其传入：

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/validate_r4.jl <运行目录>
julia +1.12.6 --startup-file=no --project=docs scripts/plot_r4.jl <运行目录>
~~~

重绘只读取数据。输入、软件环境、源码、原始数值、成本、解的状态和所有阶段一同保存；
[read_r4_run](@ref PaperRebuild.read_r4_run)检查哈希并重新验收，禁止覆盖原运行。不同配置不能冒充同输入费用对照。

## 5. 怎样解释结果

先检查模型、原电网等式、热能流、账本四项，再读费用和界。没有通过网络的AG0计划不能作为可实施收益基准。
集中成本下降也不能推出每个主体收益上升；需分别看支付前资源账、内部支付账和效用账。
改变同一物理调度的P2P价格，只会重新分配内部现金，不改变资源总成本。
禁P2P是合同分解的退化测试；它不是AG0，允许经过零售渠道完成同样物理注入。

本批未实现网络重构、ATC/ADMM或纳什议价，不声称公平、联盟稳定或论文规模复现。
