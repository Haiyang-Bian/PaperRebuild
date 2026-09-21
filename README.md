# PaperRebuild

使用 Julia 逐步复现博士论文，并沉淀可核查、可接续的研究流程。
主要智能体为 Codex，IDE 为 VS Code，文件视图使用 CodeGroup。

**当前进度以[当前状态](docs/agent/current-state.md)和[全文覆盖清单](docs/src/reproduction-coverage.md)为准。**
最新研究入口为[第7.4节原模型带初值对照](docs/src/ch07-seeded-risk.md)：44电节点/38热节点、
24小时、100个合成情景。原[共同调度](docs/src/ch07-common-witness.md)提供396812.219543CNY/日可行上界。
新三项同模型运行均在600秒内：3A仍超时无候选，3B/3C返回并独立验证候选，但费用与初值相同、
有效间隙32.95%，没有备用经济收益或最优性证据。上下备用在数值零内，未开展本批样本外评价。
下一步检验等价的稀疏装配表示，再决定规模分解；第7.5节可按独立输入继续。
历史[流量/终端结果](docs/src/ch07-flow-results.md)和[交易/重构结果](docs/src/ch07-network-results.md)保留各自边界。

此前[R8稳态能流与跨时段机制](docs/src/ch06-r8-energy-results.md)、
[R7有损共同状态规划](docs/src/ch06-lossy-flow.md)和[R6样本外统计](docs/src/r6-test-results.md)的正负结果均已保留。
已有论文示范区节点规模的迁移，缺失参数仍为明确标注的合成替代值；尚未完成全论文或作者同输入数值复现。

**以下保留R4历史阶段摘要。**热状态相容性核查的34个父调度在两组预先声明温度带下完成272条阶段记录；
26个能在设备、热交付和费用不变时重构稳态供回水状态，其中24个同时通过原电网检查。
8个开放交易调度在两组温度带下都有解析质量流区间冲突，不能只靠调整热状态消除。
本批仍采用冻结参考损耗，不认证水压、动态或实际温度相关散热。
当批结论见[相容性结果与图表](docs/src/ch04-heat-results.md)，后续新模型另见
[稳态循环与温变散热](docs/src/ch04-thermal-results.md)，历史判定保持。

前批网络重构的34项整数运行与72项连续穷举保留：34项采用模型通过，28项原电网通过。
电瓶颈例0.12011%费用改善得到本批稳态热相容性补证；开放交易0.05684%仍只是旧简化模型费用差，
不能声称电热可实施收益。热网重构未显示收益。详见[重构历史报告](docs/src/ch04-network-results.md)。

前批R4全部电池模式与精度核查：四套输入的16模式均已执行，20项完整方法运行已保存。
分布58/64模式通过采用模型，44/64通过原电网；最好模型费用与集中穷举最大相对差0.000929%。
四套均有物理合格候选，但开放灵活例最低松弛费用对应候选未过原电网，另存较高费用的合格计划。
R3阶段归档，保留算法限制和历史判定。前批18项分布运行与18项独立参考全部保存：Clarabel的8项集中福利分解通过采用模型与费用对照，
最大费用相对差约0.000636%，其中7项通过原电网等式。8项独立交易中原始6项A1通过，
仅收紧成本辅助量后的8项候选均通过，控制和实际费用不变，原失败判定保留。
两项Gurobi分布运行达到内层上限。全部电池模式核查覆盖了有限离散搜索，
尚不构成整数分布算法的一般收敛证明或论文规模速度验证；重构见本轮独立集中对照。
第4章首批59式及16条议价/TSPA原式已登记；首批6组合成输入完成18项正式运行及1项开放求解器对照。
5个集中原电网等式参考通过本批A1，6个独立自调度计划网络校核不可行，失败证据保留。
内部支付两两抵消，教学P2P结算不保证各方同时受益。原始论文数据、完整动态热网、整数分布协调及论文规模重构尚未完成。
第二批新增13条冻结证据，分离负荷偏好与可调范围；仅购能制度下取得两个可实施AG0，
灵活例同制度候选节约3.96%，但原零售价下A/B效用下降。
第三批补齐旧局部候选的独立有效界，并完成4项固定调度Nash分配；容量权重下三方均比指定AG0受益。
原B缺界记录保持不变，分配依赖无限额转移，不宣称所有子联盟稳定或作者同输入复现。
第四批TSPA完成8流程/16核算；8项弹性模型通过，仅3项原关系通过。开放固定负荷有热守恒反例，
罚项改变账面剩余而不创造资源收益。上述批次的原判定与失败证据保留。
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
