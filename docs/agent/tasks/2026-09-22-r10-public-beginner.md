# R10公开入门与原计划核查

## 目标与边界

从972dc64接续全文目标，先解释最近实验，再收尾正在进行的入门交付。
不追加新的正式科研实验、不推送、不合并；测试内小例求解另记，不扩大为新的研究批次或全文完成。
Bridge返回NO_VSCODE_INSTANCE；个人settings的SHA256保持
A70D6C47B0F534D413E3AD85D97503BB0A74C6EAC38FB3A7DDC1FC01CD157D86。

## 实际改动

- 入门R1测试入口复用现有科学测试，新增目录选取检查；完整Pkg.test和CI集合保留。
- R1默认目录按元数据创建时间选取，不混入R2–R9，不过滤失败，不跳过损坏的R1记录。
- 标准库封存器保留原输入/解、冻结验证源码、环境、预检来源、图源与图形；
  独立重算235条数值残差，而非只验证文件哈希。原始运行来自10a4c9e隔离克隆。
- v1封存器在Julia1.12有动态绑定警告；v2修正调用方式，原科学字节与判定不变。
  v1保留本地并精确忽略；v2使用depwarn=error运行。
- first-run.md从手算走到图表；原计划证据核查明确F07/F13及全文剩余范围。
  README、首页及覆盖表区分当前状态与历史快照。未修改AGENTS的科研原则。

## 已执行检查

- tmp/r10-r1-entry-v1.log：63项原R1断言、8项目录选择断言通过；未加载Gurobi。
- scripts/check_test_stages.jl：五组检查通过，91文件完整覆盖；未修改CI科学预算。
- tmp/r10-r1-latest-task-v1.log：默认选择根仓库最新真实R1记录并只读验证通过。
- tmp/r10-beginner-archive-v2.log：原预检封存及235条残差重验通过；费用24.33235889299821教学单位，
  最大残差/门槛0.0010082611048151113，模型与原支路等式通过。
- tmp/r10-beginner-tests-v2.log：9项通过，包括换目录、字节篡改、重签哈希后的物理篡改拒绝；无绑定警告。
- tmp/r10-public-frozen-cli-v1.log：包内replay.jl在depwarn=error下独立重验通过。
- tmp/r10-public-format-v1.log：只读JuliaFormatter通过。
- tmp/r10-public-r1-r4-regression-v2.log：受影响R1–R4隔离Pkg.test进程33391实际退出0，tests passed。
- tmp/r10-public-docs-v2.log：严格Documenter/doctest进程80370实际退出0，新两页已生成。
  原有页面/搜索体积提示保留，未改变严格构建选项。
- v1分别因维护锁EACCES、depot锁EACCES、IOCapture EBADF失败；已通过工具审批用相同入口重跑，原日志保留。
- tmp/r10-public-navigation-sync-v2.log：Sync78316实际退出0。
- tmp/r10-public-navigation-preservation-v1.log：20467原成员及顺序/别名/人工元数据保持，新增46；个人settings不变。
- tmp/r10-public-docs-final-v1.log：同步后严格Documenter/doctest45483实际退出0。
- tmp/r10-public-staged-check-v1.log：62个文件的明确范围、个人设置排除及冻结Git原字节168项通过。
- tmp/r10-public-project-check-v1.log：最终项目Check98849实际退出0，Project checks passed。
  仅记录真实手动检查；没有原生审阅基线，不伪造会话/Review。

## 研究解释与下一步

集中候选可行不证明分布算法有效；区域容量证书排除当前输入的门槛，不否定作者原输入。
R1预检与标准库回放证明一条开放入门路径，不证明全新电脑、全章节完整包或全文成功。
后续保留F07受控算法/规模/质量、F13主体扩展性、第6章控制域、第7章有效备用与完整故障域。
只读文档对照不替代每个历史包的独立数值回放；完整原值缺口必须显式登记。

下一批F13建议先冻结共同物理系统与分组方式，保留每个原节点的四类端口、约束和成本，
证明集中/分块相互嵌入后再求解。现有接口按原主体保存端口，不能为合并主体而混合不同节点注入。
固定资源下的计算分组敏感性和增加真实主体/资源的规模研究要分别命名；当前尚未实现该新实验。
