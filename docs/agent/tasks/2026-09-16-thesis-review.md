# 论文主线与研究边界审读

- 任务 ID：READ-2026-09-16；负责人：Codex。
- 范围：识别研究问题、对象、模型、算法、目标、结果及未解决部分；同步阅读笔记。
- 输入：本地扫描 PDF 与用户转换的 DOCX；来源和哈希见 `docs/reading/sources.json`。
- 基线：`9b1c7ff`，`master`；开始时工作树干净，VS Code 无活动或可见未保存编辑器。
- 用户约定：本轮不提交、不推送。科学模型、求解器及实验不在本轮实施范围。
- 方法：DOCX 按 XML 块建立本地检索缓存，摘要—问题—章节模型—算法—算例—结论分层阅读；关键依据回 PDF 核对。
- 通过条件：七个核心问题都有出处；作者主张、算例证据与本项目判断分别表述；保留转换错误和未核实项。
- 停止条件：关键原页不清或资料不足时标为待核实，不自行补造参数或证明。
- 任务结果：完成跨章主线审读及 22 个原页的重点核查，未声称整页逐式转录或全文精审。
  已生成 3351 个 XML 块、182551 个字符的本地索引；块号不是页码。
- 人类文档：[论文主线](../../src/thesis-overview.md)、[审读证据与问题台账](../../src/thesis-audit.md)。
  其中区分作者报告值、原页不一致、本项目解释和未验证结论；保留完整阅读断点。
- 同步入口：README、Documenter 导航、阅读导航、来源清单、当前状态、手册及 CodeGroup。
- 工具：新增 DOCX 有界检索脚本与 Julia 表格算术脚本；没有新增科学模型或依赖。
- 未解决问题：Q01–Q10 见证据台账；重点是输入闭合、简化模型分类与可行性、式（5-75）及第 6 章停止逻辑。
- 下一步：PDF 30–37 设备/网络符号与单位，然后 PDF 46–54 的原式—近似—回代检查，
  再核对 PDF 55–60 和引用数据；没有足够输入时不伪造数值复现。
- 对应提交：本轮按用户要求不提交。

## 实际验证

以下命令均从项目根目录执行。Python 使用本机已有运行时，Julia 使用已有项目内 depot，
未修改全局版本或环境锁文件。

| 检查 | 实际结果 |
| --- | --- |
| `python scripts/read_docx.py index` | 成功；来源哈希、块数及字符数写入忽略的缓存 |
| `python scripts/read_docx.py find '备用交付风险' --limit 2` | 成功；中文匹配和输出条数上限正常 |
| `python scripts/read_docx.py show --start 377 --end 377 --limit 1` | 成功；指定块定位正常 |
| `python scripts/read_docx.py show --start 1 --end 81` | 预期拒绝，非零退出；超过 80 块不读取 |
| `python -m py_compile scripts/read_docx.py` | 通过；缓存忽略 |
| `julia +1.12.6 --startup-file=no --project=. scripts/audit_thesis_tables.jl` | 通过；结果与证据台账口径一致，仅为表值算术 |
| `julia +1.12.6 --startup-file=no --project=tools scripts/format.jl` | 通过 |
| `julia +1.12.6 --startup-file=no --project=docs docs/make.jl` | 严格构建通过，包括 doctest、交叉引用和页面检查 |
| `pwsh -NoProfile -File scripts/maintain.ps1 -Action Sync` | 成功同步新增文件，人工分组/UI 字段未改写 |
| `pwsh -NoProfile -File scripts/maintain.ps1 -Action Check` | 通过 |
| `git diff --check` | 通过 |
| 原件 SHA-256 复查 | PDF 和 DOCX 均与来源登记相同；原件未修改 |

## 运行条件与限制

- 首次 Sync 在受限沙箱内无法打开 `.codex/.local/maintenance/write.lock`；
  经工具权限流程后执行既有脚本成功，没有更改锁或钩子实现。
- 首次 Documenter 构建在沙箱中遇到 Julia doctest 管道 `EBADF`；
  在工具允许的沙箱外使用同一命令通过，未关闭 doctest 或降低严格检查。
- 本地维护目录检查只发现写锁，未发现原生会话基线/审阅记录。
  因而手动完成 Sync/Check，不构造 SessionId/TurnId，不声称真实钩子生命周期已经验收。
- 没有运行科学实验、包功能回归或维护脚本 fixture 全集：本轮未改动包功能与维护实现。
  文档构建、检索脚本检查及表格算术均不代表论文结论已独立验证。
- 新文档仅在本地工作区和忽略的构建目录；没有发布网站、提交或推送。
