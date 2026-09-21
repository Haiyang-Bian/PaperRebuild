# 第7.5节：可操作开关与规模输入预运行

## 授权与工作区

持续全文目标，沿codex/r2-models从bea8884增量推进。本地提交、不推送、不合并。
个人.vscode/settings.json原差异保持；实时Bridge无注册实例，不据此断言全部编辑器已保存。
本轮上一轮分类为no progress：此前仅回答状态；本轮实际实现开关域并构造规模输入。

## 原页和采用解释

PDF139图7-12已读，300 dpi局部tmp/pdfs/r9-resilience-upright-20260921/pdf-139-switch-detail.png
确认E20–E23白框。采用7基础+4联络开关，原7.3六开关存档不变；RS08明确图示完备性仍未知。
定义R9-RW1及R9-RW2，中文API卡片与协议见ch07-resilience-pilot.md。

## 已完成验证

- tmp/r7-switch-tests-v1.log：fixture的[true,3]在Julia中先提升为整数，且误读残差formula而非id；
  修正fixture/字段后v2为38+4项通过；模型及A1不改。原值tmp/jl_wV6uy9保留。
- tmp/r7-switch-gurobi-v1.log：原生指示对偶与完整故障审计7项通过，tmp/jl_QXELIl。
- tmp/r9-resilience-input-tests-v1.log：179项构造/端口/指数稳态/时钟与同物理输入检查通过。
- tmp/r9-resilience-mapping-v1.log：19项映射通过。
- tmp/r9-resilience-format.log及format-v2.log：明确范围格式通过。
- results/summaries/r9-resilience-input-20260922-v1已冻结；manifest SHA256
  fffce9b17e4cdd58bbd0341bc01a63f353eeb24cabfd939f4af8e2edab38fc4b。
- 首次规模调用在建模/优化前失败：Julia1.12世界年龄下函数内新加载Gurobi绑定不可见。
  tmp/r9-resilience-normal-v1.log保留。顶层加载后Base.invokelatest进入运行，按v2重新冻结，物理输入不改。

## 当前边界

仅固定参考正常流、事件1与三个故障预运行；两套关键分类保留、全集和其余事件未执行。
正常末态free、部分成网与线性电网、理想变压器/无泵辅助功率均须保持声明。
后续记录v2字节对照、规模求解/回放、完整回归、严格文档、导航与最终Project Check。

## 七项运行与独立容量证据

- 输入v2清单f0ba4a138398db2384b98f56b1587ae4ae4cdd4f740015c5b4b5d41f440f7fab。
  v1/v2逐字节对照94项通过，仅运行器变更，物理输入不改。
- normal运行74e43db5-0140-48be-8aa3-645aabf7a397，费用497483.59787383664CNY/日，
  间隙9.049827095321607e-5；模型/费用/管温回放通过，137149项残差，35.224秒。
- 批处理v2日志是编排脚本字符串插值解析失败，未开始任何恢复；修正为显式插值后v3实际退出0。
  raw为results/runs/r9-resilience-pilot-20260922-v2/nodes_figure_7_12，6恢复各35.53–53.62秒。
- 聚合关键失供7.2555、9.88391793381035、10.319838401908148MWh；
  详细9.521441123589586、10.416971247091507、10.682203848858894MWh。
  六项采用模型及各自有效最优性界通过，详细每项共享/逐管分别约16923/108799残差通过。
  所有关键失供均超过2MWh；普通/热失供原值保留，未二级优化，不能解释其排序。
- R9-RW3只读容量证书：CHP1在16步全关、CHP2全开，关键需求51.2875MWh；
  CHP2/GT/PV发电上限分别24/8/12.032MWh，逐时失供下界7.2555MWh。
  15项解析/步长/非法设备/路径检查通过，见tmp/r9-resilience-report-tests-v1.log。

## 封存与图表修订

- 新报告器首次在读取动态模块x时遇Julia1.12 world age；发生于封存前。
  修正新绑定读取后，freeze-v2日志退出0，7项原值、源码和输入封存evidence-v1。
  移位tmp/r9-resilience-replay-BWWjki全部数值、事件继承和图源重算通过，111文件哈希通过。
