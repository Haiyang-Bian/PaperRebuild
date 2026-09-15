# 基础验收记录

日期：2026-09-16。状态：工程与公开发布已验证；原生钩子生命周期验收仍待实际任务触发。

- Julia 1.12.6：三个环境恢复成功，包测试 3/3，JuliaFormatter 检查通过。
- 项目结构及导航检查通过；PowerShell 7 与 Windows PowerShell 5.1 各 51 项维护断言通过。
- 断言覆盖人工分组、别名、UI 状态、增删文件、非法路径/JSON、原子写冲突、会话隔离、
  用户已有改动、计划模式、同轮提交、过期审阅和单次续做。
- Documenter 严格构建及 doctest 通过；浏览器检查了首页、工具链导航及中文排版。
- 基础提交 `73a9649` 的真实干净克隆：没有 PDF/DOCX，三个环境恢复、Julia 测试、严格文档构建和结构检查通过，工作区无变化。
- 公开文件扫描通过；PDF/DOCX 哈希及大小未改变，原件不在提交候选中。
- [公开仓库](https://github.com/Haiyang-Bian/PaperRebuild) 已建立，保留 `master` 和原始提交历史。
- 首轮 CI `35000434485` 暴露 Linux 隐藏文件读取和 PowerShell 测试退出码问题；已修复。
- [CI 35001347872](https://github.com/Haiyang-Bian/PaperRebuild/actions/runs/35001347872) 的 Windows、Ubuntu、严格文档构建及 Pages 部署全部成功。
  部署环境最初自动限定 `main`，已改为既定的 `master`，保留分支限制后重跑部署通过。
- [公开手册](https://haiyang-bian.github.io/PaperRebuild/) 已在浏览器验证正常展示首页与导航。
- Juliaup 精确通道 `1.12.6` 已注册；通过该入口执行骨架示例成功，全局默认仍为原来的 `1.13~x64`。
- VS Code Bridge 确认 settings、launch、tasks 均存在，9 个 `PaperRebuild:` 任务被 IDE 正常识别；未将配置识别等同于所有调试场景已运行。
- 可选文献工具采用 pypdf 6.10.0、pypdfium2 5.13.0、Pillow 12.3.0，已完成单页渲染烟雾测试；未进行新一轮论文阅读。
- Codex 0.153.0 原生 `/hooks` 界面及 `hooks/list` 协议确认三个项目定义均 `enabled=true`、`trust=trusted`，未绕过信任检查。
- 原生启动界面与只读上下文诊断未提供真实生命周期执行凭据，不将它们记为触发通过。
  首次实际任务触发后，检查 `.codex/.local/maintenance/startup-*.json` 及对应轮次基线、Stop 状态。
  该步骤仍待原生会话验收；fixture 已覆盖处理逻辑及启动凭据。

本地 Julia 使用项目独立 depot，未修改全局默认版本。
沙箱内 Julia 管道与 File.Replace 受限，相同检查已在普通用户环境通过，未放宽实现。

本记录说明工程基础，不构成论文复现完成证据。
