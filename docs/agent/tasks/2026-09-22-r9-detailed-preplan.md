# 第7.5节：详细恢复相容性接回灾前计划

从8146c46继续，上一目标轮为实质进展：六项故障证据封存、温区反例和开发预检。
当前仅个人settings为已有改动；VS Code Bridge无注册实例。全文目标仍active，不推送、不合并。

## 采用范围

- 保留原平均正常模型和聚合灾前版本；新r9_prescribed_detailed_preplan_v1显式复用R7-L1/L2/L3。
  灾后逐故障详细热块共用灾前完整历史、CHP承诺/出力及电池初态；不是任意给定有利初态。
- 原6-70/71支持状态继承，详细时空温区属于项目采用条件，不能冒称作者原近似式自动包含。
- R9-DH1必要预检来自温度顺序保持；通过不证明完整调度。R9-DP1–DP3记录详细模型与费用作用域。
- 原图7-12替代输入及三个故障、流量、容量、负荷、价格和2 MWh门槛不变。
  正常/恢复流量仍给定，其他流量域及完整故障覆盖尚未完成。

## 实施与验证

- 新增core/formulations/verification/algorithms/reporting的r9_detailed_preplan文件，原R9接口保持。
  求解阶段为验证预留预算；版本、费用、罚费、模型类型和原始状态分别记录。
- 第一轮专项tmp/r9-detailed-tests-v1.log退出0，81项通过；原值在日志所指隔离目录。
  覆盖经济退化、按事件取最大而非求和、详细存在性见证、历史篡改、目标混用、零预算、缺许可和移位回放。
  之后补充求解器版本字段及从进程导入前计时的实验入口，后续实际验证另记。
- 同输入协议configs/r9/detailed-preplan-study.toml已在求解前冻结。主预算从Gurobi导入前开始，
  主阶段至360秒，三项独立恢复至540秒，整个方法600秒；求解内部另为验证预留部分预算。

## 正式证据与结果

- 温区包results/summaries/r9-handoff-evidence-20260922-v1保存原4B/原开机候选、IIS及新必要核。
  tmp/r9-handoff-evidence-freeze-v1.log实际退出0，68项哈希、冻结源码移位数值回放通过，
  临时重放tmp/r9-handoff-replay-I7QMlh/relocated；不重新运行优化器或IIS。
  正常平均343.15 K，子步/空间最低343.06151011413453 K，缺口0.08848988586544237 K。
  最高入口仍不能改变该首时段出口；原状态零必要冲突、开机状态八条。粗化时间不能移除空间冲突。
- 新输入results/summaries/r9-detailed-preplan-input-20260922-v1，清单SHA256
  10f9a4a8362eae11426a8fef1ce85b4576250bb3010f8ab62f37dae1b5217258。
  tmp/r9-detailed-input-freeze-v1.log退出0；原父清单/物理输入及所有执行源码随包保存。
- 罚费原值results/runs/r9-detailed-preplan-20260922-v1/penalty，
  tmp/r9-detailed-penalty-v1.log退出0；完整方法179.635999917984秒。
  正常费用498199.1064435785、罚费105521.90617756327、总目标603721.0126211417 CNY。
  上下界一致且采用模型通过。三个独立详细恢复均solver_optimal、模型/必要温区/A2通过；
  关键失供为10.141924515983817、10.437325808244783、10.552190617756324 MWh。
  三个故障都不满足2 MWh门槛。
- 门槛原值同根threshold，tmp/r9-detailed-threshold-v1.log退出0，
  完整方法82.68700003623962秒，原生DualReductions=0下INFEASIBLE；不替换旧原式状态。
  主阶段infeasible_certified，三恢复primary_candidate_unavailable且attempted=false；缺失值不写零。
- 新证据results/summaries/r9-detailed-preplan-evidence-20260922-v1的168项文件哈希及冻结源码移位重验通过，
  tmp/r9-detailed-evidence-freeze-v1.log实际退出0，临时回放tmp/r9-detailed-replay-wsaEyS。
  summary.csv八行区分目标单位和未执行状态；comparison.csv三行与原4B同详细评价配对。
  主问题行handoff_necessary_pass=false为该单独预检未执行，三详细恢复行才是该检查结果。
- 新最坏比原4B同口径10.682203848858865 MWh减少0.13001323110254148 MWh，
  正常费用增加715.508569742 CNY/日；其他两故障分别增加0.62048339239408、0.020354561153288486 MWh。
  不能称所有故障改善，不将费用加罚费最优解的失供当作失供最小值下界。

## 图表与工程收尾

