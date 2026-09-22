# 第7.5节准备：关键负荷与全量失供

本节点为已有R7/R8增加显式关键电负荷服务范围，使用合成解析例验证。
**尚未取得第7.5节规模保供结果，也没有恢复作者缺失的逐节点重要负荷。**
币种接口见[费用与状态继承](ch07-resilience-currency.md)；权威映射为
`docs/reading/ch07/resilience-load-service.toml`。R9-RL1至RL3均为项目编号。

## 1. 原文、解释与采用范围

原论文PDF112（印刷95页）式（6-53）同时积分电、热失供。
PDF139（印刷122页）第7.5节方案4B改称重要负荷失供，罚值10元/kWh；
4C要求四小时重要负荷失供不超过2 MWh。13.75 MW的总量与电网节点标记支持
采用“重要有功电负荷”的解释，但逐节点分配未公开，图7-12和图7-14标记也不完全相同。
因此本项目显式声明这一解释，并保留来源疑点，不把所有电热损失直接改名为重要负荷损失。

| 内容 | 来源或性质 | 本节点处理 |
| --- | --- | --- |
| 原（6-53）全电热失供目标 | 作者原式 | 无`load_service`的旧输入继续使用 |
| 第7.5节重要负荷指标 | 作者表述，节点分配未闭合 | 新输入显式给出逐节点、逐时段关键有功负荷 |
| 关键/普通负荷共用节点功率因数 | 项目采用解释，参考原（6-54） | 仍从服务有功计算对应无功 |
| 普通、热负荷继续留在物理约束中 | 项目服务契约 | 不删除需求，保留原总削减上界 |
| 只优化关键电失供，其他损失另报 | 项目显式目标范围 | 不隐含增加第二级优化目标 |

单独改变统计范围会改变最优调度。关键失供为零不代表普通或热负荷零失供，
也不保证所有负荷损失之和最小。同一关键最优值可能对应不同普通和热失供；
当前没有按词典序二次最小化它们，不能把任意并列解的分项差当作严格资源收益。

## 2. 保留总需求，再分服务优先级

在原节点``n``、时段``t``给定总有功负荷``P^D_{n,t}``和关键部分``P^{D,c}_{n,t}``，
普通负荷由两者之差确定。场景``\omega``中的原总削减变量拆为两类：

```math
\begin{aligned}
0&\le P^{D,c}_{n,t}\le P^D_{n,t},\qquad
P^{D,o}_{n,t}=P^D_{n,t}-P^{D,c}_{n,t},\\
P^{\mathrm{shed}}_{n,t,\omega}
&=P^{\mathrm{shed},c}_{n,t,\omega}+P^{\mathrm{shed},o}_{n,t,\omega},\\
0&\le P^{\mathrm{shed},c}_{n,t,\omega}\le P^{D,c}_{n,t},\qquad
0\le P^{\mathrm{shed},o}_{n,t,\omega}\le P^{D,o}_{n,t}.
\end{aligned}
\tag{R9-RL1}
```

原总削减比例边界继续作用于``P^{\mathrm{shed}}``。电平衡中的服务需求仍是
``P^D-P^{\mathrm{shed}}``，无功需求仍为该量乘原节点``\tan\phi_n``；
因此不会通过删去普通负荷制造更容易的物理问题。

| 符号 | 意义与单位 | Julia或配置 |
| --- | --- | --- |
| ``n,t,\omega`` | 电节点、时段、新能源场景索引 | 数组顺序为节点×时段×场景 |
| ``P^D`` | 原总电负荷，MW | `electric.load_MW` |
| ``P^{D,c}`` | 关键有功负荷，MW，确定性输入 | `load_service.critical_load_MW`，节点×时段 |
| ``P^{D,o}`` | 普通有功负荷，MW | 原总量减关键部分，不另建可能冲突的输入 |
| ``P^{\mathrm{shed},c}``、``P^{\mathrm{shed},o}`` | 两类失供功率，MW | `P_shed_critical`、`P_shed_ordinary` |
| ``p_\omega``、``\Delta t`` | 场景概率、小时步长 | `probabilities`、`dt_h` |
| ``e,f`` | 事件及其声明集合内的故障 | 原事件规格及有限故障枚举 |

类别标签`critical`/`ordinary`是实现扩展；不冒用原文未定义的上下标含义。

## 3. 四个电热分项与一个目标

```math
\begin{aligned}
L^c&=\Delta t\sum_\omega p_\omega\sum_{n,t}P^{\mathrm{shed},c}_{n,t,\omega},\\
L^o&=\Delta t\sum_\omega p_\omega\sum_{n,t}P^{\mathrm{shed},o}_{n,t,\omega},\qquad
L^E=L^c+L^o,\\
L^{\mathrm{all}}&=L^E+L^H,\qquad \min L^c.
\end{aligned}
\tag{R9-RL2}
```

所有``L``单位为MWh。新验证记录中，`loss_critical_electric_MWh`、
`loss_ordinary_electric_MWh`、`loss_electric_MWh`、`loss_heat_MWh`和
`loss_all_energy_MWh`各自保留。通用`loss_MWh`指**该输入声明的目标指标**：
新关键版本为``L^c``，旧未分类版本为``L^{\mathrm{all}}``。
结果的`objective_kind`和输入哈希共同防止误用；禁止跨范围直接比较这个通用列。

