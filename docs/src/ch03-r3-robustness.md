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
