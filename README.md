# PaperRebuild

使用 Julia 逐步复现博士论文，并沉淀可核查、可接续的研究流程。
主要智能体为 Codex，IDE 为 VS Code，文件视图使用 CodeGroup。

**当前交付：R4集中式交易与核算基准。**R3阶段归档，保留算法限制和历史判定。
第4章59式已登记；6组合成输入完成18项正式运行及1项开放求解器对照。
5个集中原电网等式参考通过本批A1，6个独立自调度计划网络校核不可行，失败证据保留。
内部支付两两抵消，教学P2P结算不保证各方同时受益。原始论文数据、动态热网、重构和议价尚未完成。
`hello/domath` 仍只是包骨架，不计入科研进度。本轮实现尚未提交到远程。

## 入口

- [在线手册](https://haiyang-bian.github.io/PaperRebuild/)
- [本地工具链说明](docs/src/toolchain.md)
- [论文阅读导航](docs/src/reading.md)
- [论文主线与研究边界](docs/src/thesis-overview.md)、[审读证据与问题台账](docs/src/thesis-audit.md)
- [详细复现计划](docs/src/reproduction-plan.md)、[验收与科学图表](docs/src/reproduction-acceptance.md)
- [Julia 工具选型与代码设计](docs/src/julia-design.md)
- [第 2 章模型详解](docs/src/ch02-models.md)、[符号规范](docs/src/ch02-naming.md)
- [R1 运行教程与范围](docs/src/ch02-status.md)
- [第 3 章模型与补全边界](docs/src/ch03-models.md)、[R2 运行教程](docs/src/ch03-r2.md)
- [R2 合成实验结果与 F04/F05](docs/src/ch03-r2-results.md)
- [R3 采用解释](docs/src/ch03-r3-theory.md)、[投影梯度](docs/src/ch03-r3-gradient.md)
- [R3 稳健性与四模式教程](docs/src/ch03-r3-robustness.md)
- [第三批32例结果与图表](docs/src/ch03-r3-v2-results.md)
- [v3物理恢复与停止判据](docs/src/ch03-r3-v3.md)、[R3第四批30例结果](docs/src/ch03-r3-v3-results.md)
- [R3差异归因与阶段边界](docs/src/ch03-r3-baseline-results.md)
- [第4章模型与账本](docs/src/ch04-models.md)、[R4运行教程](docs/src/ch04-tutorial.md)、[首批结果与图表](docs/src/ch04-results.md)
- [Codex 入口](AGENTS.md)与[当前状态](docs/agent/current-state.md)
- [参与开发](CONTRIBUTING.md)与[来源及许可](NOTICE.md)

## 第一次运行

安装 Git、Juliaup、VS Code 和 PowerShell 7（Windows PowerShell 5.1 也支持维护脚本）。
从项目根目录执行：

```powershell
juliaup add 1.12.6
julia +1.12.6 --startup-file=no --project=. scripts/bootstrap.jl
julia +1.12.6 --startup-file=no --project=. scripts/test.jl
pwsh -NoProfile -File scripts/maintain.ps1 -Action Check
julia +1.12.6 --startup-file=no --project=docs scripts/preview.jl
```

默认预览地址为 <http://127.0.0.1:8000>；端口占用时以终端显示的地址为准，按 Ctrl+C 停止。
`juliaup add` 安装指定版本，不改变全局默认版本。安装依赖需要网络。
VS Code 的“任务：运行任务”提供同等入口。

## 本地文献

PDF 与 DOCX 不随仓库分发。合法副本可放入 `docs/摘要.pdf`、`docs/摘要.docx`，
核对 [来源登记](docs/reading/sources.json) 后按页阅读。
没有原件也能测试包和构建手册。Python 仅用于文献处理，科研实现使用 Julia。
