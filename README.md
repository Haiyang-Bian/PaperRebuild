# PaperRebuild

使用 Julia 逐步复现博士论文，并沉淀可核查、可接续的研究流程。
主要智能体为 Codex，IDE 为 VS Code，文件视图使用 CodeGroup。

## 研究现状（2026-09-22）

**当前交付是多章方法与机制的研究基线，全文复现尚未完成。**
第2–7章已有Julia实现、公式/符号台账、合成或替代输入、独立验证和科学图表。
采用解释、作者原式、项目新增假设与失败记录分别保留。

| 研究线 | 当前证据 | 主要边界 |
| --- | --- | --- |
| 第3章调度 | 小系统模型、投影梯度、四模式及边界归因 | 原外层停止与规模性能未闭合，不发展v4 |
| 第4章交易 | 集中/独立运营、账本、议价、分布及稳态热相容性 | 支付转移不等于资源节约；较大系统分布仍未合格 |
| 第5章风险与市场 | 同模型分解对照、独立新日与压力样本 | 合成有限支持、完整未来补救不等于作者数据或在线控制 |
| 第6章保供 | 有限故障规划与热量跨时段转移证据 | 完整控制/故障域、资源移除时序仍需补齐 |
| 第7章系统应用 | 44电节点/38热节点/24小时替代系统 | 原输入缺口、实质备用与规模算法适用范围仍开放 |

最新[主体扩展性批次](docs/src/ch04-scalability.md)已保存4/12项：两个集中候选通过声明模型、
原电网及账本；固定模式分布零完整轮，整数分布126轮无合格联合候选。
原启动器已不存在，后8项未见启动记录，整批独立回放尚未完成。中断原因待查，原文件保留。
阶段分支集成用于保存可接续版本，不把这批前缀结果当作F13完成。

第7章近零备用候选的1000新日零违约，不能证明实质备用收益；
一个故障的区域容量下界6.045880 MWh排除当前替代输入的2 MWh目标，不能推广为作者原系统结论。
详细解释见[跨章结论](docs/src/reproduction-findings.md)，逐项缺口见
[原要求—证据对照](docs/src/reproduction-evidence-audit.md)和[全文覆盖](docs/src/reproduction-coverage.md)。

下一步按[研究计划](docs/src/research-next-steps.md)推进：中断审计与回放 → F13完整对照 →
F07规模性能 → 控制域/资源价值与非零备用 → 逐章可复核交付。
初学者先走[第一个可复核案例](docs/src/first-run.md)；已有隔离克隆预检仍复用包缓存，
不能称全新机器或全文验收。历史结果及各阶段结论保留在对应章节，不覆盖负结果。

## 入口

- [在线手册](https://haiyang-bian.github.io/PaperRebuild/)
- [第一个可复核案例](docs/src/first-run.md)、[原计划与证据对照](docs/src/reproduction-evidence-audit.md)
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
- [R4固定效用与可实施基线](docs/src/ch04-baseline.md)、[协调收益与参与条件](docs/src/ch04-baseline-results.md)
- [R4议价推导](docs/src/ch04-bargaining.md)、[分配与局部补证结果](docs/src/ch04-bargaining-results.md)
- [R4两阶段解释](docs/src/ch04-tspa.md)、[分歧点与罚项结果](docs/src/ch04-tspa-results.md)
- [R4分布协调推导](docs/src/ch04-distributed.md)、[固定模式对照与结果边界](docs/src/ch04-distributed-results.md)
- [全部电池模式与费用界](docs/src/ch04-discrete.md)、[离散核查正式结果](docs/src/ch04-discrete-results.md)
- [网络重构采用解释](docs/src/ch04-network.md)、[重构结果与热相容性缺口](docs/src/ch04-network-results.md)
- [热状态相容性推导](docs/src/ch04-heat-compatibility.md)、[同控制重构与失败原因](docs/src/ch04-heat-results.md)
- [第5章风险调度](docs/src/ch05-risk-results.md)、[固定价格分解](docs/src/ch05-benders-results.md)
- [连续策略报价](docs/src/ch05-strategic-results.md)、[执行规则与固定成交交付](docs/src/ch05-execution-results.md)
- [全文覆盖与未完成工作](docs/src/reproduction-coverage.md)
- [Codex 入口](AGENTS.md)与[当前状态](docs/agent/current-state.md)
- [参与开发](CONTRIBUTING.md)与[来源及许可](NOTICE.md)

## 第一次运行

安装 Git、Juliaup、VS Code 和 PowerShell 7（Windows PowerShell 5.1 也支持维护脚本）。
从项目根目录执行：

```powershell
juliaup add 1.12.6
julia +1.12.6 --startup-file=no --project=. scripts/bootstrap.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r1.jl
pwsh -NoProfile -File scripts/maintain.ps1 -Action Check
julia +1.12.6 --startup-file=no --project=docs scripts/preview.jl
```

默认预览地址为 <http://127.0.0.1:8000>；端口占用时以终端显示的地址为准，按 Ctrl+C 停止。
`juliaup add` 安装指定版本，不改变全局默认版本。安装依赖需要网络。
VS Code 的“任务：运行任务”提供同等入口。
上述测试为入门R1范围；完整隔离回归仍用`scripts/test.jl`，见[质量规范](docs/src/quality.md)。

## 本地文献

PDF 与 DOCX 不随仓库分发。合法副本可放入 `docs/摘要.pdf`、`docs/摘要.docx`，
核对 [来源登记](docs/reading/sources.json) 后按页阅读。
没有原件也能测试包和构建手册。Python 仅用于文献处理，科研实现使用 Julia。
