# R6结果报告与UTF-8哈希续接

## 状态与问题定位

上轮为verified wait：训练句柄74032确认存活，未因观察超时重启。当前轮继续核验，
发现SP结果已于13:36:30 UTC封存，实际求解/验算elapsed_sec为27.426，目标−86.63050174668956。
训练摘要和策略尚未生成，不能把缺少END日志写成优化仍在运行或优化超时。
SP原始结果44,945,513字节，SHA为7d7c87920437af71486f21ce89dba75707604a0b0951ef219479af82d0550392。

独立只读探针tmp/r6_read_probe.jl及tmp/r6_policy_stages.jl定位到
r6_policy_from_training计算parent_result_sha256时的字符串SHA-256入口。
读取约0.07秒，解析约1.5秒，输入构造约8.5秒，验算约12.3–12.9秒；
验算文本各约18–19秒、完整结果序列化约1.43秒，父哈希长期未返回。
这些是诊断测量，不是新的算法速度对照。

tmp/r6_hash_probe.jl对同一UTF-8数据验证字符串、字节向量、IOBuffer摘要一致。
65,544/262,152/1,048,584字节的字符串入口约0.007/0.107/1.807秒，表现为近似平方增长；
1 MiB的字节向量/IOBuffer约0.003/0.002秒。44.9 MB原文件的字节哈希约0.163秒，
与原保存值一致。证据tmp/r6-hash-probe.log。
本机Julia 1.12.6 SHA字符串入口转CodeUnits，并按64字节块copyto!；
通用copyto!使用unalias/mightalias，CodeUnits使用通用dataids(objectid)。
实测性能问题已确认；底层别名检查的具体成本是代码推断，不冒称已由采样剖析逐帧证明。
可重复执行的最小探针已整理为scripts/diagnose_r6_digest.jl；不修改Julia标准库或全局方法。

核对PID、启动时间、Julia路径及封存SP哈希后，结束本任务的训练/两个只读探针进程。
首次沙箱Stop-Process访问拒绝，提升权限后成功；三个原句柄均返回终止exit=1。
日志tmp/r6-hash-process-stop-elevated.log；不是观察超时重跑，也不是模型不可行。
原始批次D/SP、输入、日志与源码保留。

## 修复与续接契约

科学源码仅将parent_result_sha256的SHA输入从String改为同一文本的IOBuffer。
没有改变序列化、字节、SHA算法、模型、求解器、预算、阈值或选参。
scripts/continue_r6_study.jl要求新旧归档逐文件仅此一处字面替换，且14输入、数据、规则完全一致。
旧运行完整复制并逐文件核对；既有D摘要/策略须逐值相同，SP从原值完成独立验算后提取策略。
新批次另存continuation.toml及两版冻结来源，不覆盖原批次、不重新优化已有D/SP。
尚未执行的配置继续原预算。正式续接结果在执行后追加，不能由接口存在认定完成。

## 报告入口

新增r6_study_tables/report_r6_study，训练目标、验证选择、测试均费和压力单列。
缺失训练、未知日、非完整费用显式保存；完整测试分组方生成同日配对，缺失不删样本。
21项表格测试已通过，包含未知分母、费用口径、缺失配对和5001行分块无丢失。
哈希专项29项、来源续接专项5项通过，共55项；格式、公式映射与严格Documenter/doctest通过。
完整R1–R6回归已全部通过exit=0，新增55项随完整回归通过；最小探针复跑确认44.9 MB流式摘要约0.138秒。
日志分别为r6-hash-io-tests、r6-continuation-tests、
r6-report-hash-format-check、r6-report-hash-mapping、r6-report-hash-docs及r6-report-hash-regression。
最终严格构建r6-report-hash-docs-final通过，只有既有页面/搜索索引大小警告；未提高门槛。
导航Sync及项目Check通过；无原生钩子基线，不伪造Review。个人settings哈希保持不变。
首份仅D的进度报告在results/runs/r6-formal-progress-20260919-v1，明确partial_progress_only。
该首份生成后报告检查器增加范围声明核验，旧报告保留，不冒称它可由新报告源码原样通过版本检查。
独立公开见证与F17–F19仍待正式结果；本接口的数值重验要求原始批次和冻结科学源码。

VS Code Bridge实际查询无已注册实例；保留个人settings的A70D6C47…157D86哈希。
继续codex/r2-models，仅本地提交，不推送。第6/7章、规模和全文交付仍未完成，总目标保持。
