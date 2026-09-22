# 第 2 章可核查记录

- `formulas.toml`：式 2-1 至 2-76 的完整编号清单，原页、符号、疑点和实现映射。
- `symbols.toml`：符号定义权威位置，含原文别名、单位、Julia/ASCII 映射与维度。
- `inputs.toml`：当前输入来源与尚缺作者输入；不是用合成数据填补原始参数。
- `targets.toml`：本批验收目标、阈值入口与停止条件。

人类说明在 Documenter `ch02-models.md`、`ch02-naming.md`、`ch02-status.md`；
公式、符号与实现测试映射页由 `scripts/check_ch02.jl --sync` 生成；API 由 Julia docstring 构建。
原式右侧标原论文编号，正文也从 `formulas.toml` 读取选用的原式，不复制实现全文。
已核读 PDF 14–17、30–44；DOCX 仅用于定位，不作为已核准公式来源。
所有原件仍本地保存；不要提交页面截图或整章转印。
