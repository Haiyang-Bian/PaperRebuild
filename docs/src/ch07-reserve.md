# 第7.4节：备用输入、费用单位与初始基准

本节正在把第5章的固定价格备用模型迁移到44电节点、38热节点与24小时系统。
首先确认设备、费用单位和初始状态相容，然后才比较风险方案。
**输入核查和无备用开发基准不等于完成100情景风险实验。**

## 1. 从什么系统开始

原PDF135–137的第7.4节是价格接受型研究，3A、3B、3C分别讨论鲁棒、已知概率机会约束、
分布鲁棒机会约束。它从第7.1节独立修改，不沿用第7.2节PV1扩容至6 MW，
也不沿用第7.3节聚合商设备及负荷放大。原文结果表只保留为作者报告值，不用于反推替代参数。

新模板保留PV1的2 MW以及三台PV总容量8 MW，新增表7-12的四台用户侧P2H：

| 设备 | 电节点 | 热节点 | 采用电输入容量 MW | 转换效率 |
|---|---:|---:|---:|---:|
| P2H1 | 15 | 23 | 0.20 | 0.8 |
| P2H2 | 2 | 6 | 0.30 | 0.8 |
| P2H3 | 38 | 28 | 0.25 | 0.8 |
| P2H4 | 21 | 14 | 0.20 | 0.8 |

原表未写容量在电侧还是热侧，电输入侧是显式项目解释。
电负荷峰值45.67 **MVA**乘替代功率因数0.9得到41.103 MW，不能直接当45.67 MW。
热源H1/H15之外的36个热节点各配一栋合成建筑；四个有本地P2H，其余只能接收热网供热。
源、荷和设备位置来自台账；建筑参数、管径/长度/保温、线路阻抗及小时曲线是冻结协议中的替代输入。

## 2. 初始历史怎样构造

参考室温294.15 K、环境283.15 K，取原热峰值7.23 MW的80%均分给36个负荷节点。
参考端口温差40 K、建筑时间常数6 h。计算使用比热
``c=4200\times10^{-6}\;\mathrm{MW}/[(\mathrm{kg/s})\mathrm K]``：

```math
H_b^{\mathrm{ref}}=\frac{7.23\times0.8}{36},\qquad
m_b=\frac{H_b^{\mathrm{ref}}}{40c},\qquad
G_b=\frac{H_b^{\mathrm{ref}}}{294.15-283.15},\qquad C_b=6G_b.
\tag{R9-RS1}
```

源H15的参考注入流量按0.6 MW和40 K确定；其实际所需热量还受混合回水影响，
不强制等于0.6 MW。其他质量流沿原树累加，遇到零流或反流即拒绝。
管道截面由0.5 m/s的声明流速确定，600 m长度和保温关系形成显式的SI损耗参数。

采用已有第5章节点法核。令``d_p``为管内容水量相对一个时间步流量的比值，
``a_p=\lceil d_p\rceil``，``\varepsilon_p``单位W/(m·K)，``A_p``单位m²：

```math
d_p=\frac{\rho A_pL_p}{m_p(3600\Delta t)},\quad
J_p=\exp\!\left[-\frac{\varepsilon_p(3600\Delta t)}
 {c_p\rho A_p}\left(a_p-\frac12\right)\right],\quad
T_{p,\mathrm{out}}^{\mathrm{ref}}=T_a+J_p(T_{p,\mathrm{in}}^{\mathrm{ref}}-T_a).
\tag{R9-RS2}
```

此处``c_p``为4200 J/(kg·K)。它保留作者核的半时间步项，
不能解释为连续水团热方程的精确衰减。先前向算供水、再反向算回水：

```math
T_i^S=\frac{\sum_{p\to i}m_p T_{p,\mathrm{out}}^S+
 \sum_{s\in i}m_sT_s}{\sum_{p\to i}m_p+\sum_{s\in i}m_s},\qquad
T_b^R=T_{i(b)}^S-\frac{H_b^{\mathrm{ref}}}{cm_b},\qquad
H_s=cm_s(T_s-T_{i(s)}^R).
\tag{R9-RS3}
```

回水混合使用下游回水与本地负荷回水同样加权。将每根管的入口参考温度填入所需历史，
不通过优化结果反推初值。参考源温363.15 K、本地P2H为零时，源H1/H15所需热量约
5.730396/0.679651 MW，源端容量及温度范围均通过独立检查。

建筑采用末温等于初温；管温终端显式为`free`。未来环境按参考建筑热损与声明热曲线换算。
它们都是本次替代设定，尚不能支持公平周期费用或真实建筑舒适性结论。

