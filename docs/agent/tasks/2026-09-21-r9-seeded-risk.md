# R9：原百情景模型的带初值对照

从c27fd55接续。共同见证已在三方案各100原情景通过，初值不等于新优化结果。
本轮先答复研究结论，再按全文active目标继续。个人settings保持，Bridge没有注册实例；只本地提交。

## 事前协议

- 保留r9-reserve-data-20260921-v2全部输入与案例哈希；原3A固定全零舒适开关，3B/C为原MILP。
- 使用共同见证3996193a…，不把它自动回填为新求解器候选；不改任何科学约束、目标或A1/A2。
- 3A原生PStart配Method=0及LPWarmStart=2；3B/C原生Start，原单线程/种子23/容差1e-9保留。
  依据[Gurobi官方warm-start说明](https://docs.gurobi.com/projects/optimizer/en/current/features/warmstart.html)。
- 每项完整600秒，前420秒含读取/建模/初值/优化，独立运输检查到480秒，剩余供原验算和封存。
  这比历史运行增加候选验证预留，因此是初值、LP方法及预算分配的组合对照，不能单独归因为初值加速。
- 小例测试和协议冻结先于正式优化。原完整结果、失败、超时照常保留；训练候选未锁定前不做样本外。
- 保存原变量、原生初值读回、实际候选、界、三运输证书与独立残差摘要；逐情景分文件，避免大文件。
  重读可调用原冻结验证器完整重算；摘要不代替原数值。

## 实施状态

- 共同节点本地提交c27fd553b183d5b643ea9d328ee96fb76d599482。
- 开放专项33项、本机Gurobi原风险LP/MIP对照10项通过。初版保存摘要推断成Float64字典，
  插入嵌套验证字段失败；改为显式异构字典，原开发失败日志tmp/r9-seeded-tests.log保留。
  修正后的完整专项为tmp/r9-seeded-tests-v2.log，未修改模型、验收或冻结科学结果。
- 正式冻结r9-seeded-input-20260921-v1，manifestSHA
  447a0c8f1acf34e6ed4cd82689c1c65412f7eaaf9f91c9eaebe96d75b24a3779。
  其显式依赖原共同输入包，不复制/改写旧数据；存有新求解代码及原字节初值。
- 三方法按冻结顺序各执行一次，结果目录results/runs/r9-seeded-20260921-v1，未追加预算或重抽输入。
  3A完整421.8036秒仍无候选；3B/C分别463.9422/471.7298秒有实际候选，原模型/风险/费用通过。
  最坏费用均396812.219543CNY/日，下界266043.263018，间隙32.9549%；最优性未完成。
  两者费用未改善，备用绝对值最大9.5513e-14MW，最坏舒适事件0，不支持备用价值或方案收益排序。
- 公开原数值r9-seeded-evidence-20260921-v1配对原共同输入和新冻结代码，无results/runs依赖。
  移位重验、字节/状态/假成功篡改拒绝9项通过，日志tmp/r9-seeded-portability.log。
  3B/C重算200原情景、各2187906残差；3A核验负状态，不把打印的通用提示当作有候选。
- 结构只读计数与完整3A的1061074变量/2735895约束相符；1672800条边界行，
  单情景86688存储精确零、42452非零系数。费用在运输行重复1440000项。
  以原生界、精确去零、情景费用辅助等式构成的替代表达尚未实现，不能称已证明超时原因。
- F45v1图例遮挡3C下界，原图与失败审阅保留；v2仅修改布局/判定说明，实际视检通过。
  重绘未求解；图源原值、运行ID、单位与配置全部保存。
- R5–R6与R7–R9隔离回归均退出0，日志分别tmp/r9-seeded-regression-r5-r6.log与
  tmp/r9-seeded-regression-r7-r9.log；未改动的R1–R4沿用紧邻共同见证节点的完整回归。
  最终只读格式通过。新图源检查首轮错用solver_bound字段，原字段为solver_objective_bound，
  已修正检查脚本；科学代码、冻结结果和绘图数值均未改，失败日志tmp/r9-seeded-delivery.log保留。
  修正后549项交付核对通过，tmp/r9-seeded-delivery-v2.log；严格Documenter/doctest退出0，
  tmp/r9-seeded-docs.log。映射tmp/r9-seeded-mapping-final.log和格式tmp/r9-seeded-format-final.log通过。
  导航首次受沙箱保护拒绝写本地锁，未更改导航；以原脚本权限流程继续，Sync实际退出0，
  tmp/r9-seeded-sync-approved.log。导航保留17047原成员与人工元数据，新增263；
  tmp/r9-seeded-navigation.log。
- 同步后严格构建发现generated-inventory为200.41KiB，超原200KiB门槛，失败日志
  tmp/r9-seeded-docs-final.log保留。人类索引按批次根目录汇总，CodeGroup完整成员和文件本身不改。
  `Inventory-Text`仅调整一层归组；专项检查覆盖根表/嵌套图源去重和普通源码/公共样式保留。
  PowerShell 7与5.1专项各6项通过；5.1首次被本机脚本执行策略阻止，改用已有测试的进程级执行参数，
  不修改全局策略。针对性重生成使用权威生成器、原锁和原子写入，实际退出0，
  tmp/r9-seeded-inventory-rebuild.log；只改变人类索引，CodeGroup保持。原Markdown134362字节降至55941。
  最终严格文档/doctest退出0，tmp/r9-seeded-docs-final-v2.log；索引HTML为102.17KiB。
  导航末次核对仍保留17047原成员/人工元数据，新增263，个人settings哈希不变。
  首轮暂存280文件/814检查通过，生成的来源状态页随后一并纳入本节点；
  完整暂存281文件/816检查通过，tmp/r9-seeded-staged-v2.log。个人设置未纳入。
  最终Project Check实际退出0，日志tmp/r9-seeded-project-check.log记录Project checks passed；
  核对收尾记录后保存本地提交，不推送、不合并。全文目标继续active。
