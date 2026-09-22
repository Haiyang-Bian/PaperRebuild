# R9：同模型紧凑表示与受控比较

## 开始状态

- 从本地e27f6e1继续全文目标；不推送、不合并，个人`.vscode/settings.json`保留。
- 用户询问本轮意义与后续：3B/C有合格百情景候选但与共同初值同费用、备用近零；
  3A无候选，原风险最优性和样本外结论未完成。先做有限的等价表示对照，第7.5节可以独立推进。
- 实时VS Code Bridge查询没有注册实例；不能据此断言编辑器中没有未保存内容。

## 采用规则

- r9_compact_v1：仅原生声明边界、精确去零、自由费用变量等式。
- 保留原案例、100支持、风险/交付规则、求解器方法、初值和600秒预算；旧接口默认原表示。
- 原逐行和目标消元核查、双向点映射、原验证器及LP/MIP原生初值检查先于正式比较。
- 规模对照方案已写入configs/r9/compact-study.toml；结果未运行，不宣称加速。

## 实际验证

- 84项数学/集成检查通过，覆盖原约束/目标、双向可行点、原验证器、存档和失败传播。
- 本机原生LP/MIP与实际日志16项通过。首版Windows临时日志清理警告保留；
  新版在项目tmp保留独立日志，再次16项通过且无警告。
- 冻结兼容30项通过；当前代码/冻结协议17项通过，旧带初值证据549项通过，公式映射通过。
- 修正新增求解器函数变量名与赋值符之间的解析歧义，尚未执行的草稿不计作科学失败运行。
- 首次导航同步被沙箱拒绝写入维护锁，未修改分组；按授权在提升环境通过既有脚本重试，保留原日志。
- 严格文档首轮遗漏内部日志函数API卡片；补齐原生卡片，保持checkdocs门槛，v2严格构建/doctest退出0。
- R7–R9隔离回归和只读格式实际退出0；R1–R6未修改科研实现，沿用紧邻节点回归通过记录。
- 导航Sync/保留核对/Project Check顺序脚本实际退出0；日志分别为
  tmp/r9-compact-sync-v2.log、tmp/r9-compact-navigation.log和tmp/r9-compact-project-check.log。
  保留tmp/r9-compact-groups-before.json基线；17310个原成员与人工元数据保持，新增25。
  同步后的最终严格Documenter/doctest也退出0，日志tmp/r9-compact-docs-final.log。

## 冻结输入与下一步

- r9-compact-input-20260921-v1，manifest SHA256
  b3473ac124c64b7fef5789ef4638e3bf2a15ea11cfa0d30f5e0e2829acebe609。
- 与原seeded协议相比只增加等价表示与有效日志观测，原三案例和共同初值哈希相同。
- 正式百情景对照尚未运行，无新的费用或加速证据。完成本节点检查后仅执行已声明的一轮；
  继续受限则以阶段数据决定后续，不原样无限重跑。第7.5节按独立输入推进。
- 收尾范围在tmp/r9-compact-stage-allow.txt，暂存核查入口tmp/check-r9-compact-staged.jl；
  项目检查真正退出0后执行；父提交e27f6e1，个人settings哈希保持，不推送。

规模对照只在上述检查完成后启动，使用冻结脚本：

```sh
julia +1.12.6 --startup-file=no --project=. results/summaries/r9-compact-input-20260921-v1/implementation/scripts/run_r9_seeded_batch.jl results/summaries/r9-common-input-20260921-v2 results/summaries/r9-compact-input-20260921-v1 results/runs/r9-compact-20260921-v1
```
