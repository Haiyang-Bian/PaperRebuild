# R6 正式实验协议与运行顺序

本页说明怎样从[六方法开发实验](r6-pilot-results.md)进入可比较的样本外研究。
最新进度：训练、验证和独立测试均已完成，详见[独立测试阶段结果](r6-test-results.md)；
压力测试和正式报告尚待收尾。下文保留各阶段执行历史，不将旧快照改写成后续完成状态。
规则位于`configs/r6/study.toml`，全部输入仍是合成数据。实现节点b27c59b已通过验收，
正式批次`r6-formal-20260919-v1`的14输入和源码已冻结并独立重验，D/SP原值已保存。
SP优化约27.43秒，随后策略提取在大文本字符串哈希上耗时；独立探针已定位，原进程经身份核验后结束。
修复只将同一UTF-8文本送入SHA的载体改为IOBuffer；新批次r6-formal-20260919-v2已按下述契约续接，
D/SP全部原值保持，未重新优化。两项进度快照已通过8项独立重验/篡改检查，剩余训练继续。
在上述续接节点，完整训练、500验证日及1000测试日尚未完成；不能把接口测试或进程启动当作正式风险或费用结论。

## 要回答的问题

在同一个24小时系统与同一组新日上，分布稳健与机会约束是否改善室温风险和备用交付？
增加的费用是否值得，哪些策略在持续调用下仍会失败？
训练目标的定义不同，最终比较必须使用共同新日操作规则和同日费用。

## 首次求解前固定什么

| 项目 | 本批规则 |
|---|---|
| 输入 | 已冻结2000训练日；训练专用100代表；500验证日；1000独立测试日 |
| 方法 | D、SP、RO、DRO、CCP、DRJCC |
| 半径 | DRO/DRJCC各取0、0.0005、0.001、0.005、0.01，共14项训练配置 |
| 风险 | 完整日联合舒适限额5%，单侧95%概率界；未知留在分母 |
| 主操作 | `r6_support_nearest_v1`，固定训练成交、所选价格和最近代表的舒适开关 |
| 预算 | 每个训练配置600秒，每个新日60秒；包括既有接口内建模与核验 |
| 求解器 | 训练Gurobi，单日补救HiGHS，线程1；参数在配置中逐项冻结 |
| 压力日 | 无PV/晴空PV × 持续满上调/满下调，单独保存24项结果 |

零半径检查名义分布退化，小正半径用于考察较弱扰动下风险预算的作用。
这些是项目设计，既不冒称作者参数，也不预先断言覆盖最佳半径。
与开发批次最先三个代表的条件概率不同，正式训练使用完整100代表及原训练簇频数。

## 怎样选择参数