## 3. 人民币费用与输配费

旧`r5-dispatch-case-v1`继续使用USD字段，旧输入和哈希不迁移。
新v2要求`currency = "CNY"`或`"USD"`，费用字段为`cost_per_MWh`与`penalty_per_MWh`。
单位声明、成本残差与灵敏度跟随输入币种；不执行汇率换算。
原USD策略市场和已验证市场父成交不能自动用作人民币输入。

备用容量价显式解释为CNY/(MW·h)，收入乘时间步。
原PDF135的文字给出能量价200–400、备用价20–40，但图7-9的曲线并非全部落在这些范围内。
当前协议采用文字范围内的合成价格，不将它们称为图像数字化结果；真实逐时价格仍缺失。
输配费``\kappa^{\mathrm{grid}}=125.6`` CNY/MWh只加在日前和实时能量价格上：

```math
\kappa^{\mathrm{grid}}\Delta t\sum_t
\left(P_t^{\mathrm{DA}}-P_t^{\mathrm{delivery}}\right)
=\kappa^{\mathrm{grid}}\Delta t\sum_tP_t^{\mathrm{PCC}}.
\tag{R9-RS4}
```

因此实际进口电量只付一次输配费，不对备用容量重复收费。
解析费用缩放、可信对偶、共同承诺、风险分支枚举和保存重读由`test/r5_currency.jl`验证。
完全固定的零备用手算例可能有退化乘子；其数值不唯一不代表币种接口错误。
梯度缩放检查使用具有解析导数的光滑域，不修改求解器原始乘子或放宽KKT阈值。

## 4. 开发入口与未完成工作

```julia
using PaperRebuild
case = r9_reserve_template("docs/reading/ch07", "configs/r9/reserve-protocol.toml")
audit = audit_r9_reserve_input(case)  # 不求解、不写文件
```

Julia入口均有对应VS Code任务。输出须选新目录，已有结果不可覆盖：

```sh
julia +1.12.6 --startup-file=no --project=. scripts/check_r9_reserve.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_reserve.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r5_currency.jl
julia +1.12.6 --startup-file=no --project=. scripts/probe_r9_reserve.jl input results/runs/r9-reserve-input-new
julia +1.12.6 --startup-file=no --project=. scripts/probe_r9_reserve.jl nominal results/runs/r9-reserve-nominal-new
```

`nominal`先保存输入与源码，再以一个确定性情景优化共同日前购电，上/下备用均固定为零。
模型保留线性电网、固定流节点法、完整未来轨迹补救，不包含交流损耗、水压或CHP启停。
完整过程预算600秒，独立验算与KKT结果分别保存。

开发探针`r9-reserve-nominal-20260921-v1`已完成：费用373718.305522 CNY，
模型与KKT通过，含导入、保存与重读约49.55秒。输入哈希为
`180ce14ba015198654a5af096172b4b6959b7fe6b029860631258779a39eac6a`。
这证明本替代输入下存在无备用的全天基准，不证明任何备用容量可以交付。
40项原始科研文件无损封存为45项分片/辅助载体，目录为`results/summaries/r9-reserve-nominal-20260921-v3/`，
可在没有原运行目录的情况下只读重验：

```sh
julia +1.12.6 --startup-file=no --project=. results/summaries/r9-reserve-nominal-20260921-v3/audit-source.jl check results/summaries/r9-reserve-nominal-20260921-v3
```

初版未分片记录超过仓库单文件5MiB限制；v2已分片但有Julia1.12动态绑定警告，
v3在读取冻结绑定时使用最新世界龄。旧载体保留本地，原输入、数值和乘子不变，未重跑实验。

正式100情景比较仍需先冻结：训练/验证/测试划分、调用信号与不确定域、距离和半径，
以及3A要求的严格交付。当前模板`delta=0.1`不是“100%响应”保证；无备用探针因容量总和为零，
其误差预算也为零。三方案比较须说明是否统一采用严格交付或将交付规则列为单独因素。
尚不报告3A/3B/3C排序、样本外可靠率或作者同输入复现。
原PDF93的式（5-70）对应建筑与时段的联合舒适事件，5%风险阈值与交付误差`delta`是两项不同约束。
有限支持上的概率扰动，也不能自动保证未出现过的任意24小时调用轨迹均可交付。

原式边界、符号与未决问题见[台账索引](ch07-reserve-generated.md)。

```@index
Pages = ["ch07-reserve.md"]
```

```@docs
r9_reserve_template
audit_r9_reserve_input
```
