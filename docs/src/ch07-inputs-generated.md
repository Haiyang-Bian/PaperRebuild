# 第7章输入与原表核查索引

<!-- generated: r9-source-ledgers -->

权威记录为 `docs/reading/ch07/` 的原页转录。本页由 Julia 生成；作者数值不是本项目优化结果。

## 场景差异

| 节 | 父输入 | 已核实的独立改动 |
|---|---|---|
| 7.2 | 7.1 | E22光伏从2增至6 MW；四种流量/源温模式 |
| 7.3 | 7.1 | 八聚合商、节点负荷1.5倍、设备与联络线；表7-9是否已放大仍未明 |
| 7.4 | 7.1 | 价格接受者、100代表、ε=0.05、四个P2H设备 |
| 7.5 | 7.1 | 独立CHP扩容/启停成本、GT、0.4新能源、关键负荷与四小时故障 |

## 设备与量纲

44电节点/43条边、38热节点/37对管；两张原图均通过连通树检查。
电负荷峰值 `45.67 MVA` 是视在功率，热峰值为 `7.23 MW`；功率因数仍缺。

基准额定电源合计16.5 MW、光伏8 MW；按表列设备推算供热能力为 9.0 MW，正文写8.1 MW，两者保留。
两个电锅炉的额定热输出为1、1.2 MW，派生额定电输入为 1.086957、1.290323 MW。

## 作者四模式目标：表7-5

| 模式 | 日费用 CNY | 光伏利用率 % |
|---|---:|---:|
| CF_CT | 390828.85 | 96.32 |
| CF_VT | 387334.85 | 96.7 |
| VF_CT | 386177.86 | 98.68 |
| VF_VT | 382346.88 | 99.74 |

由原表首末行重算费用下降 2.170252%，利用率增加 3.42 个百分点；这不是本项目收益。

## 超出显示舍入的算术或跨表差异

舍入带由原表显示位数传播，独立于科学A1/A2门槛。跨表口径未明不能直接断言原文计算错误。

| ID | 重算值 | 原记值 | 单位 | 解释类型 |
|---|---:|---:|---|---|
| R9-Q01 | 9.0 | 8.1 | MW | arithmetic |
| 7-10-vs-7-11 | 67443.06 | 67048.62 | CNY | cross_table_comparability_unresolved |
| Q08-4B | 3.266868 | 4.31 | percent | arithmetic |
| Q08-4C | 1.058038 | 1.68 | percent | arithmetic |

全部 39 行（包括通过和尾数误差）保存在审计报告，未用修正值覆盖原表。

## 原始输入缺口

| ID | 场景 | 仍缺或需澄清 |
|---|---|---|
| R9-D01 | 7.2 / 7.3 / 7.4 / 7.5 | 逐线路电阻、电抗、容量；变压器阻抗/变比；节点电压边界 |
| R9-D02 | 7.2 / 7.3 / 7.4 / 7.5 | 逐管长度、直径、粗糙度/水压、保温；温度/流量边界及历史 |
| R9-D03 | 7.2 / 7.3 / 7.4 / 7.5 | 24小时逐节点有功、无功、热需求、光伏可用出力与功率因数 |
| R9-D04 | 7.2 | 固定热源供温/管流参考及精确的日末热状态约束 |
| R9-D05 | 7.3 | 表7-9是否已放大负荷；HP/EB身份；新增光伏和热储能参数；电池效率/初末状态；不满意度与结算规则 |
| R9-D06 | 7.4 | 逐时价格及备用容量价的时间基准；P2H容量基准；训练/验证/测试样本、舒适度与热参数、模糊集标定 |
| R9-D07 | 7.5 | 关键负荷逐节点分配；精确故障集合/时轴；电源可用性与成网资格 |
| R9-Q01 | 7.2 / 7.3 / 7.4 / 7.5 | 正文8.1 MW与表列基准设备合计9.0 MW供热能力的解释 |
| R9-Q02 | 7.5 | 表7-17标题写4C、所在文字讨论4B；4B罚项目标与纯失供描述不一致 |
| R9-Q03 | 7.5 | 事件时轴不一致；事件1失供表7-18为0.2593 MWh，PDF141文字为0.358 MWh |

## 迁移约束

### 7.2

复用：R2Case, fixed-flow subproblem, R3OperationSpec and independent WMM replay。

接口缺口：第3章目标(3-1)不含启停项，表7-2却列启动费。先确认7.2实际费用口径和初始开机状态；不能仅凭设备表引入二元变量、改变连续梯度子问题。若另研究启停，须命名独立版本。

不得默认继承：7.3 load factor, R3 synthetic recovery tail, or unrecorded transformer equivalence。

### 7.3

复用：R4 theory, network/accounting utilities and validation pattern; separate scale adapter required, not direct R4Case loading。

接口缺口：R4Case is fixed to DSO/A/B and one battery; eight aggregators, two batteries and distinct electric/heat mappings require an incremental scale interface. A4/A8 share heat node 26; avoid double-counting base load. Thermal storage/HP, flexible preferences, payoffs and startup interpretation still require declared inputs.

不得默认继承：7.2 PV enlargement, teaching settlement prices, or automatic second multiplication of table-7-9 loads。

### 7.4

复用：R5 internal dispatch/risk interfaces and R6 frozen statistical protocol。

接口缺口：Resolve capacity input/output basis; specify buildings, call signals, uncertainty support and reserve settlement time.

不得默认继承：Strategic market-clearing KKT, previous synthetic dataset identity or a capacity-price time unit chosen without declaration。

### 7.5

复用：R7 inherited-state planning and R8 economic/penalty/threshold comparisons。

接口缺口：Allocate critical load; freeze clock grid, faults, initial commitments and grid-forming eligibility; source generation differs from 7.3.

不得默认继承：Chapter-6 500 USD/MWh penalty, four-hour window inferred from mixed captions or ablation inferred from HS/NR abbreviations。

迁移状态：`partial_72_fixed_flow_duals_open_73_model_inputs`；详见[输入说明与后续顺序](ch07-inputs.md)。
