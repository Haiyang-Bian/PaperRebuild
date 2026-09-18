# Codex 工作手册

## 最小上下文

开始读 AGENTS、[当前状态](current-state.md)，按任务读代码、
[质量规范](../src/quality.md)和[目录规范](../src/structure.md)。
论文阅读走[阅读导航](../src/reading.md)与来源清单，不一次加载全书。
研究概览读[论文主线](../src/thesis-overview.md)，具体疑点与续读范围查
[证据台账](../src/thesis-audit.md)；不得把已建立索引或完成主线审读记成逐式审核完成。
跨会话以仓库记录为准，旧对话和文件名仅用于定位。
后续研究按[复现计划](../src/reproduction-plan.md)选阶段，按[验收协议](../src/reproduction-acceptance.md)
冻结判定条件；工具与模块以[Julia 技术设计](../src/julia-design.md)为准。
新增科研闭环优先 Julia。允许有边界地自行实现算法，但必须记录与原方法的差异及保证范围。

第 2 章工作先读 [模型详解与 C01–C12 疑点](../src/ch02-models.md)、[符号规则](../src/ch02-naming.md)。
公式/符号权威数据在 `docs/reading/ch02/`，改动后用 Julia `scripts/check_ch02.jl --sync` 更新生成页。
不得把 HS 效率方向、风电爬升段、z 的时间范围、水压方向或热核半步项静默改成常见模型。
R1 微型数据明确为合成，Gurobi 默认容差的失败运行保留；更严容差重跑不得放宽 A1 阈值。
文档展示按[质量规范](../src/quality.md)：API 读取 Julia docstring，公式有独立排版与编号，
不再生成整段源码/测试展示页；索引更新不得恢复已取消的展示方式。

第3章数据工作先读[数据搜集](../src/ch03-data.md)和`docs/reading/ch03/sources.toml`。
按来源锁定哈希，XLSX只读明确范围，不执行MATLAB文本或接受未经核验的公式缓存。
96样本不等于已经确认15分钟；33热节点公开基准不等于论文32热节点。保留D01–D09和Q01。

R2先读[模型解释](../src/ch03-models.md)、`docs/reading/ch03/model-issues.toml`和任务记录。
公式/符号由`scripts/check_ch03.jl --sync`同步，API仍为原生docstring卡片。
literal版本blocked不能静默改为checked；模型A1与原关系A1分别报告，压力锥松弛不取等也是结果。
保存运行前后源码哈希必须一致；开发中早期运行不自动进入正式摘要。

R3先读[采用解释和推导](../src/ch03-r3-theory.md)。固定流量接口复用R2Case；流量计划单独保存哈希。
诊断、修正距离和运行成本是三个目标，界不能混用。弹性问题有解不作为最终成功。
κ重构必须保留原解并检查依赖；最终电网原等式和独立WMM回放仍须通过A1。
R3第二批新增`r3_pg_checked_v1`：读[灵敏度与投影梯度](../src/ch03-r3-gradient.md)。
直接修正仍是独立基准；局部半空间只作一次试探，不累计成全局有效割。
原始对偶必须通过KKT；Gurobi对偶目前未通过该检查，不能用于声称已验证梯度。
可行性、外层停止和物理调度分别报告；论文规模未实现。
R3第三批使用显式`r3_pg_checked_v2`，读[稳健性与四模式](../src/ch03-r3-robustness.md)。
局部凸方向是项目补充，不能冒称可信梯度；原始对偶、缩放重试和原始变量方向分别保存。
四模式通过R3OperationSpec传入全部阶段；CT只固定源供温，新案例才使用有界负荷回水。
共同恢复尾段纳入成本，末端记忆状态须独立回放通过。VF固定流量子问题界不能当整个VF问题下界。
可选ObjBound/Pi不可用要保留缺失原因与已有候选；不要把属性错误当模型不可行。
双源VF-CT已有“PG未恢复、直接参考可行”的正式反例，后续优先复用该冻结输入分析边界，不重选容易通过的案例。
完整结果与仍开放的问题见[第三批报告](../src/ch03-r3-v2-results.md)及`docs/reading/ch03/r3-v2-issues.toml`。

R3第四批显式v3见[物理恢复与停止判据](../src/ch03-r3-v3.md)。恢复中间点不是调度成功，
原始变量局部方向不需要宣称可信对偶；驻点核验则必须逐次通过原KKT门槛与重读验证。
区分原停止、局部松弛模型驻点、原物理A1及费用优化完成。保留历史v2判定与固定尾段反例。
最终原等式求解失败不得覆盖已验证候选；恢复候选若留下，明确费用优化未完成。
既有cost_optimization_complete按候选所属内层模型解释；结合strict-dispatch-audit.csv检查
是否取得严格原等式调度，不能将A1合格SOCP的内层最优自动当成该调度完成。

## 文档更新路由