- F49初版位于docs/src/assets/r9-handoff-v1，原值/source.csv/plot-source.jl/配置/哈希一起保存。
  tmp/r9-handoff-plot-v1.log保留首次失败：图层间接引入JuMP而文档环境未直接依赖该包。
  改为纯TOML/SHA对象读取，未增加优化依赖；v2日志退出0，已实际视检无裁切。
  图描绘旧状态反例，不是新详细方案的轨迹；精确低温差在正文与图源明确。
- 受影响R7–R9完整隔离回归tmp/r9-detailed-regression-v1.log实际退出0，末行tests passed。
  原R1–R6未修改，本次不因例行收尾重复运行全部无关实验。
- 新增只读交付入口scripts/check_r9_detailed_artifacts.jl，覆盖封存哈希、尺寸、负状态、图源及篡改拒绝。
  第一轮967通过/2失败：图清单写入时纳入了空清单自身；CSV的显式空字符串不等于missing。
  保留v1图，修正先哈希后开文件，生成docs/src/assets/r9-handoff-v2；读CSV按原空字符串核验，不修改原表。
  tmp/r9-handoff-plot-v3.log退出0；v1/v2的source.csv及PNG哈希完全相同，原视觉检查仍适用。
  交付v2为966项通过，tmp/r9-detailed-artifacts-v2.log实际退出0；原失败日志保留。
  最后加强篡改检查：完整副本先通过，再只改summary.csv触发拒绝，排除缺文件带来的混淆。
  tmp/r9-detailed-artifacts-v3.log实际退出0，967项通过；最后只读格式v3也退出0。
- 公式/API映射26项、最终只读格式通过，日志tmp/r9-detailed-mapping-v1.log及r9-detailed-format-final-v2.log。
  导航Sync实际退出0，tmp/r9-detailed-sync-v1.log；独立核验保留18587个原成员/人工元数据，新增339。
  严格Documenter/doctest实际退出0，tmp/r9-detailed-docs-v1.log；仅保留已有体积提醒，公式/API/图表链接无构建错误。
  最终项目检查原进程实际退出0，tmp/r9-detailed-project-check-v1.log记录Project checks passed。
  长时间无日志期间保持等待原进程，没有将静默当失败或重复启动。
  实际350文件暂存范围、冻结Git原字节及个人settings核验1025项通过；最终日志更新再核对暂存差异。

## 下一节点

最坏10.319838 MWh电力失供的网络/端口原因仍需单独提取证据，不能用热冲突替代。
先读已保存故障的设备出力/电力分区/可达容量，形成必要供能界，再决定哪个模型边界需要有依据的对照。
本节点不扩大故障全集或自由流量域，不宣称第7.5节或全文完成。

### 接续只读开发线索（尚未封存）

- tmp/audit-r9-worst-values.jl从已存aggregate-author_event1读取控制与节点削减，v2日志退出0。
  线路12/26/28/30/46/47曾达到容量，节点7/8/15/22电压曾到边界；活跃本身不证明原因。
- tmp/audit-r9-electric-cut.jl在全部健康线路双向可用、CHP不受启停、忽略热/电压/无功等乐观域计算最大流。
  初版在记录写入处有括号错误；修正后tmp/r9-electric-cut-v2.log退出0，解析小例通过。
  这只是必要下界，未用原最优拓扑锁死其他可行控制，也未运行优化器或改父计划。
- tmp/check-r9-electric-cut-certificate.jl独立按节点守恒累加，9项通过，
  tmp/r9-electric-cut-certificate-v1.log退出0。缺电区域
  [1,2,3,4,5,6,13,14,15,16,17,18,19,27,38,39,40,41,42,43,44]没有内部发电，恢复外网交换为零。
  三条健康边界线30(26–27)/35(35–38)/47(19–33)容量为2.562235688729875/0.843485688729875/2.562235688729875 MW，
  合计5.9679570661896255 MW；四小时关键需求8.020833333333332/7.7/7.21875/6.978125 MW。
  必要关键失供下界6.045880068574829 MWh，已超过2 MWh，但仍低于原最坏10.319838 MWh。
  原输入和故障哈希写入tmp/r9-electric-cut-v2.toml，正式封存、原式/参数来源和更完整解释留下一节点。
  可以初步排除只增加区域外CHP发电就满足2 MWh的解释；不扩大为作者同输入结论。
- 已只读追溯src/core/r9_resilience.jl与原configs/r9/resilience-protocol.toml：
  原树容量按正常绝对负荷/接入设备包络乘1.5生成；联络线容量取原树连接路径的最小容量，阻抗取路径和。
  这是预先冻结的项目替代规则，不是作者公开的线路额定值。必要下界解释本替代系统，不能反证作者原算例。
  后续若研究容量影响，应使用事先声明的独立敏感性协议；不反向调参使失供恰好降到2 MWh。

保留负结果及原始状态；不按收益改参数、放宽A1/A2或宣称全文完成。