每个候选都在相同500验证日上运行。先检查[式R6-F1](r6-study-equations.md#R6-F1)：
保守概率上界不超过5%、全部费用完整，才进入该方法的合格集合。
其中按最低平均净费用选择，费用在`1e-8`合成USD内同分取较小半径。

若没有合格候选，仍按事先声明的风险上界、缺失费用数、完整均费、半径顺序选择一个，
但保持`validated=false`。这使失败有完整后续证据，不意味着验证通过。
验证选择规则见[式R6-F2](r6-study-equations.md#R6-F2)与[`select_r6_methods`](@ref)。

参数选择锁定以后，才运行1000测试日。不能看测试结果重新选半径、轨迹或操作方式。
最终主要检验是所选DRJCC策略的联合舒适风险；其他方法为比较结果，
不得把分别计算的区间称为六方法同时保证。配对费用有缺失时不提供完整总体排名。

## 失败、限时和压力怎样处理

- 训练候选须通过模型、风险、费用重算与独立市场检查。限时但合格的策略可以继续评价，最优性未完成单列。
- 没有合格训练策略时，该候选全部新日记未知；不换初值或将失败标成零违约。
- 单日缺解、缺可信费用最优性或数值失败，仍保存原状态和数值，未知保留在概率分母。
- [独立舒适诊断](r6-evaluation.md)不替代正式策略结果，不能用诊断成功消除主策略失败。
- 四个确定性压力日不进入二项统计或测试均费，见[式R6-F3](r6-study-equations.md#R6-F3)。

总净费用含日前支付和实时设备、结算、罚项，可能为负；这不是社会资源成本。
原论文按备用容量的误差预算与按实际调用量的交付指标分别报告。
仍使用完整未来轨迹、乐观市场选择、线性电网和固定流量热网，不能称在线控制或完整交流/水力认证。

## 当前训练结果与下一步

本机批次`r6-formal-20260919-v2`的14项训练已完成，候选检查与费用求解完成标志均通过。
D/SP沿用已保存原值，没有重复优化；其余候选按冻结顺序及原预算执行。
此前两项快照继续保留其历史范围，不能把后来完成的配置补写进旧快照。

本批使用100个训练代表。SP训练目标为−86.630502合成USD，CCP为−86.840688；
与前三代表开发例相比，两者不再相等，表明原来的小样本退化不能推广为“机会约束没有作用”。
这仅证明采用模型在本次输入上给出不同选择，不证明CCP在新日更省钱或更可靠。

同一模型族内，DRO半径从0增至0.01时，训练目标从−86.630502变为−84.343542；
DRJCC对应从−86.840688变为−84.346069。这与增加分布不确定性约束后更保守的训练目标相容。
各方法的目标包含不同的期望、最坏费用或风险约束，不能将这些数字直接排列成总体性能名次。
负值表示本模型的净支付口径，不代表负的社会资源成本。

下一步已经经冻结执行目录启动：14候选先在同一500个验证日评价，按预先冻结的资格和回退规则
锁定六策略，再做1000个独立测试日及四个单列压力日。需要同时报告违约率上界、未知数、
费用完整性和同日配对费用；尚未执行的日子不计作成功。

### 500日验证的阶段结果

随后14组验证全部完成，共7000次逐日评价，均无未知日，费用完整。
选择阶段已逐条原值重验并锁定策略；下表是验证描述，尚非独立测试结论。
各方法概率界是分别计算的单侧95%界，不是多候选同时保证。

| 候选 | 违约日/500 | 概率上界 | 日均净费用（合成USD） |
|---|---:|---:|---:|
| D | 0 | 0.5974% | −84.270799 |
| SP | 0 | 0.5974% | −85.697078 |
| RO | 0 | 0.5974% | −81.621341 |
| DRO，半径0.0005 | 0 | 0.5974% | −85.717410 |
| CCP/DRJCC，半径0 | 23 | 6.4543% | −85.863175 |
| DRJCC，半径0.001 | 17 | 5.0564% | −85.824000 |
| DRJCC，半径0.005 | 6 | 2.3547% | −85.602056 |
| DRJCC，半径0.01 | 0 | 0.5974% | −85.582114 |

CCP观测违约比例4.6%虽低于5%，其概率上界仍超过门槛，判为证据未定。
半径0.001也不能因只略超门槛就算合格。增加到0.005时，DRJCC减少了相对CCP的违约，
均费增加约0.261119合成USD；这支持本输入上的风险与费用权衡。
但SP既无观测违约、均费又略低于该DRJCC候选，因此没有“DRJCC全面优于其他方法”的证据。
不能把训练目标、选参用验证均费或零观测违约直接当作真实总体性能保证。

选择进程已退出0：DRO锁定半径0.0005，DRJCC锁定0.005；CCP按原规则回退并保留`validated=false`。
1000个独立测试日已通过原冻结执行目录启动，单列压力日待随后执行。
不根据本表改半径、数据或舒适门槛。原始证据位于v2批次各`validation/<candidate>/summary.toml`，
正式可移植报告及图表须在后续原值重验和测试齐备后封存。

## Julia 与 VS Code 入口

在仓库根目录按顺序执行；以下`<study-directory>`替换为同一个新的运行目录。

```text
julia +1.12.6 --startup-file=no --project=. scripts/test_r6_study.jl
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl freeze <study-directory>
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl train <study-directory>
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl validation <study-directory>
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl select <study-directory>
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl test <study-directory>
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl stress <study-directory>
julia +1.12.6 --startup-file=no --project=. scripts/r6_study.jl check <study-directory>
```

VS Code任务提供同名操作。冻结前科学源码与规则必须已经提交；不要求个人编辑器设置进入提交。
冻结包含14项完整训练输入、全部日身份、压力轨迹身份、源码归档、环境与设备信息，且不启动优化。
归档逐文件与磁盘哈希一致后才能运行。执行期间改变科学源码会拒绝继续，不能混用版本。

训练、逐日结果采用新文件写入；再次运行只重读已有结果，继续尚无记录的配置或日子。
半写目录不作为完成标志，也不自动删除。`select`逐日回代后固定六策略；`check`不求解，
重新核验已有记录并明确是否已齐备14训练、14验证摘要、6测试摘要和6压力摘要。
记录齐备与风险/费用验收通过仍是不同字段。

## 已保存结果的报告与重验

`report_r6_study.jl`只读取已经封存的训练记录与分组摘要，不重新求解。
`create`要求14训练、14验证摘要、6测试摘要及6压力摘要齐备；运行途中可显式使用`snapshot`。
进度快照的缺失记录标为`not_recorded`，不能把尚未执行的日子写成零违约。

```text
julia +1.12.6 --startup-file=no --project=. scripts/test_r6_study_report.jl
julia +1.12.6 --startup-file=no --project=. scripts/report_r6_study.jl snapshot <study-directory> <new-report>
julia +1.12.6 --startup-file=no --project=. scripts/report_r6_study.jl create <study-directory> <new-report>
julia +1.12.6 --startup-file=no --project=. scripts/report_r6_study.jl check <study-directory> <report>
```

训练目标与样本外均费分表。`risk-cost.csv`保留风险上下界、未知数、完整费用数和条件费用统计；
`days`分块保留每天的费用、室温与实际调用交付。六个测试分组齐备后才生成同日配对费用表，
任何配对缺失都不生成总体差值区间。压力日另表，不进入随机样本风险和均费。

报告绑定其生成时已完成记录的哈希；后续追加其他配置不会改写旧快照。
`check`重新执行对应训练与逐日数值验算，再逐字节核对CSV，不能只靠报告自己的哈希声明通过。
此入口依赖本地原始批次及其冻结科学源码，逐日重算完整物理原值。
正式结果及公开统计/压力证据入口见[测试与压力结果](r6-test-results.md)。

### 可移植统计与压力证据

`r6_public_report.jl`从完整报告导出新包，不重新求解。它包含全部13000条随机日统计源表、
15组配对费用、14候选策略及24压力日完整原值和科学源码归档。
随机日公开重验仅认证由日记录重算统计，不含随机日全部调度/KKT原值；
这些完整原值仍由本地原报告入口重验。压力日则在临时目录加载原科学源码进行完整回代。

```text
julia +1.12.6 --startup-file=no --project=. scripts/r6_public_report.jl create <study-directory> <report> <new-public>
julia +1.12.6 --startup-file=no --project=. scripts/r6_public_report.jl check results/summaries/r6-public-20260920-v1
julia +1.12.6 --startup-file=no --project=. scripts/test_r6_public_report.jl results/summaries/r6-public-20260920-v1
julia +1.12.6 --startup-file=no --project=docs scripts/plot_r6_study.jl results/summaries/r6-public-20260920-v1 <new-figure-directory>
```

后两项分别做重封哈希后的数值篡改拒绝、只读图表重绘；不重选参数、不重跑优化。
F17保留共同日费用和配对区间；F18注明各自单侧概率界；F19保留全部四压力日，
建筑相对初温显热不能称为电池或管网储热量。图源、运行ID和生成配置与图一同保存。

### 原值续接的边界

`continue_r6_study.jl <parent-batch> <new-frozen-batch>`仅用于本次已定位的哈希性能修正。
它检查两份源码归档只有一处预先登记的字面替换，规则、14训练输入、全部数据与物理边界完全相同。
原运行连同旧源码/提交记录完整复制，逐文件哈希核对，已有摘要和策略须保持相同。
续接另写`continuation.toml`，未尝试配置仍执行原600秒预算；不把文件处理耗时记成优化速度。
其他模型或配置变化必须另作研究版本，不能使用这个限定入口。

## 长运行与后续章节开发的隔离

正式批次的科学源码必须保持冻结，但后续章节仍需增量开发。
`r6_frozen_workspace.jl`将原`source.tar`和冻结日数据复制到独立执行目录，
原模型、14输入、求解器参数、预算和选择规则全部保持。报告程序从同一个冻结提交取出。
这只隔离执行文件，不改变任何科学方法，不重新生成日轨迹或已有训练结果。

```text
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl prepare <study-directory> <new-frozen-workspace>
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl check <study-directory> <frozen-workspace>
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl run <study-directory> <frozen-workspace> validation
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl run <study-directory> <frozen-workspace> select
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl run <study-directory> <frozen-workspace> test
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl run <study-directory> <frozen-workspace> stress
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl run <study-directory> <frozen-workspace> report-snapshot <new-report>
julia +1.12.6 --startup-file=no --project=. scripts/r6_frozen_workspace.jl run <study-directory> <frozen-workspace> report-check <report>
```

执行前后逐文件检查归档身份、数据清单和完整目录；拒绝额外文件、重写源码清单、路径越界和覆盖。
执行目录的`execution.toml`记录原冻结提交，子进程避免向上识别开发仓库的新HEAD。
Julia依赖缓存可共用，源文件与输入是独立副本。命令失败保留原退出状态和已有结果，不自动重试。
`check`只核查文件身份；`run ... check`调用原批次的数值重验，两者证明范围不同。

VS Code提供准备、文件核查、冻结实验动作和报告入口。
当前v2的隔离目录位于该批次`frozen-workspace/`；首次运行仍须核验对应原值报告。
旧的主工作区训练进程终止前仍不能修改其科学源码；只有实际切换到已核验的隔离入口后，
后续章节开发才不会影响这项正式实验。

### 可追踪的实现

[`R6StudySpec`](@ref)、[`r6_study_candidates`](@ref)规定候选；
[`r6_summarize_days`](@ref)、[`select_r6_methods`](@ref)负责统计与选择。
`test/r6_study.jl`的R6-F1/F2/F3检查未知分母、阈值选择、同分/回退、源码冲突、
压力边界和原始数值重读。正式报告、同日费用比较与F17–F19应在真实运行后生成。
