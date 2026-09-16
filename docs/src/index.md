# PaperRebuild 复现手册

本项目使用 Julia 逐步复现一篇博士论文，同时建立能由后来者接续的开发和记录流程。
Codex 为主要智能体，VS Code 为主要 IDE，CodeGroup 按工作目的组织文件视图。

## 当前状态

工程基础已建立，研究进入 R2 首批模型闭环。跨章主线见[论文主线与研究边界](thesis-overview.md)。
第2章76条公式已登记，新增[模型详解](ch02-models.md)、[符号规范](ch02-naming.md)
和[微型耦合案例](ch02-status.md)。第3章57条公式已登记，
[项目补全模型](ch03-models.md)与[合成实验结果](ch03-r2-results.md)可逐式检查。
完整数据、原式冲突、物理可行性恢复、市场/重构及论文结果复现仍待后续。
包中的 `hello`、`domath` 为工具链示例，测试通过仅说明骨架可用。
详细状态见仓库中的[当前状态](https://github.com/Haiyang-Bian/PaperRebuild/blob/master/docs/agent/current-state.md)。

## 建议阅读顺序

1. 按[工具链](toolchain.md)安装环境，完成第一次测试和文档预览。
2. 通过[目录规范](structure.md)找到输入、代码、配置和输出。
3. 阅读[工作流程](workflow.md)和[质量规范](quality.md)，了解何时记录、检查和提交。
4. 先读[论文主线](thesis-overview.md)了解研究问题，再从[阅读导航](reading.md)确定小批次范围。
5. 使用[记录模板](templates.md)，按[证据台账](thesis-audit.md)中的断点继续核查。
6. 实施前阅读[复现计划](reproduction-plan.md)、[验收协议](reproduction-acceptance.md)
   和[Julia 技术设计](julia-design.md)，按阶段启动最小可验证案例。
7. 从[第2章模型详解](ch02-models.md)进入编号公式、符号、[API 索引与 docstring](api.md)和验证映射，再按[R1教程](ch02-status.md)运行并检查图表。
8. 按[第3章R2教程](ch03-r2.md)比较WMM与SCHPD，区分求解器状态、模型约束通过和原物理误差。

## 后续内容

Julia完整基础课程、一般模型、后续章节算法推导与真实论文数据复现仍待补充。
当前教学案例使用公开合成数据，不是作者实验的独立复现。
