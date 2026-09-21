# 第7.5节：已保存开机候选的逐故障核查

从832a9f8继续；用户询问“这一轮说明什么、接下来做什么”，先核对当前记录，再沿既有全文目标
执行已准备的独立故障评价。个人settings保持，VS Code Bridge无注册实例；本地提交、不推送。

## 原值与协议

- 使用r9-preplan-input-20260922-v1；manifest SHA保持
  79db356c697a60bfec6c25e0874f71e5f070397191a1e4ce400acb1fa2951933。
- 父候选为r9-preplan-loss-diagnostic-20260922-v1/penalty_with_CHP1_event_on.toml。
  父计划原值、正常费用503527.775614 CNY/日、启停及完整状态均不变；不进行新灾前优化。
- scripts/r9_preplan_faults.jl在求解前复制输入、父记录和科学源码，按三个故障分别运行聚合/详细恢复。
  整体600秒、恢复截至540秒、每项最多60秒；结果保存后重验源/父哈希。

## 实际结果

- tmp/r9-preplan-faults-v1.log及原值results/runs/r9-preplan-faults-20260922-v1；进程实际退出0。
  总墙钟55.528秒。聚合失供0、9.447932245080498、10.319838401908143 MWh，三项model_pass。
  三项详细恢复均infeasible_certified，无原值候选；不能写成零失供或热网通过。
- 原4B对应聚合7.2555、9.88391793381035、10.319838401908148 MWh。最坏故障保持，其他两项改善。
  重新优化后的灾前出力/热状态同时变化，不是单独启停效应。详细不可行的共同原因待提取约束证据。
- 已向用户解释：提高罚值无法突破既有采用域的数值失供下界；最坏指标不代表所有故障表现；
  聚合关键失供为零不证明普通/热负荷服务，更不证明详细调度可实施。

## 独立验证与收尾

新增scripts/r9_preplan_fault_evidence.jl：先核对输入/基准/父诊断/新阶段哈希，
用各记录的冻结源码重算原正常、事件继承、约束、流量与详细热初态，再生成comparison.csv。
封存包含全部原字节及检查源码；移位重读不调用优化器。实际检查结果如下。

- 封存results/summaries/r9-preplan-faults-20260922-v1成功；全部父计划、继承和12项新旧恢复
  用各自冻结源码重读通过。tmp/r9-preplan-fault-evidence-freeze-v1.log记录实际退出0。
- tmp/r9-preplan-fault-delivery-v1.log实际退出0，1282项通过，包括180文件哈希、移位数值回放、
  缺失状态、篡改拒绝与公开文件边界。解包tmp/r9-preplan-faults-yidhMR；原记录未重写。
  三项新聚合的原6-88精确交换诊断仍失败，不将采用模型通过扩大为原热关系通过。
- tmp/r9-preplan-fault-format.log：全范围只读Julia格式检查退出0。
  本轮未改变src或test模型代码，未重复运行旧模型全回归；新增检查直接覆盖冻结新旧模型原值回放。

下一步主题：固定流详细恢复的继承相容性、最坏故障区域供能/网络限制。
在有限反例上先定位原因，不扩大全故障搜索、不按收益改参数；R9/R10及全文仍未完成。

## 后续开发诊断：正常平均与灾后子时段边界

- 对同一detailed-external_only重建并提取IIS，单次开发预算180秒。
  v1在33.344秒保存INFEASIBLE，但设置TimeLimit后触发JuMP的OptimizeNotCalled；这是诊断脚本错误。
  已检查JuMP源码：通用优化器属性setter设置is_model_dirty。使用MOI后端仅更新预算后，
  两条矛盾约束的解析例六项通过；没有改原模型行、容差或原求解判定。
- v2实际34.818秒，INFEASIBLE/CONFLICT_FOUND；两条冲突行为
  out_S[37,3,1] == 343.06151011413453 和 out_S[37,3,1] >= 343.15。
  原值results/runs/r9-detail-conflict-20260922-v1/v2；原输入/源码哈希检查通过。
  copy_conflict还保留无关整数变量域，不能声称其整份MPS是只有两行的最小文件；上述两行自身足以矛盾。
- tmp/r9-detail-interval-replay.jl独立水团回放六项通过，不用JuMP矩阵。
  管37为37→38，流率0.9563492063492065 kg/s，容积1.1476190476190478 m3。
  3.75分钟子时段四个出口均温为343.3269797717307、343.15、343.06151011413453、343.06151011413453 K；
  入口取全下界/全上界得到相同四数，因20分钟输运时间而未受灾后新入口影响。
  四值平均与原15分钟正常均温均为343.15 K；第三、四子时段低于下界约0.088489886 K。
  正常R7-D-pipe-temperature检查15分钟出口均温，详细R7-T-bound检查各子步平均，两者尺度不同。
- 上述开发证据暂存results/runs/r9-detail-interval-replay-20260922-v1及对应日志；尚未进入正式公开包。
  这解释已存开机候选的一个充分不可行原因；不能解释10.319838 MWh电力最坏失供下限，二者须分开。
  下一节点先封存可移位的单管证据，再采用显式版本将子步兼容条件接回灾前决策；
  原正常候选及旧判定保留，不通过放宽温度下界或舍去子时段来制造通过。

- 接续v2独立回放为七项通过，原值results/runs/r9-detail-interval-replay-20260922-v2。
  粗、细网格在首15分钟边界的空间最低温均为343.06151011413453 K；不能只归因于时间细分。
  正常库存平均边界与详细空间边界也有差别，下一节点须核对并显式统一采用范围。
- 必要温区开发检查tmp/r9_handoff_temperature.jl用允许入口两端回放，不调用优化器。
  第一版测试夹具把NamedTuple传给仅支持Dict的TOML哈希，原脚本/log保留；v2仅修正该类型。
  tmp/r9-handoff-development-v2.log实际退出0，十项通过；原经济状态零冲突，开机状态八条冲突，
  最大0.08848988586544237 K，输入/流量未修改。此必要条件不是完整调度可行性认证。
  该开发接口尚未接入src、公共API或灾前规划，下一节点仍须公式台账、完整测试和证据封存。

- 导航Sync实际退出0，18402原成员与人工元数据保留、新增185；tmp/r9-preplan-fault-group-preservation.log。
- 严格Documenter/doctest实际退出0，tmp/r9-preplan-fault-docs.log保留搜索索引大小警告。
  映射25项通过；最终Project Check原进程实际退出0，tmp/r9-preplan-fault-project-check.log记录Project checks passed。
  原进程未因沉默重启；后续仅补充上述解释和已完成状态，未改变科学源码或冻结输入。
- 补充解释后严格Documenter/doctest再次退出0，tmp/r9-preplan-fault-docs-final.log；
  原有导航页和搜索索引大小警告保留，未改阈值。
- 192项暂存文件的范围、冻结Git字节及个人设置检查570项通过，tmp/r9-preplan-fault-stage.log。
  核验后仅补本段执行记录并再次检查暂存差异；个人settings始终未暂存，不推送。
