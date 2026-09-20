# R8：稳态能流与跨时段储热

本页使用第6.5.3节方案3.1的明确解释，建立`r8_energy_flow_checked_v1`。
这是合成小系统对照；容量和散热规则由项目显式补充，不能称为作者未公开源码的等价实现。
原页记录、居中编号公式和符号见[台账](ch06-r8-energy-equations.md)。
36项正式对照与解析边界见[储热机制结果](ch06-r8-energy-results.md)。

## 为什么要另建稳态对照？

详细热网在某一小时可以“产热多于交付”，把差额存入管水，后续再利用。
稳态能流要求同一小时产热等于负荷加损耗；上一小时多余的热不能带到下一小时。
它还忽略温度、质量流和水压，因此两个模型的可行域一般不能直接视为包含关系。
旧批次“禁止净预充热”仍保留全部温度与库存动态，属于另一项实验。

作者图6-7说明：灾害前段利用充裕电力驱动电锅炉，后段释放热量，减少供热对电力的竞争。
单小时事件难以完整展示这一机制，新增案例明确采用四小时PCC断开。

## 模型差异与共同部分

| 项目 | 详细输运参考 | 稳态能流对照 |
| --- | --- | --- |
| CHP启停、容量、爬坡与价格 | 共用输入 | 共用输入 |
| 电池及电网、故障、重构 | 共用既有模型 | 共用既有模型 |
| 正常到灾后的继承 | 包含空间管温、CHP与电池 | 仅CHP和电池；无虚构管温 |
| 热平衡 | 逐管输运与库存变化 | 当期节点净热量守恒 |
| 损耗 | 输入温度和停留时间相关 | 参考供回温产生的冻结散热 |
| 热端点与末端 | 详细温区和声明库存边界 | 没有温区或热库存终端 |

`reference_UA`仍需在空载时补偿冻结散热；若岛内设备无法产热，恢复可能硬不可行。
这应解释为该参考损耗边界的结果。共同零UA输入用于检验无需损耗近似的储热机制；
有损组的差异同时包含储热和损耗表示变化，不能全部归因于热惯性。

共用检查器的部分检查只报告`shared_block_pass`；它不能单独产生完整模型通过标志。
独立能流验证器另验热流容量、节点守恒、状态继承、原始现金成本和失供积分，组合判定采用模型。

## 可手算的四小时机制

合成案例保留三电节点、两热节点和一对供回水管，移除电池及其独有成网资格。
CHP最多0.3MW电/热，GT最多0.5MW电，电锅炉最多0.25MW电、效率0.95。
电负荷为0.5、0.5、0.8、0.8MW，热负荷恒为0.4MW。

每根管含18000kg水，5kg/s在一小时恰好交换整管。两种UA输入均采用供水下界以上1K的初态，
回温按0.4MW稳态交付推导。该统一余量在首次优化前由首段出水的散热边界推导，未按收益调参。

零UA下可手工令热源出力为0.5、0.5、0.3、0.3MW：
前两小时各存入0.1MWh，后两小时各释放0.1MWh；独立水团回放检查供回温和末端恢复。
手算电锅炉出力为前两小时各0.2/0.95MW、后两小时为零，均在容量内。

即时能流下，晚段电负荷已经等于CHP与GT电出力上限之和。
每增加1MW电锅炉用电，只获得0.95MW热，却需要少供1MW电；故两个晚段的最小电热总失供至少0.2MWh。
这给出可在优化前检验的机制，不预先规定求解器必须返回上述手工轨迹。

## 如何运行与检查

从仓库根目录运行：

```sh
julia +1.12.6 --startup-file=no --project=. scripts/check_r8_energy.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r8_energy_flow.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r8_energy_cases.jl
```

正式协议为`configs/r8/energy-flow-study.toml`：旧两套输入新增12次稳态对照，
新四小时输入在两种UA、三种目标、两种热模型和两求解器下共24次运行，总计36次。
旧动态运行保留；每次运行共享600秒，主阶段最多80%，其后固定正常原值独立评估风险。
冻结、运行、报告和只读重读由`scripts/r8_energy_study.jl`分开提供。
图表须从保存结果生成；当前新增机制不代表论文规模性能已经通过。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/r8_energy_study.jl freeze results/runs/r8-energy-new
julia +1.12.6 --startup-file=no --project=. scripts/r8_energy_study.jl run results/runs/r8-energy-new HiGHS
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/run_r8_energy_gurobi.jl results/runs/r8-energy-new
julia +1.12.6 --startup-file=no --project=. scripts/r8_energy_study.jl check results/summaries/r8-energy-20260920-v1
```

先冻结再运行，已运行目录拒绝覆盖；VS Code的“R8 energy”任务提供相同入口。
已有证据无需重新优化，使用`check_r8_energy_results.jl REPORT PARENT AUDIT`重验，
`plot_r8_energy.jl REPORT AUDIT NEW_FIGURES`在docs环境中只读重绘。

## 自由流量可行性补证

旧四项限时无候选状态保持。独立固定方案嵌入把物理值保持不变，仅求辅助量，另保存全部辅助变量。
`scripts/r8_embedding_evidence.jl check REPORT EVIDENCE`使用父冻结源码重建**未固定的原自由模型**，
从保存值重算全部约束，再做独立物理回放；无需Gurobi许可，也不重新优化。
补证包为`results/summaries/r8-embedding-20260920-v1`。
首版审计类型错误仍存档，四项完整v2给出可行见证，不能替代自由调流收益和最优性证明。

## Julia API

```@index
Pages = ["ch06-r8-energy.md"]
```

```@docs
r8_energy_spec
build_r8_energy_model
solve_r8_energy_case
validate_r8_energy_solution
save_r8_energy_run
read_r8_energy_run
```
