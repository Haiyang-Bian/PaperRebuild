# 目录与文件规范

| 位置 | 用途 | 版本控制 |
| --- | --- | --- |
| `src/` | 可导入的 Julia 模型与算法 | 提交 |
| `test/` | 测试与可公开的小型 fixture | 提交 |
| `configs/` | 显式参数、种子和实验配置 | 提交 |
| `scripts/` | 运行、阅读、检查及维护入口 | 提交 |
| `tools/` | 独立开发工具环境 | Project 和 Manifest 提交 |
| `tools/solvers/` | 可选 Gurobi 能力预检及 R1/R2/R3 本机对照环境 | Project 和 Manifest 提交，不含许可 |
| `tools/data/` | Julia公开数据下载、XLSX导入和初检环境 | Project 和 Manifest 提交 |
| `data/raw/` | 原始数据，附来源、许可和哈希 | 默认忽略数据 |
| `data/processed/` | 从原始数据派生的输入 | 默认忽略产物 |
| `results/runs/` | 独立运行目录、日志和原始输出 | 默认忽略产物 |
| `results/summaries/` | 核查后的差异表、失败记录及结论 | 提交 |
| `docs/src/` | Documenter 人类文档 | 提交 |
| `docs/agent/` | 智能体手册、当前状态、决策记录 | 提交 |
| `docs/reading/` | 原件登记与检查元数据 | 提交 |
| `docs/build/` | 生成的网站 | 忽略，仅部署构建产物 |
| `.codex/.local/` | 会话基线、审阅与触发记录 | 忽略 |
| `tmp/` | 阅读图片、隔离测试等临时材料 | 忽略 |

现有 PDF/DOCX 在 `docs/` 根目录精确忽略，来源登记允许本地文件缺失。
新增文献先登记来源和忽略路径，不能直接把大文件加入 Git。

使用仓库相对路径，配置以 `/` 分隔；禁止个人机器路径或凭据。
运行目录建议为 `日期_短名称_唯一标识`，每次独立，不覆盖旧目录。
公开图表连同生成配置、来源和说明进入摘要子目录，避免孤立图片。

可公开的小型测试数据放 `test/fixtures/` 并注明许可与来源。
单个提交文件超过 5 MiB 时检查拒绝，先设计外部来源登记。
目录随任务增量扩展，不预先为每个章节创建空模块。
未来模型、算法、独立验证与实验入口的职责按 [Julia 模块设计](julia-design.md)实施。

R1 已增量建立 `src/core/`（输入契约）、`components/`（设备）、`networks/`（恒流热核）、
`formulations/`（JuMP 约束）、`verification/`（数值独立验算）、`reporting/`（保存重读）。
`docs/reading/ch02/` 管理机器清单；生成公式/符号/实现索引页有明确标记。
`scripts/plot_r1.jl` 在 docs 环境提供绘图方法；科学包导入不加载绘图库。

R2沿用以上模块：`networks/water_mass.jl`提供纯数值输运，`formulations/r2.jl`构造优化模型，
`verification/r2.jl`独立回代。第3章公式/符号/疑点以`docs/reading/ch03/`为权威记录。
`configs/r2/`冻结合成输入；`experiment_r2.jl`保存独立批次，`report_r2.jl`生成审阅摘要，
`plot_r2.jl`从已保存解绘图。公开摘要位于`results/summaries/r2-first-batch/`，原始日志不直接发布。

R3在同一分层中增加`formulations/r3.jl`、`verification/r3.jl`、`reporting/r3_runs.jl`，复用R2Case。
`configs/r3/study.toml`冻结案例选择和边界变化；`experiment_r3.jl`执行预算受控闭环，
`r3_task.jl`提供验证/阶段比较/重绘，`report_r3.jl`从显式批次生成`results/summaries/r3-first-batch/`。
普通模型包不加载CairoMakie；绘图方法在docs环境由`plot_r3.jl`提供。
