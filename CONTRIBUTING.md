# 参与开发

先阅读 [工具链](docs/src/toolchain.md)、[工作流程](docs/src/workflow.md)
与 [质量规范](docs/src/quality.md)。这里仅维护协作入口，不重复规则正文。

日常改动使用短期分支（Codex 默认 `codex/主题`），保持提交范围清晰。
基础建设保留现有 `master` 历史。提交消息使用 `类型: 具体变化`，例如
`docs: clarify input provenance` 或 `test: check heat balance residuals`。

提出变更时说明问题、最终行为、验证证据及仍存在的限制。
涉及研究假设或接受阈值时先记录决策，再执行实验；不要根据结果倒改成功标准。
修改工具链或依赖时更新锁文件及使用说明，并通过 CI。

公开仓库不包含论文原件、未授权数据、凭据及个人机器配置。
来源权利说明见 [NOTICE.md](NOTICE.md)。
