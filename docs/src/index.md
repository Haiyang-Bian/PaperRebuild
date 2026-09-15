# PaperRebuild 复现手册

本项目使用 Julia 逐步复现一篇博士论文，同时建立能由后来者接续的开发和记录流程。
Codex 为主要智能体，VS Code 为主要 IDE，CodeGroup 按工作目的组织文件视图。

## 当前状态

处于工程基础阶段。已有扫描论文初步阅读导航；全文精读、数学模型转录和数值复现尚未完成。
包中的 `hello`、`domath` 为工具链示例，测试通过仅说明骨架可用。
详细状态见仓库中的[当前状态](https://github.com/Haiyang-Bian/PaperRebuild/blob/master/docs/agent/current-state.md)。

## 建议阅读顺序

1. 按[工具链](toolchain.md)安装环境，完成第一次测试和文档预览。
2. 通过[目录规范](structure.md)找到输入、代码、配置和输出。
3. 阅读[工作流程](workflow.md)和[质量规范](quality.md)，了解何时记录、检查和提交。
4. 开始研究时使用[记录模板](templates.md)，从[论文阅读导航](reading.md)确定小批次范围。

## 后续内容

Julia 基础教学、设备模型讲解、算法推导和完整复现实例均待补充。
本阶段仅提供工具链说明和这些内容的记录框架。
