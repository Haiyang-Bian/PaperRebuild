# 可选求解器能力预检环境

用途：检验本机 Julia/JuMP/Gurobi 的接口、许可及基础数学问题求解能力。
不包含论文科学模型，不替代物理回代、算法验收或论文结果对照。
根包测试和 Documenter 构建不依赖这个环境。

从仓库根目录执行：

```powershell
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/bootstrap_solvers.jl
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/check_solvers.jl
```

VS Code 的 `PaperRebuild: solver bootstrap` 和 `PaperRebuild: solver check` 对应上述命令。
首次先恢复环境；许可由本机已有 Gurobi 配置提供，不将许可文件、密钥或环境凭据写入仓库。
如使用自定义 `JULIA_DEPOT_PATH`，恢复与检查必须使用相同设置。

Project/Manifest 锁定接口和二进制包。Gurobi.jl 可能使用 JLL 引擎，
不应根据系统 `gurobi_cl` 的版本推断实际求解引擎。
当前已核验 Julia 1.12.6、JuMP 1.31.2、Gurobi.jl 1.9.3、引擎 13.0.3。

检查包括 LP/对偶、MILP、SOCP/连续对偶、MISOCP、有界非凸二次、非线性表达式、
不可行状态和 2101 变量规模例。每例求解时间上限 30 秒，单线程、固定种子。
任何失败使脚本非零退出；结果与哈希写入本地忽略的
`tmp/solver-checks/qualification-*/report.toml`，不覆盖以前运行。
这些小例不能证明完整求解器能力、论文规模性能或未来许可持续有效。

工具选型和后续接入以 [Julia 技术设计](../../docs/src/julia-design.md) 为准。
