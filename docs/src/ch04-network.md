# 第4章电热网络重构：采用解释与验证

本批从固定拓扑进入带联络线的三节点网络。设备、偏好、结算沿用冻结父输入；
新增联络线与动作规则明确作为合成设定，不是作者原参数。

## 1. 原页与问题

重新核查PDF65–67（印刷48–50），重点为(4-22)、(4-27)–(4-40)、(4-41)–(4-51)。
原文把电开关按时段处理，把热阀门按运行日处理。当前采用版本保持这一时间尺度差异。
完整采用式、原页下标差异和反例见[公式及符号](ch04-network-equations.md)。

原式(4-29)的开关因子与文字含义冲突；(4-38/39)按闭合状态求和不能表达动作次数。
我们依据文字、开路极限和守恒推导新式，不把这些修正冒称作者源码。
仅检查每节点至多一个父节点也不能排除孤岛。本批使用虚拟商品流加边数约束；
连通与径向的适用条件可对照[Wang等公开预印本v3](https://arxiv.org/abs/1912.05185v3)。

## 2. 为什么虚拟方向不等于物理方向？

假设联络线为1–3，选择1–2和1–3后，虚拟流从根节点1向两个节点各送一单位，
只是证明它们与根相连。节点3的CHP仍可向节点1或2送能，不能因为虚拟方向而禁止。

电线路保存一个参考方向，P/Q允许正负。热管分别建立正反方向弧，每条已开阀物理管道
每时段恰选一个方向，反向弧交换端点。损耗只在所选弧计一次；关闭阀门时两弧流量和损耗均零。
阀门仍整日不变，逐时方向切换不冒充阀门开关动作。

这仍是稳态热能流模型：没有水压、温度混合、时延、启停加热能量或瞬态换向。
零质量流与正热输运能否被当前端口包络排除，也不能当成完整管温实现性结论。

## 3. 动作成本和可比较性

每个电开关按真实0/1变化计费；热阀门只相对初始状态计一次。费用单位为合成美元/次，
不乘小时数。该费用由运营商承担，属于资源/操作成本；内部交易支付继续抵消。

初始网络此前至少稳定一个时间步；本批两步窗口至多一次动作，每线全时域最多两次。
尾端拓扑自由，未加周期恢复；因此不能解释为周期重复运行收益。

四种策略为固定、电网可重构、热网可重构、两网联合重构。它们都使用相同的候选图、
双向热模型、核心输入和动作成本。固定策略的零动作计划也属于更自由策略；
若自由策略找到更差候选，须检查界与求解状态，不能直接解释为灵活性有害。
旧固定方向热网输入未迁移，不能与本批双向模型费用差作单因素重构收益。

## 4. 冻结输入与独立参照

配置位于configs/r4/reconfiguration/。联络线1–3的电阻/电抗及热管长度等于原1–2与2–3之和；
新增线不被人为设成更短更便宜。电瓶颈把第一线P/Q容量乘1/2、电流平方上界乘1/4；
热瓶颈把第二管道容量乘1/4。改变前先冻结规则与哈希，不按结果选参数。

单时段参照覆盖3种电树、3种热树、4种接通管方向和2个电池模式，共72项连续SOCP。
只有每项都有有效下界或不可行证据时，才合并下界。这证明的是该单时段有限问题；
四时段问题由整数求解器给出实际界，并另求原电网等式参考。

## 5. Julia入口

```julia
using PaperRebuild
c = load_r4_case("configs/r4/reconfiguration/import.toml")
b = build_r4_reconfiguration(c; spec=R4ReconfigurationSpec(policy=:joint))
```

模型构建不求解、不写文件。科学函数说明见
[build_r4_reconfiguration](@ref PaperRebuild.build_r4_reconfiguration)、
[solve_r4_reconfiguration](@ref PaperRebuild.solve_r4_reconfiguration)、
[validate_r4_reconfiguration](@ref PaperRebuild.validate_r4_reconfiguration)和
[enumerate_r4_reconfiguration](@ref PaperRebuild.enumerate_r4_reconfiguration)。
保存、重读仍使用原生[save_r4_run](@ref PaperRebuild.save_r4_run)/
[read_r4_run](@ref PaperRebuild.read_r4_run)，会检查新拓扑及完整文件哈希。

```powershell
julia +1.12.6 --startup-file=no --project=. scripts/test_r4_reconfiguration.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r4_reconfiguration.jl
```

当前阶段先建立重构数学与程序证据，正式机制结果单独保存；不提前宣称降低费用或改善消纳。