R4议价先读[单阶段分配](../src/ch04-bargaining.md)。总支付替代旧内部结算，增量补偿另存；
不能把无限额转移的解析解当成有支付上限市场的通用解。零/负剩余、原物理验收及所有子联盟稳定分开。
公式/符号权威记录为docs/reading/ch04/bargaining.toml，生成页由check_r4_bargaining.jl --sync维护。
TSPA原文采用松弛网络分歧点，本批未实现；下一阶段须审查罚项、可行域和(4-102)的前提。

2026-09-18起R3阶段归档，优先R4[集中交易与账本](../src/ch04-models.md)。
R4保留独立输入；不从R2Case或R3OperationSpec继承WMM/尾段。热能流合格不等于动态温度合格。
合同正向为出售，物理注入正向为注入网络；内部支付不计入社会资源成本。
AG0先独立求解后冻结聚合商计划；网络校核失败不能悄悄重调聚合商。
教学结算后的个体损失如实保留，不宣称公平分配或议价已实现。
R4首批正式证据见[结果与边界](../src/ch04-results.md)。AG0有热过剩反例，无可实施费用降幅。
区分同调度支付转移和资源收益；固定负荷退化改变偏好锚点，不作灵活性价值结论。
R4结果由check_r4_artifacts.jl检查摘要哈希；重绘不写入原运行目录，避免破坏其文件清单。

R4新基线见[可实施分歧点](../src/ch04-baseline.md)。偏好参数与flex分离；仅购能制度须在本地/集中/网络三阶段一致。
它是项目对照制度，不能冒充作者设置。没有通过网络原关系校核的分歧点不得生成收益率。
成本、内部支付和个体效用分别核算；完整热网温度可实现性仍未验证。全论文剩余工作见[覆盖清单](../src/reproduction-coverage.md)。
本批13运行见[新基线结果](../src/ch04-baseline-results.md)：两套仅购能AG0网络合格，开放AG0失败保留。
灵活AG0的B局部OPTIMAL但有效界缺失，不能把完整费用认证改为true。新摘要用check_r4_baseline.jl，旧19记录仍用原检查器。

R3第五批见[独立基线](../src/ch03-r3-baseline.md)和[归因结果](../src/ch03-r3-baseline-results.md)。
显式r3_paper_structure_v1不调用v2/v3恢复；检查源码调用边界和真实阶段记录。
冻结规则在configs/r3/baseline-study.toml；旧尾段与bounded_return_tail必须显式区分，旧默认不变。
停止审计仅取初值和接受更新；core_only仅比较共同核心指标，不参与周期总费用排名。
模型候选、κ重构、A1、原等式检查和所选候选费用完成五项分别报告。
最终报告目录保留artifact-hashes.toml；绘图只读CSV，图形配置记录生成脚本及输入哈希。

| 变化 | 审阅位置 |
| --- | --- |
| 环境、命令、依赖、VS Code | 工具链说明及相关锁文件 |
| 新文件、移动、删除 | CodeGroup Sync，职责变化时更新目录规范 |
| 模型、数据、实验 | 映射/实验记录、结果摘要、当前状态 |
| 假设、质量要求、方法 | 质量规范或适用协议、决策记录 |
| 任务完成或受阻 | 当前状态中的断点及证据 |

规则保留一个权威正文。无语义影响时说明理由，不制造文档 diff。
记录实际命令与结果，不填写未运行的检查。

## 维护命令

```powershell
pwsh -NoProfile -File scripts/maintain.ps1 -Action Sync
pwsh -NoProfile -File scripts/maintain.ps1 -Action Check
pwsh -NoProfile -File scripts/maintain.ps1 -Action Review -SessionId '<hook session_id>' -TurnId '<hook turn_id>' -Note '审阅路径、实际更新或无影响理由'
```

Review 填写钩子给出的会话/轮次 ID 与真实语义说明。
凭据绑定当前 HEAD、文件快照和分组内容；后续修改或提交使其失效。
无原生基线时手动 Check 并报告，不能伪造会话 ID。

## 生命周期

- SessionStart 提供短入口，包括压缩后的恢复；写入忽略的本地启动凭据供诊断，不修改文档。
- UserPromptSubmit 记录基线，包含用户已有脏文件。
- Stop 发现变化时同步生成导航并要求一次收尾。
- 已请求过或 `stop_hook_active` 为真时，不再阻止结束；仍有缺项则警告。
- 计划模式不写状态或导航；纯只读任务不改版本控制文件。
- 不自动科研实验、Git 提交、推送或调用第二个模型。
- 基线、审阅和事件文件只供本地诊断，不读取完整会话正文。
- 非法 JSON、路径越界、状态失效、写入冲突显式失败，不强制覆盖。

只维护 `paperrebuild-` 组成员与生成索引，保留人工组及 UI 字段。
结构检查与语义审阅分别负责，机器不能判定科学结论正确。

## 启用与验收

分别记录配置、fixture 测试、原生事件。通过 Codex `/hooks` 信任项目定义。
未信任时完成其他工作并报告待激活状态，不使用 bypass 或手写 trusted_hash。
依据：[官方钩子说明](https://learn.chatgpt.com/docs/hooks)。
