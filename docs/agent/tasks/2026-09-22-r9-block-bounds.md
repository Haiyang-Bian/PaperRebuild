# R9连续首块：有限等价表示诊断

2026-09-22，从c3d8c2d接续。用户询问本轮意义和下一步；按此前全文active目标继续小范围诊断。
原工作区仅个人.vscode/settings.json，SHA为A70D6C47B0F534D413E3AD85D97503BB0A74C6EAC38FB3A7DDC1FC01CD157D86。
Bridge无注册实例，未修改个人设置；无推送/合并。

## 固定问题与预先规则

- 父批次为r9-distributed-corridor-20260922-v1，清单SHA
  1623bf96b2637084aca0501cbcf5d3b1f6cf366d0fc38d1ef9789f92a8670aea。
- 只诊断actor2第一轮零消息/零乘子、ρ=1；保留输入、模式和原属性。
- 优化前写rules.toml，四项为Clarabel/Gurobi×原相等上下界/显式固定；
  QCPDual=1在Gurobi两项一致，只为原乘子读取。每项求解最多60秒、共同600秒。
- 精确有限相等界才允许转换，1775变量；原有2749变量保持，约束数5116→3341。
  不替换科学模型，不改变旧调用或历史结果，不做完整ADMM重跑。

## 实际过程

- 第一开发脚本导入PaperRebuild.Clarabel失败，尚未启动优化；tmp/r9-bound-representation-v1.log保留。
  修正独立环境导入，继续同四项规则，新目录tmp/r9-bound-representation-v2。
- 28073实际退出0，四项内部27.094352秒。Clarabel两项ALMOST_OPTIMAL，Gurobi两项OPTIMAL。
  逐行等价检查与独立数字系数回放不依赖优化器。各状态/原始乘子/报告目标均原样保存。
- Clarabel原/固定目标6.066472498235/6.066472497910；Gurobi两项6.066473527488，均为无量纲增广目标。
  Gurobi原乘子的对偶/互补/驻点指标2.614e-5/1.288e-3/1.180e-4；目标报告差5.542e-8。
  诊断不生成全局下界，不把原生OPTIMAL当作KKT已通过，不因Clarabel残差较小升级原状态。
- 原文件及完整模型快照封存results/summaries/r9-bound-diagnostic-20260922-v1。
  39727实际退出0，四项数值重读与精确等价证明通过，约10.8MB原值。
  脚本scripts/r9_block_bound_evidence.jl和test_r9_block_bound_evidence.jl仅使用标准库。
- 解析QP符号、平方/交叉项导数、旋转锥、缺失乘子与精确等价测试通过。
  20332实际退出0：13解析+4等价+4原包/换目录/篡改共21项，日志tmp/r9-bound-evidence-tests-v2.log。
  只读格式、严格文档/导航及最终项目检查等待实际终态后追加。
- R9-DB1及作用域独立的变量/固定界已登记，22项映射实际退出0；不改原5个ADMM关系。
  导航Sync 44394仍在运行，日志tmp/r9-bound-navigation-v1.log。同步前快照为
  tmp/r9-bound-file-groups-before.json，个人settings哈希见上。不要重复启动已在运行的Sync。
  同步后做保留性、最终格式、严格文档、项目Check及明确范围本地提交；本段不提前报通过。

## 接续收尾

- 原Sync 44394实际退出0，tmp/r9-bound-navigation-v1.log记录Navigation synchronized。
  20430原成员、原顺序/人工元数据/个人settings保持，新增37，见navigation-preservation-v1.log。
- 最终只读格式退出0；严格Documenter/doctest 88764实际退出0，仅页面/索引体积警告，未改变门槛。
  日志tmp/r9-bound-docs-final-v1.log。模型src/锁文件和原数值未变。
- 最终项目Check 84713实际退出0，tmp/r9-bound-project-check-final-v1.log记录Project checks passed。
  50文件明确暂存范围与冻结Git原字节139项通过；本节点按该范围保存本地进度。
  个人settings保持原哈希且未暂存；无科研重跑、推送或合并。
- 本轮继续准备R10要求—证据审计：原总计划、A0–A6和F01–F23均保留；
  早期状态说明仅属历史，不能作为当前缺失判断。PDF1/2为重复摘要、145/146为总结/展望；
  原文题名/作者/年份尚未从这些页面取得，不把CamScanner元数据当作者。
  原四页只读渲染和SHA已核对；首次Julia沙盒pipe EBADF日志保留，正常授权v2退出0。

## 研究结论与后续

这项改写不足以解决原失败，未排除其它表示影响或查清求解器内部误差成因。
不把四项开发诊断计为规模分布成功；此前240/238轮未通过的判断保持。
剩余完整子块精度与运行开销保留有预算专题，同时推进R10主张—证据—可复核范围及干净克隆教程。
