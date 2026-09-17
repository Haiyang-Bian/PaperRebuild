# R3 稳健性与四模式：推导和实施记录

本批增量实现中，尚未完成正式实验，不提前声明整个 R3 完成。

## 1. 对偶最小反例

MOI 最小化约定为

```math
L(x,y)=c^Tx-\sum_i y_i^TF_i(x),\qquad
c-\sum_i A_i^Ty_i=0.\tag{R3-D01}
```

变量固定等式、变量界和锥均必须计入驻点检查；原始乘子不改写。
依据：[MOI 对偶约定](https://jump.dev/MathOptInterface.jl/stable/background/duality/)。

最小例固定 ``m=1``，最小化 ``\kappa``，约束为

```math
a(\kappa+1,2m,\kappa-1)\in\mathcal Q_3,
\quad 0\le\kappa\le10,\quad a\in\{1,1000\}.\tag{R3-D02}
```

活跃情形解析最优值为1、固定流量乘子为2；另固定 ``\kappa=2`` 得到非活跃锥。
2026-09-17 本机八组对照：Clarabel 四组 KKT 通过；Gurobi 活跃锥、1000倍缩放一组
原始目标正确，但不能取得桥接等式的 `Pi`（错误10005），其余三组通过。
这说明原始目标正确不保证对偶可用；尚不能将此前四组坏对偶全部归因于此反例。
工具脚本为 `scripts/diagnose_r3_duals.jl`，完整本地证据为
`results/runs/r3-dual-diagnostic-20260917T082727.toml`。
补充原生属性对照 `results/runs/r3-dual-diagnostic-20260917T085422.toml` 显示，失败组
原生Pi、QCPi和RC均返回10005，而不只是桥接后读不到乘子；因此此最小例不能归因于项目乘子符号转换。
开放测试见 `test/r3_duals.jl`。求解器库未修改，KKT 门槛未放宽。

## 2. 局部方向的推导

固定流量问题可写为 ``F(x,m)=0``。分段内在当前状态作展开：

```math
F(x_0,m_0)+F_x(x_0,m_0)(x-x_0)
+F_m(x_0,m_0)(m-m_0)=0.\tag{R3-L01}
```

固定流量时热关系关于调度变量线性，因此保留原子问题的线性行，加入流量偏导即可。
热功率含 ``m(\tau^S-\tau^R)`` 的两部分导数；混合同时计入总流率和各入流；
WMM质量权重、停留时间及指数损耗均取解析分段导数，历史保持常数。
诊断行还包含流量相关的松弛归一化系数，不能遗漏其导数。

用输入边界跨度归一化流量与温度，冻结分量不进入更新：

```math
\min\ \widehat f(x)+0.01\|d\|_2^2,
\qquad\|d\|_\infty\le\Delta.\tag{R3-L02}
```

系数0.01、信赖域和接受比率是项目数值规则，不冒称作者原式。
此问题同时改变调度变量，所得方向是原始变量局部模型方向；没有可信对偶时不称为最优值梯度。
任何预测改善均须回到详细固定流量子问题重新求解验证。

## 3. 四模式原页核查

已视觉核查 PDF58／印刷页41，第3.4.3节：

```math
m_{jk,t}=\hat m_{jk,t},\quad(j,k)\in\mathcal C,\ t\in\mathcal T.\tag{3-67}
```

```math
\tau^S_{k,t}=\hat\tau^S_{k,t},\quad k\in\mathcal J^S,\ t\in\mathcal T.\tag{3-68}
```

```math
\begin{cases}m_{jk,t}=\hat m_{jk,t},\\
\tau^S_{k,t}=\hat\tau^S_{k,t}.\end{cases}\tag{3-69}
```

分别对应 CF-VT、VF-CT、CF-CT。CT约束对象为热源，不是全网温度。
原文预设流量来自前置优化且保留时间下标；本批采用预先冻结的恒定参考流量，
这是统一比较口径的项目选择。新案例的有界负荷回水与共同恢复尾段同样另行标注。
旧案例和旧运行仍使用原来的固定负荷回水设定。

## 4. Julia 调用与数据冻结

接口：[`R3OperationSpec`](@ref)、[`build_r3_local_step`](@ref)、
[`solve_r3_projected_gradient`](@ref)、[`solve_r3_reference`](@ref)、[`compare_r3_modes`](@ref)。
源码分别在 `src/core/r3_operation.jl`、`src/algorithms/r3_local.jl`、
`src/algorithms/r3_v2.jl`、`src/reporting/r3_modes.jl`；测试在 `test/r3_v2.jl`。

```julia
using PaperRebuild, Clarabel
c = load_r2_case("configs/r3/single-source-four-modes-v1.toml")
operation = R3OperationSpec(c; mode=:CF_CT)
r = solve_r3_projected_gradient(c; algorithm=:r3_pg_checked_v2,
    operation, convex_optimizer=Clarabel.Optimizer)
validate_r3_solution(c, r)
```

完整实验由 `scripts/experiment_r3_v2.jl` 在可选 Gurobi 环境运行。
CF直接进行固定流量调度，外层记录为空；VF显式使用v2，旧调用默认仍为v1。
v2依次尝试可信梯度、一次等价锥缩放重解、原始变量局部方向、必要的邻段真实子问题。
若PG只接受到第8次或更晚的回溯小步、投影梯度仍大，则先尝试局部方向；其失败时保留已检验的小步。
输运切换点明确拒绝局部Taylor方向，先在归一化1e-4、1e-5、1e-6邻域用真实子问题检查邻段。
局部信赖域从0.1开始、失败缩半，实际/预测改善比至少0.1才接受，至少0.75可放大至0.2。
`projected_gradient_norm` 与 `local_direction_norm` 分开保存。
光滑数值停止仍要求连续三次已接受费用变化足够小；局部停止还要求信赖域不活跃及KKT检查通过。
运行达200轮仍可能仅为可行候选，不能改称收敛或全局最优。

每个完整方法共享600秒预算，外层最多540秒，最后预留60秒固定流量原等式调度。
`r3_cost_reference_v1` 是独立的直接最小费用参考，不是PG修正步骤。
VF的固定流量子问题界只约束该固定流量调度，不能充当整个VF问题的下界。

冻结输入在 `configs/r3/*-four-modes-v1.toml`：单源10步（4+6），双源14步（4+10）。
新增光伏峰值按电负荷峰值加电锅炉额定电功率总和的80%计算，为0.44/0.88MW；
核心可用比例为0/0.6/1/0.2，尾段为0。这里电热转换指耗电供热设备EB，CHP不计入耗电容量。
历史由恒流、固定源温度和负荷参考回水的稳态混合/衰减递推得到，构造时检查单位、温度及供热容量。
尾段取最长路径最慢流量历史覆盖的两倍再加2步；独立回放检查末端全部有效记忆的入口、流量与出口。
尾段既计费用，也保留逐时供热与损耗数据，不能用自由终端状态解释储热收益。

### VS Code 和终端入口

```powershell
julia +1.12.6 --project=. scripts/test_r3_v2.jl
julia +1.12.6 --project=tools/solvers scripts/diagnose_r3_duals.jl
julia +1.12.6 --project=tools/solvers scripts/experiment_r3_v2.jl
julia +1.12.6 --project=. scripts/r3_pg_task.jl validate <运行目录>
julia +1.12.6 --project=docs scripts/report_r3_v2.jl <批次study.toml>
```

对应VS Code任务已配置。报告与科学图从保存结果重绘，不重新求解。
F09的热量列是源注热减负荷和独立回放损耗的累计收支，并非恢复出的连续管温分布。

## 5. 当前验证边界

完整热关系偏导已用单源/双源、调度/非零松弛诊断和三个递减差分步长测试。
开发单源v2跑满200轮，局部方向确实参与，保存重读和物理A1通过；这是开发验证，不是正式四模式结论。
开发中发现并修复v2嵌套求解函数复用阶段索引的问题；每轮中心、试探和保存流量都重新检查对应关系。
严格文档构建已通过；最终正式实验与回归证据将在本批结果页登记。