- F47-v1视觉检查发现纵轴上限2裁掉聚合6-88诊断点。原CSV有失败，未改变原运行。
  精确交换差0.964128059553305/2.0065965985299723/1.632329011766009MW。
  evidence-v2显式输出scope和exact_exchange_check，图v2分别展示adopted与exact_exchange。
  冻结旧报告源码用于旧CSV重验，避免当前报告修订改写旧表结构。
- R7–R9完整隔离回归实际退出0（tmp/r9-resilience-regression.log）；新增开关与规模输入测试均在其中。
  当前未改R1–R6科学代码，其邻近节点回归记录保持。实时Bridge再次返回无注册实例。
  个人settings SHA256仍为A70D6C47B0F534D413E3AD85D97503BB0A74C6EAC38FB3A7DDC1FC01CD157D86。

后续填写v2移位复核、最终图交付、格式/映射/Documenter、CodeGroup和Project Check的实际结果。

## 已完成的报告复核与下一接口审查

- v2移位到tmp/r9-resilience-replay-EwZg75，七项冻结源码数值、完整初态继承和图源逐字节重算通过。
  新报告器重读v1到tmp/r9-resilience-replay-KXe4Os也通过；两者分别使用各自冻结的报告函数。
- tmp/r9-resilience-report-tests-v2.log：容量15、篡改3、保留精确交换失败5项通过。
  F47-v2已实际视检，诊断叉号完整显示；原v1保留。交付检查931项通过，资产复制到docs/src/assets/r9-resilience-pilot-v2。
- 全量Julia只读格式退出0；公式映射22项通过。新冻结目录设-text，分片objects设binary，避免提交改变原哈希。
- 只读接口审查：r8_spec/solve_r8_case已有economic/penalty/threshold和独立恢复评估，
  但r7_flow_planning_spec要求流量界覆盖r7_planning_pairs全部42故障，并显式转为Gauss共同流量域。
  下批不能以三项预运行冒充该全集，也不能静默将当前给定流量精确参考改成另一热近似。
  先冻结相同正常/恢复热解释和所选故障范围，再测建模开销和4A/4B/4C；此处仅审查，尚未实现新规划。
- 导航Sync实际退出0，tmp/r9-resilience-navigation-check.log确认17615原成员与人工元数据保留、新增365。
  严格Documenter/doctest实际退出0（tmp/r9-resilience-docs.log），保留HTML索引/搜索大小的非阻断警告，未改阈值。
  tmp/stage-r9-resilience.jl --check核对381文件/384项通过，个人settings不纳入；Project Check尚在执行。
- 最终Project Check实际退出0，tmp/r9-resilience-project-check.log记录Project checks passed。
  依照明确381文件范围暂存并核对原字节后保存本地提交；不推送、不合并，不改个人settings。

### 下个实施节点的具体约束（计划，未实施）

优先复用build_r7_planning的included子集和同一给定流量正常模型，避免先引入Gauss表示改变比较口径。
第一批子集仍为当前三个冻结故障。须显式记录只纳入三个见证，不能将其可行性或最坏值认证成42故障结果。
4A保持当前正常经济解；4B在该正常费用上加入10000CNY/MWh乘以三个故障关键失供的最大值，
同一事件的多个故障不做简单罚项求和；4C使三个见证各满足2MWh，再最小化正常费用。
由模型重新选择灾前CHP承诺及热状态，后续事件仍继承同一计划，不能在恢复核查时临时启动CHP1。
4B为了让罚项而非硬门槛决定权衡，可在独立载体上将恢复允许失供界设为关键需求总量，
须记录该策略差异而保持物理正常输入不变；既有case与原结果不修改。
每个新正常候选都重新进行三个故障的聚合与给定流量逐管检查，分别记录采用约束、6-88精确诊断及详细回放。
最坏关键失供、总费用和正常资源成本分开；尚未核验的恢复阶段记未决，不能用主问题见证冒充独立最小失供。
先测试max与sum罚项区别、零罚收益退化、容量必败和继承身份，冻结运行预算与源码后再做规模比较。