手算例为一小时0.6 MW电需求，其中关键0.3、普通0.3。断线后该岛只有0.2 MWh电池，
故关键失供至少``0.3-0.2=0.1`` MWh，普通失供0.3 MWh，总电失供0.4 MWh。
原热负荷继续存在，实际热失供另报。步长改成0.5 h时关键失供0.05 MWh；
改成2 h时电池能量耗尽，关键失供0.4 MWh，不能只按功率乘时间忽略库存。
两个场景分别继承0与0.2 MWh、概率0.25与0.75时，关键期望失供应为0.15 MWh。

## 4. 灾前规划、阈值与人民币罚费

正常期需求仍为原总需求。事件从原时间网格的``a_e``开始，关键负荷同步截取相同窗口：

```math
\begin{aligned}
P^{D,c,\mathrm{rec}}_{n,\tau}&=P^{D,c,\mathrm{normal}}_{n,a_e+\tau-1},\\
\eta_e&\ge L^c_{e,f}\quad(\forall f\in\mathcal F_e),\\
C^{4B}_{\mathrm{adopted}}&=C^{\mathrm{normal}}+lambda\sum_e\eta_e,\qquad
\eta_e\le\overline L^c_e\quad\text{（阈值方案）}.
\end{aligned}
\tag{R9-RL3}
```

``L^c_{e,f}``已经包含新能源概率加权。只有最坏恢复评估完成后才能将上图量解释为
声明故障集合中的最坏损失；普通/热分项取自相应关键最坏见证，不是各自独立最大值。
事件求和不代表事件概率；有限集合通过也不认证未覆盖故障。

人民币版本沿用显式`currency="CNY"`，`penalty_MWh=10000`。
罚项是CNY/MWh乘MWh；恢复评估与恢复下界仍是MWh。
本节点测试这一组合的计算链，不将相同罚值视为作者输入已补全。

## 5. Julia操作与核查

```@index
Pages = ["ch07-critical-load.md"]
```

```@docs
with_r7_critical_load
```

短调用示例：

```julia
c = load_r7_recovery_case("configs/r7/recovery-hand.toml")
critical = reshape([0.0, 0.3], 2, 1)
new_case = with_r7_critical_load(c, critical;
    provenance="合成解析例：关键0.3 MW，原总负荷0.6 MW")
```

后续使用原[`solve_r7_recovery`](@ref)及[`validate_r7_recovery`](@ref)。
正常版本同样通过[`R7NormalCase`](@ref)进入规划及[`r8_spec`](@ref)/[`r8_energy_spec`](@ref)。
构造器复制父输入；不修改设备、原需求或已有运行。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r7_critical_service.jl
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_critical_service.jl
```

测试包括解析积分、不同概率、LP原对偶、错误分配/维度/符号/范围拒绝、零关键需求边界、
预算耗尽、移位重读与篡改拒绝；并覆盖有限故障规划、详细/能流恢复和三种目标的继承。
既有A1/A2不变，源代码与测试分别见映射台账，不在正文复制完整实现。

本节点179项专项、45项映射与条件输入检查、完整R7–R9隔离回归均已实际通过；旧冻结正常/恢复证据16项
重验也通过。严格Documenter/doctest通过。它们验证采用的模型与接口，未运行规模保供或远端CI。

## 6. 本节点之后

本实现只处理原共同网格，不新增小时到15分钟转换；正常爬坡、开停与管内历史不能直接重贴标签。
下一步要明确关键负荷节点分配、事件窗口、故障全集及预算、孤岛成网资格，再冻结小批次输入。
两图冲突与原作者未公开细节仍保存在`resilience-review.toml`。

本节点还继承R7既有的全节点成网路径要求：虚拟商品流在每个节点有单位需求，
各节点电压均有正下界。因此，即使允许切除全部负荷，无合格电源的孤立节点仍不在该恢复域内。
这不是关键负荷接口本身修复的范围；后续[部分停电域](ch07-energization.md)已单独实现并核查。
规模迁移前应以单断线解析例区分“全部节点须带电”与
“允许部分节点停电”的采用模型，不能把前者的不可行直接当作实际保供不可能。
开发反例从原两节点手算输入去掉电池，设置电/热需求全零、第二节点无根资格，再切断唯一电线；
在60秒预算内返回`INFEASIBLE`。孤立节点的虚拟流等式此时要求`0=-1`，独立解释了冲突。
输入、结果与冻结源码保留在`tmp/r9-isolated-node-20260921-v1`，它不是论文规模保供结果。

还有一个迁移输入的条件冲突：旧第7.2节合成协议把45.67 MVA按功率因数0.9均分到43个非根节点，
两套重要节点集合内的总峰值负荷仅11.470605、12.426488 MW。
**若把13.75 MW解释为这些节点在同一峰值时点的关键需求，旧分配就无法容纳它。**
这说明需要明确13.75 MW的容量/时序含义并另行冻结节点分配；不是论文错误证据，
也不能靠突破R9-RL1或静默增大总负荷解决。条件算术由同一映射检查器核验。
解析例和接口测试通过只能说明这一服务口径实现正确，不能宣称第7.5节规模保供或全文完成。
实际收尾状态见`docs/agent/tasks/2026-09-21-r9-critical-service.md`。
