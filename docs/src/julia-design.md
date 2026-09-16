# Julia 工具选型与代码组织

日期：2026-09-16。设计依据是论文的问题结构与[复现计划](reproduction-plan.md)，
不按包名反向简化科学问题。以下区分“已预检”“选定但待接入”“候选”。
工具的适用性参考本页链接的官方资料；版本最终由对应环境 Manifest 锁定。

## 1. 主技术路线

**Julia 1.12.6 + JuMP/MathOptInterface 建模，Gurobi 主求解，Julia 自编论文外层算法，
CairoMakie 输出科学图，Documenter 汇总说明。**

新数据准备、实验编排、检查、统计和绘图优先使用 Julia，保持配置—运行—验证—图表闭环。
外部求解器通过 Julia 接口调用仍属于这个闭环，不要求底层算法全部以 Julia 编写。

### 作者实际采用的工具与方法

- 表 3-7 及正文（印刷 43 / PDF 60）明确写 MATLAB、Gurobi 10.0.1。
  表中 **NM-CHPD** 是文献 [36] 的模型对照，表注是 Gurobi NonConvex 直接求解双线性问题。
  它不能因为缩写 NM 就被当作 Nelder–Mead。
- 第 4–6 章算例说明同样报告 MATLAB/Gurobi；第 5 章使用 k-means 形成代表性场景，
  并报告蒙特卡洛样本外测试。文本定位 B1558–1561、B2081、B2128、B2555。
- 本轮没有找到必须采用某个 MATLAB 专有工具箱的证据，不据此补写 YALMIP/其他工具箱为作者依赖。
  如果后续取得作者代码或文献 [36] 的实现，再登记真实版本、算法选项及等价替代方式。

复现的对象是数学模型、更新规则和结果口径。作者运行环境作为比较信息保留；
新版求解器/硬件下的绝对秒数不能直接当作算法加速贡献。

## 2. 优化工具的选择

| 工具 | 决定与用途 | 适用限制 |
| --- | --- | --- |
| **JuMP + MathOptInterface（MOI）** | 选为代数建模与求解状态接口；变量/约束命名、导出模型、取解/对偶/界 | JuMP 是建模层，不能靠统一 API 消除求解器能力差异 |
| **Gurobi.jl** | 主求解器：LP/QP/MILP、SOCP/MISOCP、可支持的非凸二次与非线性小型直接对照 | 同时记录接口版与引擎版；全局结论取决于有效模型、终止状态与界，不能只看目标值 |
| **HiGHS.jl** | 选为无商业许可的 LP/MILP/凸 QP 基准和公共 CI 工具 | 不作为通用 SOCP、MISOCP 或非线性求解器 |
| **Clarabel.jl** | 选为连续凸锥子问题的独立交叉验证，检查锥模型与对偶 | 不直接求带整数变量的完整模型 |
| **Ipopt.jl** | 选为连续非线性物理回代、局部求解与固定离散变量后的对照 | 局部结果，不能给非凸原问题全局证书；不能直接处理整数 |
| **Optim.jl** | 条件选用：低维外层参数搜索、Nelder–Mead 或局部优化对照 | 不是表 3-7 的 NM-CHPD；一般网络等式和整数约束不能仅加罚函数便声称等价 |
| **BlackBoxOptim.jl** | 候选：不光滑且无法可靠求导的低维外层启发式搜索 | 固定随机种子/评估预算，独立验证约束；无有效界时不宣称全局最优 |
| **BilevelJuMP.jl** | 候选：第 5 章小型双层市场交叉核验 | 主实现保留可审查的 KKT/对偶转换；不能把双层软件接口当成任意整数下层的等价解法 |
| **Alpine.jl** | 候选：支持表达式范围内的小型非凸全局对照，主求解器受阻时评估 | 需额外子求解器和有界变量；单独验收实际支持的模型 |
| **Juniper.jl** | 候选：混合整数非线性可行解/启发式对照 | 官方明确为启发式，不可用来替代全局认证 |
| **Optimization.jl** | 暂不叠加为第二套主建模框架；若后续出现仿真参数估计再评估 | 当前 JuMP 更直接表达大量显式网络/整数约束，避免重复维护相同模型 |

