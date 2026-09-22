# 第7.5节：区域供能下界与替代容量来源

从f33d4f3继续。上一目标轮完成详细规划、原值封存和本地提交，属于实质进展。
当前仅个人settings为已有改动；Bridge无注册实例。全文目标保持active，不推送、不合并。

## 本节点职责

- 将已发现的三边界线路区域固定为事后分析对象；按节点有功守恒证明必要下界。
  不将开发搜索包装成预注册统计实验，不复用原最优拓扑锁死其他控制。
- 所有健康边界线可双向使用、区域内CHP按额定能力，忽略热/电压/无功/径向性等，是乐观扩域。
  电池额定放电忽略能量限制；PV保留原降额及情景可用量。R7恢复PCC交换固定零，不能迁入允许购电的模型。
- 逐时需求/上界用保存Float64的精确有理数积分，下界向下转为浮点数；不放宽A1/A2。
- 已核对R9-D01明确缺少原逐线路容量；原树包络×1.5及联络路径最小容量为项目冻结规则。
  新协议configs/r9/electric-cut-study.toml固定区域、同三个故障和作用域；不修改原数据或优化运行。

## 验证安排

手算、独立有功网络LP、故障/方向/源容量/储能/概率/时间步和篡改检查；再使用原包冻结源码验证三项父恢复。
封存输入、父运行、公式来源、逐时下界和报告代码，移位重读；图表仅读取已存证书。
实际结果在运行完成后追加。后续完整第7.5节及R9/R10仍按全文覆盖清单推进。

## 实际执行与结果

- `scripts/test_r9_electric_cut.jl`实际退出0，41项通过，日志`tmp/r9-electric-cut-tests-v1.log`。
- `scripts/r9_electric_cut_evidence.jl freeze`实际退出0，原值包`results/summaries/r9-electric-cut-evidence-20260922-v1`，
  37项文件哈希、三个父聚合恢复及换目录数值重验通过，日志`tmp/r9-electric-cut-freeze-v1.log`。
  原事件故障下界6.04588006857483 MWh，父恢复10.319838401908141 MWh；另两故障同区域下界0，原结果不改。
- 全部47线路容量重算最大误差0 MW，来源协议和原输入哈希一致；原逐线数据仍缺失。
  不将容量构造规则称为作者原参数，也不把必要界称为全部最小失供。
- F50由`plot_r9_electric_cut.jl`读取封存数值绘制，实际退出0，日志`tmp/r9-electric-cut-figure-v1.log`。
  `docs/src/assets/r9-electric-cut-v1`同时保存16时段表、三线路表、原脚本、配置和哈希；图片已实际查看，图例/单位/边界/运行ID可读。
- 映射v1失败：测试名`R9-EC1/EC2`省写了第二式前缀，检查器未找到完整`R9-EC2`。
  保留日志`tmp/r9-electric-cut-mapping-v1.log`；将在当前完整回归退出后补齐测试名，不改变模型或测试断言。
- 受影响R7–R9完整隔离回归实际退出0，日志`tmp/r9-electric-cut-regression-v1.log`记录`Testing PaperRebuild tests passed`。
  其后仅将联合测试名称改为完整`R9-EC1 and R9-EC2`，所有断言与科学实现保持。
- 交付检查实际退出0，150项通过，日志`tmp/r9-electric-cut-delivery-v1.log`。
  包含完整临时副本先通过、再单文件篡改拒绝；图源与父原值逐字段一致。
- 导航Sync v1因沙箱禁止写`.codex/.local/maintenance/write.lock`退出，尚未同步；原日志保留。
  使用正常权限申请重新执行维护脚本，不修改锁或钩子信任配置，原导航快照保持。
- 补全测试名后专项仍41项通过；映射v2为11项通过，只读全项目Julia格式通过，日志分别为
  `tmp/r9-electric-cut-tests-v2.log`、`tmp/r9-electric-cut-mapping-v2.log`、`tmp/r9-electric-cut-format-final.log`。
