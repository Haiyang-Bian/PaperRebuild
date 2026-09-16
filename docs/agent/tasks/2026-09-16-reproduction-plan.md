# PLAN-2026-09-16：分阶段复现计划与 Julia 工具选型

## 任务与范围

按论文主线制定详细步骤、交付物、一般测试、科学验收和图表要求；
设计 Julia 优先的工具、模块和实验脚本结构，为可执行辅助脚本提供 VS Code 任务。
用户补充允许引入其他工具，并在必要时调研公开算法、轻量自实现。
本轮不启动论文模型，不提交、不推送；沿用上一轮暂不提交约定。

## 开始状态与保护

- 起始分支 master，HEAD `9b1c7ff8e2ef9517b7eafa38b2952559cad88261`。
- 上轮主线审读、证据台账、DOCX 辅助和表格算术等已存在未提交修改；本轮保留。
- VS Code 原有设置中用户移除了 `julia.environmentPath`，未恢复该项。
- 编辑器初查无活动/可见文本编辑器；中途 VS Code 实例重启，重新定位当前实例。
- Bridge 沿用已存在的工作区实验；其健康状态为 partial，未执行接受、恢复或结束实验。
  原生设置流程启用了 Bridge 实验和编辑可见性；没有发起 Git 工作树迁移。

## 实际交付

1. [复现计划](../../src/reproduction-plan.md)：R0–R10，按各章条件分支推进。
2. [验收协议](../../src/reproduction-acceptance.md)：A0–A6、预先声明的数值门槛、
   运行产物、预算、停止规则、23 类科学图；明确未开始的研究状态。
3. [技术设计](../../src/julia-design.md)：作者工具核查、JuMP/MOI 与求解器选型、
   数据统计及作图、算法自实现边界、拟定模块和运行接口。
4. 可选 `tools/solvers/Project.toml`、Manifest、说明；新增 Julia 恢复与能力检查脚本。
   根包、原有文档及格式工具环境的依赖未改变。
5. 三个原生 VS Code 任务：solver bootstrap、solver check、thesis arithmetic。
6. 更新阅读入口、质量与目录规则、工具链、手册、当前状态和 ADR-002。

## 原文与工具核对

- PDF 60 / 印刷 43 的表 3-7：NM-CHPD 是文献 [36] 的模型对照，
  表注为 Gurobi NonConvex 直接求双线性问题，不能解释成 Nelder–Mead。
- 作者算例报告 MATLAB / Gurobi 10.0.1；第 5 章报告 k-means 与样本外蒙特卡洛。
  未找到足以声明 YALMIP 为作者依赖的证据。
- 工具能力依据官方 JuMP、求解器与 Julia 包文档；链接集中在技术设计，避免重复维护。
- JuMP/Gurobi 已在本项目预检。HiGHS、Clarabel、Ipopt、CairoMakie 等属于已选定待接入，
  其余候选包并未全部安装或宣称通过本项目测试。

## 验证证据

| 检查 | 本轮结果与边界 |
| --- | --- |
| 可选环境恢复 | Julia Pkg 成功生成独立锁文件；首次受限进程解包发生 EBADF，正常权限重试成功 |
| 求解器能力 | 最终格式化脚本 8/8 通过；非论文科学实验 |
| 真实版本 | Julia 1.12.6、JuMP 1.31.2、Gurobi.jl 1.9.3、JLL 引擎 13.0.3；系统 CLI 13.0.2 |
| LP/对偶 | 目标 2、平衡对偶 2 |
| SOCP/对偶 | 目标约 5、固定变量等式对偶约 0.6000002 |
| 非凸二次 | 最大目标 1，上界约 1.0000006984 |
| 其他例 | MILP、MISOCP、非线性接口、不可行状态、2101 变量例通过 |
| VS Code 任务 | 3 项已被原生任务服务识别；thesis arithmetic 实际执行，退出码 0；另两项脚本经 Julia CLI 验证，未声称全部由 IDE 执行 |
| JuliaFormatter | 新增 Julia 脚本完成格式化，格式检查通过 |
| 最终项目/文档检查 | CodeGroup/索引 Sync、项目 Check、严格 Documenter 构建、JuliaFormatter、git diff --check 均通过 |

最终能力报告保存在本地忽略的 `tmp/solver-checks/qualification-zWpupU/report.toml`。
Manifest SHA-256：`057c96acb8b5806c11e4a2d4ac4dde25344abcbcd217c685351e421a4b4d8406`；
检查脚本 SHA-256：`eac56ce432dd0afa9b4c3bcc89594e5d1d5b4b8f218431c5e8d2bf7b41279be5`。
未将许可 ID、凭据、原始许可日志或机器绝对路径写入公开资料。

## 钩子与收尾

当前会话本轮真实 SessionStart（resume）及 UserPromptSubmit 已留下本地记录，
时间分别为 2026-09-16T02:01:01Z 与 02:01:03Z。
可据真实基线执行 Review；本轮最终 Stop 事件尚未发生，不预填成功。
本地钩子状态不提交；先前审读任务缺少原生基线的记录不追改。

最终已执行导航同步、项目 Check、JuliaFormatter 和 `git diff --check`，均通过。
Documenter 在 `warnonly=false`、`doctest=true`、`checkdocs=:all` 下构建成功。
暂存区为空，HEAD 保持起始提交；根科学代码、测试及三个既有环境锁文件没有本轮修改。
Review 在全部文档收尾后依据真实基线登记；成功与否以本地维护凭据为准，不用本文替代凭据。

## 断点

下一实施批次从 R0 的第 2/3 章方程、初始历史与输入缺口开始，
随后做 R1 一个可手查微型例。Q01/Q02/Q05/Q06/Q07/Q10 等仍按台账阻断对应正式结论。
不凭工具安装或规划文档把任何论文模型阶段标为通过。
