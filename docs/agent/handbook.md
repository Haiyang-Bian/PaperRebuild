# Codex 工作手册

## 最小上下文

开始读 AGENTS、[当前状态](current-state.md)，按任务读代码、
[质量规范](../src/quality.md)和[目录规范](../src/structure.md)。
论文阅读走[阅读导航](../src/reading.md)与来源清单，不一次加载全书。
跨会话以仓库记录为准，旧对话和文件名仅用于定位。

## 文档更新路由

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

- SessionStart 提供短入口，包括压缩后的恢复。
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
