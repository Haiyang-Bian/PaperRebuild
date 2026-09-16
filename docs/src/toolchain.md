# 工具链与日常命令

## 安装与恢复

需要 Git、Juliaup、VS Code、Codex，以及 PowerShell 7。
Windows PowerShell 5.1 也支持维护脚本，可将下文 `pwsh` 换成 `powershell`。
从仓库根目录运行命令；VS Code 用“打开文件夹”打开整个仓库。
若 Windows PowerShell 提示禁止执行脚本，可使用已配置的 VS Code 任务，或在该次命令中添加
`-ExecutionPolicy Bypass`（放在 `-File` 前），无需修改全局执行策略。

如果尚未安装，先按官方说明完成下列准备，再重新打开终端：

| 工具 | 官方安装入口 | 安装后检查 |
| --- | --- | --- |
| Git | [Git for Windows](https://git-scm.com/install/windows) | `git --version` |
| Juliaup | [Julia 官方版本管理器](https://github.com/JuliaLang/juliaup#installation) | `juliaup --version` |
| VS Code | [Windows 安装说明](https://code.visualstudio.com/docs/setup/windows) | 能打开项目文件夹 |
| PowerShell 7 | [Microsoft 安装说明](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) | `pwsh --version` |
| Codex | [官方快速开始](https://learn.chatgpt.com/docs/quickstart) | 完成登录并打开本项目 |

```powershell
git clone https://github.com/Haiyang-Bian/PaperRebuild.git
cd PaperRebuild
juliaup add 1.12.6
julia +1.12.6 --startup-file=no --project=. scripts/bootstrap.jl
```

Juliaup 管理安装版本；`+1.12.6` 为本次命令选择版本，不修改全局默认。
`--project` 选择依赖环境，`--startup-file=no` 避免个人启动脚本影响运行。
首次下载和预编译可能较慢，以退出码 0 和完成信息为准。

三个基础环境：根目录供科学代码，`docs/` 供 Documenter 和预览，`tools/` 供 JuliaFormatter。
另有可选 `tools/solvers/` 用于 JuMP/Gurobi 能力预检，不随普通 bootstrap 安装。
Project 描述直接依赖，Manifest 锁定实际版本。恢复使用 instantiate；
不要随手 update 或手动修改 Manifest。包路径依赖为相对路径，整个仓库须一起克隆。

## 常用命令

| 目的 | 根目录命令 |
| --- | --- |
| 包测试 | `julia +1.12.6 --startup-file=no --project=. scripts/test.jl` |
| 工具链示例 | `julia +1.12.6 --startup-file=no --project=. scripts/smoke.jl` |
| 论文表值算术核对 | `julia +1.12.6 --startup-file=no --project=. scripts/audit_thesis_tables.jl` |
| 恢复可选求解器预检环境 | `julia +1.12.6 --startup-file=no --project=tools/solvers scripts/bootstrap_solvers.jl` |
| 求解器能力预检 | `julia +1.12.6 --startup-file=no --project=tools/solvers scripts/check_solvers.jl` |
| Julia 格式检查 | `julia +1.12.6 --startup-file=no --project=tools scripts/format.jl` |
| 应用格式 | 上一命令末尾增加 `--fix`，随后检查 diff |
| 项目结构与导航检查 | `pwsh -NoProfile -File scripts/maintain.ps1 -Action Check` |
| 同步导航 | `pwsh -NoProfile -File scripts/maintain.ps1 -Action Sync` |
| 维护脚本测试 | `pwsh -NoProfile -File test/maintenance.tests.ps1` |
| 严格构建文档 | `julia +1.12.6 --startup-file=no --project=docs docs/make.jl` |
| 本地预览 | `julia +1.12.6 --startup-file=no --project=docs scripts/preview.jl` |

默认预览地址为 <http://127.0.0.1:8000>；端口占用时 LiveServer 选择下一个可用端口，
以终端显示的地址为准。Ctrl+C 停止，修改文档后重启预览重新构建。
正文默认使用侧栏之外的全部可用宽度，小屏侧栏收起；长公式可在公式区域横向滚动。
模型原式居中并显示论文式号，API 页面由 Julia docstring 生成可折叠卡片。
直接双击 HTML 不能可靠浏览采用目录 URL 的页面。生成网站位于 `docs/build/`。

## VS Code 与 CodeGroup

接受工作区推荐的 Julia、Codex、CodeGroup、EditorConfig、Markdownlint 扩展。
从“终端 → 运行任务”选择 `PaperRebuild: ...`；调试配置运行骨架示例。
Julia 扩展使用 `+1.12.6` 和工作区环境，测试使用单线程基线。

在资源管理器打开 CodeGroup 文件分组视图。`paperrebuild-` 开头的组由脚本管理：
新增文件后运行 Sync，组内成员重新计算；组名、排序、折叠、固定、文件别名及人工组保留。
自动组中手动删掉的成员下次同步会恢复；长期个人整理请使用人工组。
目录决定文件实际位置，分组仅是导航视图。

新增 `PaperRebuild: solver bootstrap`、`solver check` 和 `thesis arithmetic` 任务。
先运行 solver bootstrap，再运行 solver check；许可不可用时预检失败并保留报告，不能视为跳过后通过。
任务使用工作区相对路径；普通预览/骨架测试不要求 Gurobi。
科研工具的用途、可选项和 Julia 自实现边界见 [Julia 技术设计](julia-design.md)。

## Codex 钩子启用

项目提供 SessionStart、UserPromptSubmit、Stop 命令钩子。
首次在受信任项目启动 Codex CLI 后，通过 `/hooks` 审阅并信任三个项目定义。
定义变更后重新审阅。Check 通过不代表原生钩子已启用。
本地事件证据在忽略的 `.codex/.local/maintenance/`；具体行为见智能体手册。

信任由 Codex 原生机制管理，不手写信任哈希或绕过检查。
参考：[Codex Hooks](https://learn.chatgpt.com/docs/hooks)。

## 文献辅助工具

只有处理本地论文时才需要 Python 3.10 或更新版本：

```powershell
python -m venv .venv
.venv/Scripts/python -m pip install -r scripts/requirements-reading.txt
.venv/Scripts/python scripts/read_thesis.py render --pages 30-32 --rotation 270 --dpi 160
```

Linux 使用 `.venv/bin/python`。每次最多渲染 12 页，输出到忽略的 `tmp/`。
公式密集页每批 1–3 页；DOCX 辅助检索，关键符号与页码回 PDF 核对。
`inspect` 会重写文本层检查清单，仅在重新检查原件时运行并审查差异。

DOCX 索引工具只依赖 Python 标准库，不改写原件：

```powershell
python scripts/read_docx.py index
python scripts/read_docx.py find '备用|交付风险' --limit 20
python scripts/read_docx.py show --start 373 --end 421 --limit 60
```

默认原件路径为 `docs/摘要.docx`，缓存为忽略的 `tmp/docx-thesis/`。
`index` 记录来源哈希；原件变化后重新建立索引，旧块号和阅读记录须重新核对。
每次最多显示 80 个块，块号不对应 PDF 页码。索引不做 OCR，也不能修复缺失的数学符号。
无本地原件时不运行索引；工程检查和表格算术脚本不依赖论文原件。

## 常见问题

R1 建模使用根环境的 JuMP、CSV、Clarabel、HiGHS；图表使用 docs 环境的 CairoMakie/CSV，
Gurobi 本机对照使用 `tools/solvers`。具体命令见 [R1教程](ch02-status.md)。
新增 `R1 mapping check`、`R1 mapping sync`、`R1 tests`、`R1 micro case`、`R1 validate saved`、`R1 redraw` 六个任务。
后两个任务选择最新保存记录并显示其 ID，不会跳过失败记录；也可从终端显式传入运行目录。

- 找不到版本：运行 `juliaup add 1.12.6`，再执行带版本命令。
- 缺少依赖：确认目录及 `--project`，重跑初始化并保留错误输出。
- Sync 并发冲突：重新读取分组文件，确认人工修改后重试，不强制覆盖。
- 没有原件：干净克隆默认如此，工程测试和文档构建不需要原件。
- 钩子未触发：检查信任和事件记录，fixture 只验证脚本行为。

依据：[Documenter](https://documenter.juliadocs.org/stable/man/guide/)、
[Julia 环境管理](https://pkgdocs.julialang.org/v1/environments/)、
[CodeGroup](https://github.com/MiszterSoul/codegroup)。