依据：
[JuMP 状态与解](https://jump.dev/JuMP.jl/stable/manual/solutions/)、
[Gurobi.jl 能力与环境](https://jump.dev/JuMP.jl/stable/packages/Gurobi/)、
[Gurobi 非线性求解](https://docs.gurobi.com/projects/optimizer/en/current/features/nonlinear.html)、
[HiGHS.jl](https://jump.dev/JuMP.jl/stable/packages/HiGHS/)、
[Clarabel](https://clarabel.org/stable/)、
[Ipopt.jl](https://jump.dev/JuMP.jl/stable/packages/Ipopt/)。

搜索/扩展工具依据：
[Optim](https://julianlsolvers.github.io/Optim.jl/latest/)、
[BlackBoxOptim](https://github.com/SciML/BlackBoxOptim.jl)、
[BilevelJuMP](https://joaquimg.github.io/BilevelJuMP.jl/stable/)、
[Alpine](https://jump.dev/JuMP.jl/stable/packages/Alpine/)、
[Juniper](https://jump.dev/JuMP.jl/stable/packages/Juniper/)、
[Optimization.jl](https://docs.sciml.ai/Optimization/stable/)。

### 对论文各章的映射

- 第 3 章：JuMP/Gurobi 构建经核实的简化/固定流量子问题；Julia 实现投影梯度和可行性恢复。
  NM-CHPD 直接对照使用原模型和 Gurobi 非凸模式，Ipopt 只提供另列的局部参照。
- 第 4 章：JuMP 子问题 + Julia 的 ATC/ADMM/议价协调；先用集中模型做基准。
- 第 5 章：市场出清、概率运输和线性/整数重构由 JuMP 求解；Julia 实现双线性 Benders、
  场景筛选与全情景复查；小例与扩展式/BilevelJuMP 对照。
- 第 6 章：JuMP 主/恢复/对手模型，Julia 实现内外 C&CG；微型故障集合穷举作为验证基准。

模型分类尚有疑点时先解决台账，例如 Q10；不能因为选了 Gurobi 就把原式直接贴上 MISOCP 标签。

## 3. 数据、统计、物理和图表工具

| 功能 | 选型 | 引入时机 |
| --- | --- | --- |
| 配置与身份 | Julia 标准库 TOML、SHA、Dates、UUIDs、Random、Test | 从第一批开始；配置与哈希不依赖 Python |
| 表格输入输出 | CSV.jl + DataFrames.jl | R0/R1；输入边界使用表格，模型内部转有类型数组/结构 |
| 大型结果 | 首选开放 CSV；确有体积/类型需求时再选 Arrow/JLD2 | 不把 Julia 二进制快照作为唯一长期结果 |
| 场景生成/聚类 | Clustering.jl、Distributions.jl、StatsBase.jl | R5；k-means 特征、标准化、初始化、权重与种子均记录 |
| 统计验收 | Distributions.jl 的分位数；HypothesisTests.jl 等做交叉核验 | R6；按 A5 明确联合事件和独立样本单位 |
| 导数验证 | JuMP 的导数能力；必要时 ForwardDiff.jl 与有限差分 | R3；仅对兼容的光滑 Julia 函数使用，不直接微分 Gurobi 黑箱 |
| 拓扑 | 简单关联矩阵先用标准库；连通/孤岛验证需要时引入 Graphs.jl | R1/R7；验证器与优化拓扑约束相互对照 |
| 量纲 | 内部统一 MW/MWh、kg/s、K、小时和明确货币；需要时 Unitful.jl 做输入边界检查 | 不把带单位对象未经验证地塞入优化系数 |
| 详细物理参照 | 需要独立时域模型时再评估 DifferentialEquations/OrdinaryDiffEq 等 | 先有物理方程和边界，再选择数值积分器；与论文离散模型分开 |
| 科学图 | CairoMakie.jl，PDF/SVG/PNG | R1 起；统一风格、字体、轴单位、源数据和图 ID |
| 文档 | 已有 Documenter.jl | 贯穿所有阶段；从验收摘要引用图和指标 |

直接依据：
[CSV](https://csv.juliadata.org/stable/)、
[Clustering k-means](https://juliastats.org/Clustering.jl/stable/kmeans.html)、
[Distributions](https://juliastats.org/Distributions.jl/stable/)、
[HypothesisTests](https://juliastats.org/HypothesisTests.jl/stable/)、
[ForwardDiff 限制](https://juliadiff.org/ForwardDiff.jl/stable/user/limitations/)、
[CairoMakie](https://docs.makie.org/stable/explanations/backends/cairomakie)。
候选包须在真正接入时核对官方支持范围并锁版本，不一次安装全部生态包。

## 4. 允许轻量自实现，怎样确定边界

用户已明确允许按需要引入其他工具，并调研公开方法实现 Julia 版本。
采用以下顺序，发生能力缺口时继续推进可验证的工作：

1. **辨明缺口。**是 Julia 包没有接口、表达式不受支持、数值不稳定、规模太大，还是论文算法本来就要自己写？
   保留最小失败例和原始错误，不把不同问题统称“Julia 做不到”。
2. **优先接口/等价表达。**检查 MOI bridge、Julia 的 C/动态库接口、外部程序的文件交换及成熟开放库。
   转换须保留约束和保证；不能为绕过接口删除困难约束。
3. **实现论文算法层。**投影梯度、ATC/ADMM 更新、非对称议价流程、有限概率运输编排、
   Benders 割管理、场景筛选、嵌套 C&CG 与故障枚举是适合自实现的范围。
   LP/MIP/SOCP 子问题继续交给已验证求解器。
4. **专用算法试验。**必要时可实现受限问题的主动集、分支定界、分段线性化或空间划分原型，
   但先限定变量/函数类型、边界、凸性和规模，说明返回局部解、可行解还是有界证书。
   公布原理不等于复现商用软件的全部预处理、割、数值稳定性和性能。
5. **达标才接入。**算法身份证列出处、假设、伪代码、停止条件、复杂度、包/版本、
   与作者实现差异及保证范围。未经验证的实现放试验区，不成为正式结论的唯一依据。

### 自实现算法的最小验收包

- 至少包含解析例、可穷举例、成熟求解器对照，以及不可行、无界、退化、缩放困难等适用的失败例。
- 第一轮限定最多 20 个决策变量、4 个时段、3 个随机情景或 4 条脆弱线路；
  超出前先冻结专用测试协议，不能因一例成功直接扩到论文大系统。
- A1 验证物理/数值解；A2 验证更新、割和界。宣称全局保证时，需要有效松弛与界的依据，
  小例吻合本身不构成一般证明。
- 同一输入和预算比较正确率、可行率、目标/界、时间和内存，保留反例。
- 若不能维护有效界或目标结构不符合前提，保留 `heuristic_only` / `not_certified`，
  可继续作为候选解生成器，但不能驱动 Benders/C&CG 的认证停止条件。

例如，缺少直接可用的“论文 DRJCC 求解包”时，可在 Julia 中自行实现情景循环、运输分布子问题和割更新，
用 JuMP/Gurobi 解每个数学子问题，再以小型全情景模型对照。
这比从头开发通用 MILP 求解器更贴近当前科学问题。
公开的 [JuMP Benders 教程](https://jump.dev/JuMP.jl/stable/tutorials/algorithms/benders_decomposition/)
可作为软件模式参考，论文的双线性和风险约束仍需独立推导。

## 5. 拟定模块结构

保持包名/UUID和已有目录；随阶段增量创建下列文件，不批量生成空模块。
顶层 `PaperRebuild` 是公共入口，下面优先普通 Julia 文件和小型类型/函数，只有需要隔离职责时才设子模块。

```text
src/
  PaperRebuild.jl
  core/           # IDs, CaseData, TimeGrid, SourceRef, SolverPolicy, RunResult
  data/           # TOML/CSV 读入、单位归一、来源/拓扑/时序校验
  components/     # CHP、转换设备、电/热储能、建筑
  networks/       # 配电网、节点法热网、简化热网、灾后等效热储能
  formulations/   # ch03_dispatch、ch04_trading、ch05_reserve、ch06_resilience
  algorithms/     # projected_gradient、atc_admm、bargaining、benders、nested_ccg
  verification/   # 独立物理残差、会计账、界/割、统计风险、故障穷举
  reporting/      # 指标、对照表、图源表、CairoMakie 绘图
  studies/        # 配置驱动的章节编排；不在 import 时运行
scripts/
  run_study.jl    # 未来：一次明确 study/config 的运行入口
  validate_run.jl
  compare_runs.jl
  plot_run.jl    # 只读运行输出，不调用优化
  ch03/ ... ch07/ # 仅当章内操作确有专门职责时添加薄入口
configs/
  cases/         # 网络/设备/时序入口与版本
  studies/       # 场景矩阵、模型变体、求解器、种子、预算、验收协议
test/
  unit/ integration/ algorithms/ regression/ fixtures/
```

目录名是设计，不是已实现 API。架构遵循
[JuMP 大模型设计建议](https://jump.dev/JuMP.jl/stable/tutorials/getting_started/design_patterns_for_larger_models/)，
模型构建使用函数和明确数据，避免靠全局变量传递模型状态。

### 核心接口契约

| 拟定接口 | 输入 → 输出 | 必守要求 |
| --- | --- | --- |
| `load_case(path)` | 数据/来源配置 → 有类型 `CaseData` | 缺数据报错，单位和初始历史显式 |
| `build_dispatch(case, spec, optimizer_factory)` | 数据 + 章节模型变体 → 模型及命名变量/约束映射 | 不求解、不写文件；保留公式来源 ID |
| `solve_study(case, spec, policy)` | 完整配置 → `RunResult` 与迭代轨迹 | 预算传播；先查状态再读取目标/变量/对偶 |
| `validate_solution(case, spec, result)` | 原数据 + 数值输出 → 分项 `ValidationReport` | 无 JuMP 变量引用也能回算，模型约束与原式分开 |
| `compare_runs(runs, targets)` | 已验证输出 + 论文指标 → 差异表 | 拒绝混合不相容配置/单位/数据版本 |
| `plot_run(run, figures)` | 落盘数据 + 图配置 → 图和图源清单 | 不重新求解；失败/未定状态可见 |

模型类型显式区分 `NodeMethodHeat`、`SimplifiedHeat`、`EquivalentTwoTankHeat`，
以及完整/线性化配电潮流、价格接受/制定者、加权/逐场景失供要求。
共享数据结构不等于共享所有可行域；各章节不得默认继承上一章的假设。

### 求解器与并行约定

以 `optimizer_factory` 注入求解器，物理模型文件不固定写死 Gurobi。
运行时才创建许可环境；导入包不申请许可或启动实验。
需要连续 QCP 对偶时显式配置 `QCPDual=1`，并检查 dual status；
MIP 或非凸模型不因设置该参数就能提供可用的理论对偶。
参数依据见 [Gurobi QCPDual](https://docs.gurobi.com/projects/optimizer/en/current/reference/parameters.html#parameterqcpdual)。

串行基准先通过，再考虑场景并行。Gurobi 环境不在线程间共享并发使用；
每个进程/工作者有独立运行上下文及许可预算，记录线程总数，避免超额并行扭曲比较。
所有研究结论都保留实际求解器版本和参数。

## 6. 环境与 VS Code 任务

根目录仍是科学包环境，`docs/` 是文档，`tools/` 是格式工具。
本轮增加可选的 `tools/solvers/`，只用于选型预检并有独立 Project/Manifest，
不使普通文档构建和骨架测试依赖 Gurobi 许可。
正式科学实现时按阶段将实际需要的包接入根环境；Gurobi 通过可选依赖/扩展或实验适配器加载，
迁移后删除重复职责的预检环境须另行审查。

本轮可执行入口：

```powershell
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/bootstrap_solvers.jl
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/check_solvers.jl
julia +1.12.6 --startup-file=no --project=. scripts/audit_thesis_tables.jl
```

第一个命令恢复环境，第二个只检查求解器能力，第三个只核算论文表值。
对应 VS Code 任务名称为 `PaperRebuild: solver bootstrap`、`solver check`、`thesis arithmetic`。
科研入口尚未实现，不提前添加指向不存在脚本的任务。
将来的 `run / validate / compare / plot` 任务显式选择 TOML 配置，不提供一键默认运行所有大实验。

现有 Python 工具仅保留在扫描渲染/OCR/历史 DOCX 索引辅助边界；之后确需迁移时，
Julia 负责流程与哈希，外部文献工具可通过命令接口调用并记录版本。
既有 PowerShell 钩子先保留，不能以“外套一个 Julia 启动器”声称已迁移。
如迁入 Julia，须覆盖既有 5.1/7 行为、中文/BOM、会话、并发、只读规划与续做上限等测试，
重新经过原生信任流程。科研闭环不等待这项维护迁移。

## 7. 已执行的能力检查

本轮使用 Julia 1.12.6、JuMP 1.31.2、Gurobi.jl 1.9.3，
Pkg 解析的 Gurobi 引擎为 **13.0.3**；系统命令行安装为 **13.0.2**，两者不同并已记录。
原论文为 10.0.1，不能宣称运行环境完全一致。

在本机许可下，已通过 8 个有已知答案的检查：LP 与对偶、MILP、SOCP 与连续对偶、MISOCP、
有界非凸二次、非线性表达式接口、不可行状态、2101 变量规模检查。
例如 SOCP 的最优值为 5，固定变量对应对偶约为 0.6000002；非凸例目标为 1 且给出有效界。
这支持接口与本次许可可用，不保证论文大模型的性能或未来许可持续有效。

预检输出到忽略的 `tmp/solver-checks/qualification-*/report.toml`，记录脚本/环境哈希及逐项状态。
公开文档不写许可 ID、凭据、个人机器路径或完整许可日志。
HiGHS、Clarabel、Ipopt 等当前完成文档选型，尚未在本项目接入或通过交叉求解测试。