- 当时续接断点：导航Sync v2已获正常权限并启动，确切进程句柄19000，日志`tmp/r9-electric-cut-sync-v2.log`；
  不因沉默重启。原导航快照`tmp/r9-electric-cut-groups-before.json`已保存，退出后用
  `tmp/check-r9-preplan-groups.ps1`核对成员/人工元数据。随后严格Documenter、最终Project Check、暂存原字节核验与本地提交。
  当时尚未进行本节点提交；HEAD为f33d4f3，个人settings的SHA256仍为
  A70D6C47B0F534D413E3AD85D97503BB0A74C6EAC38FB3A7DDC1FC01CD157D86。
- 接续确认Sync v2原进程实际退出0；人工分组/元数据/18926个原成员保持，新增55个，
  日志`tmp/r9-electric-cut-groups-preserved.log`。严格Documenter/doctest原进程实际退出0，
  `tmp/r9-electric-cut-docs-v1.log`保留输出；已有API/清单/搜索索引的体积警告保留，没有改构建门槛。
  最终Project Check独立原进程73713随后实际退出0，日志`tmp/r9-electric-cut-project-check-v1.log`记录`Project checks passed`。
  全部科学脚本、测试断言、封存原值和图源在最终检查期间未改；后续仅补齐本段实际收尾状态。
- 66文件暂存范围及冻结Git原字节199项检查通过，日志`tmp/r9-electric-cut-staged-check-v1.log`。
  实际未暂存差异仅个人settings；按本节点明确范围形成本地提交，提交编号以Git历史核实，不推送或合并。

## 第7.4节接续前的只读核查（不是样本外结果）

`tmp/r9-oos-preflight.jl`只读训练证据原字节，确认3A无候选；3B/C日前购电、上下备用逐位相同，
100个训练z均为0。原值范围和差异保留于`tmp/r9-oos-preflight-v1.log`。
`tmp/r9-oos-operation-audit.jl`进一步使用冻结构建器核对各100情景的物理输入、共同边界、价格、温度域和控制，
两项完整候选均重新通过原模型/风险/费用检查；去除训练案例名称后，全部操作数据相同。
原两项费用优化未完成的状态保留，日志`tmp/r9-oos-operation-audit-v1.log`；无新优化。

下一节点应先冻结3A缺失与两个有效父候选，再按预声明的最近代表舒适分支执行完整日补救。
两父身份保留，只有完整操作哈希相同才共用测试日计算；不能把相同策略重复评价充作独立收益差异。
复用R6的独立连续补救/统计工具，但不借用R6策略出清的USD市场身份，R9保持固定教学价格和CNY。
还需定义逐日预算、存档和未知计数并做解析/保存重读测试；本次不声称样本外评价已完成。

接续训练兼容探针`tmp/r9-oos-training-probe.jl`实际退出0，原值`tmp/r9-oos-training-probe-v1`。
仅使用首个冻结训练代表train_000890，固定原3B成交和价格，科学物理依赖先与冻结源码逐文件核对。
复用R6连续补救核，HiGHS单线程、原始/对偶容差1e-9、求解预算60秒；结果solver_optimal，
model/KKT/cost均通过，构建/求解/独立检查13.151秒。训练证据加载与旧候选重验不计入这项局部耗时，
不能将它称为完整方法速度；没有读取样本外优化结果或调整输入，开发探针不混入正式测试日统计。

## 对用户问题的研究判断

最新详细规划在三个故障均取得采用模型合格调度，但最坏10.552191 MWh仍未达2 MWh；
新区域证书独立说明同容量下至少6.045880 MWh不可避免，单纯调整算法、热控制或外区发电不能消除该硬限制。
继续提升罚值的优先级降低。先完成本节点证据收尾，再推进已冻结训练候选的样本外评价和R10跨章结论，
未完成规模/故障/控制域仍显式保留；不能因此宣布全文复现完成。
