# 第7.5节准备：初始空间管温

## 目标与本批边界

从b8e003f接续。用户询问本轮意义及下一步，已按当前证据解释部分停电域和初态预检；
持续全文目标下完成有损空间初态输入接口。本批不运行规模保供优化，不推送。
个人settings SHA256保持A70D6C47B0F534D413E3AD85D97503BB0A74C6EAC38FB3A7DDC1FC01CD157D86；
实际Bridge没有注册实例，不能由此断言全部编辑器均已保存。

## 推导与实现

- r7-initial-profile-v2显式序列化完整指数段，R9-RI1至RI3单独编号。
- 保持分段常温旧含义、运算顺序和原输入身份；作者节点法不静默接收新空间历史。
- 正常调度、事件模板精确均温、详细事件继承、正常/共同流量核接入。
- 新空间积分在零UA时仍有误差契约；范围检查使用实际端点，不要求基准温度自身处于物理温区。
- 新依赖进入正常/规划/共同流量及下游R8冻结源码入口；旧包仍用自身冻结源码重验。
- 输入预检为候选分配、预优化审计，不称冻结规模算例。

## 实际验证

- tmp/r9-resilience-input-preflight.log：159项通过；两套关键分配可嵌入同一总负荷。
  参考CHP2为4.629704218134866MW、节点15供热0.6542025790048294MW。
  均温替代首步最大偏差0.17255599710932756K；原报告保留。
- tmp/r7-initial-profile-tests-v1.log：19通过后测试fixture删除变量声明界而失败；
  改用等式保留界，v2的19+41项通过，不改科学门槛。
- tmp/r7-initial-profile-tests-v3.log实际退出0：19+41+19=79项通过；
  正常/共同规划及移位重读/篡改拒绝，开发原值保留tmp/jl_JkOmWB。
- tmp/r7-initial-profile-gurobi-v1.log实际退出0：16+4=20项通过。
  实际变量路径含停流/跨段；解析反问题q=2.000000004000529、下界2.0。
  原记录tmp/r7-initial-profile-gurobi-v1；不把该界用于网络规划。
- 正式预检159项退出0，报告results/summaries/r9-resilience-input-audit-20260921-v1/preflight.toml；
  保留工程协议、脚本及水团回放源码哈希，没有调用规模优化器。
- tmp/r7-initial-profile-normal-replay.log与joint-replay.log均退出0，原冻结源码独立重读通过。
- tmp/r7-initial-profile-regression.log实际退出0，完整R7–R9隔离回归通过。
  之后仅补零UA空间初态的费用界报告范围及五项回归，物理方程不变。
- tmp/r7-initial-profile-tests-v4.log实际退出0，19+41+24=84项通过，原值tmp/jl_LwVF9z；
  映射v2的37项及最终只读格式检查退出0。零预算状态仍不得冒充候选。
- 导航同步退出0，独立核对保留17605个原成员/顺序/人工元数据，新增10项；个人settings哈希保持。
- 最新冻结源码的normal-replay-v2.log与joint-replay-v2.log均退出0；原值仍独立通过。
- tmp/r7-initial-profile-docs.log：严格Documenter/doctest实际退出0，保留既有页面/搜索索引大小警告。
- 显式34文件暂存范围预检首次被沙箱Julia子进程EBADF阻止；允许本机Git管道后退出0，
  tmp/r7-initial-profile-scope-check.log保存71项只读检查通过，无实际暂存。
- 最终Project Check实际退出0，tmp/r7-initial-profile-project-check.log记录Project checks passed。
  采用tmp/stage-r7-initial-profile.jl的34文件明确范围逐字节核对暂存，个人设置不纳入。
  本节点只作本地提交，不推送、不合并；原失败记录与规模未冻结状态保持。

## 后续

本节点工程与证据收尾已通过。之后声明机械可操作开关域、冻结规模输入，再做有限预运行。
全文目标仍active，R9/R10及其他未决研究项不因本节点通过而完成。
