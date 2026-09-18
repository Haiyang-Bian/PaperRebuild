# 重构采用式与符号

<!-- Generated from docs/reading/ch04/network.toml. -->

## R4-N1：全节点连通树

```math
\sum_e u_{e,t}=|N|-1,\quad -( |N|-1)u_{e,t}\le F_{e,t}\le(|N|-1)u_{e,t},\quad \sum_{\delta^+(i)}F-\sum_{\delta^-(i)}F=\begin{cases}|N|-1&i=1\\-1&i\ne1\end{cases}\tag{R4-N1}
```

项目采用单根、全节点连通；不是孤岛供能模型。虚拟流不等于物理方向。

API：[build_r4_reconfiguration](@ref PaperRebuild.build_r4_reconfiguration)；测试：R4 network reconfiguration。

## R4-N2：电开路与电压降

```math
|v_j-v_i+2(rP+xQ)-(r^2+x^2)\ell|\le(v_{\max}-v_{\min})(1-u^E),\quad |P|\le P^{\max}u^E,\quad |Q|\le Q^{\max}u^E,\quad0\le\ell\le\ell^{\max}u^E\tag{R4-N2}
```

此处v_min/v_max为电压平方边界。断开时P/Q/ell为零，因此M等于平方电压跨度足够。

API：[build_r4_reconfiguration](@ref PaperRebuild.build_r4_reconfiguration)；测试：R4 network reconfiguration。

## R4-N3：动作与稳定窗口

```math
a^E_{e,t}=|u^E_{e,t}-u^E_{e,t-1}|,\quad \sum_{k=\max(1,t-d+1)}^t a^E_{e,k}\le1,\quad\sum_ta^E_{e,t}\le A_e^{\max}\tag{R4-N3}
```

用四个线性不等式精确实现二元异或；初始此前d-1步稳定，尾端不加周期恢复。

API：[validate_r4_reconfiguration](@ref PaperRebuild.validate_r4_reconfiguration)；测试：R4 network reconfiguration。

## R4-N4：日阀门与逐时热方向

```math
d^+_{p,t}+d^-_{p,t}=u^H_p,\quad 0\le(m,H^{in},H^{out})^\pm\le(M,H^{\max},H^{\max})d^\pm,\quad H^{out,\pm}=H^{in,\pm}-L_p d^\pm\tag{R4-N4}
```

每条物理管道只在一个方向计损耗；反向弧交换端点，实际能量和质量均非负。L来自既有SI冻结损耗。

API：[build_r4_reconfiguration](@ref PaperRebuild.build_r4_reconfiguration)；测试：R4 network reconfiguration。

## R4-N5：资源与动作成本

```math
C=C_{\rm resource}+C_{\rm grid}+C_{\rm discomfort}+c^{SA}\sum_{e,t}a^E_{e,t}+c^{VA}\sum_p|u^H_p-u^H_{p,0}|\tag{R4-N5}
```

动作按美元/次，无额外Δt；由运营商承担，内部支付仍抵消。不是新收费转移带来的收益。

API：[solve_r4_reconfiguration](@ref PaperRebuild.solve_r4_reconfiguration)；测试：R4 network reconfiguration。

## R4-N6：有限枚举参照

```math
C^*=\min_{z\in\mathcal Z}C_z^*,\qquad L=\min_{z\in\mathcal Z}L_z,\qquad U=\min_{z\in\mathcal Z_{\rm feasible}} C_z\tag{R4-N6}
```

仅全部状态均有有效界或不可行证明时给并集证书。当前单时段为3电树×3热树×4热方向×2电池模式。

API：[enumerate_r4_reconfiguration](@ref PaperRebuild.enumerate_r4_reconfiguration)；测试：R4 network reconfiguration。

## 符号

|稳定ID|符号|含义|Julia|单位|定义域|
|---|---|---|---|---|---|
|r4-network-uE|``u^E_{e,t}``|电线路闭合状态|`u_E[e,t]`|1|binary|
|r4-network-uH|``u^H_p``|物理热管日阀门开启状态|`u_H[p]`|1|binary|
|r4-network-aE|``a^E_{e,t}``|相对上一时段的电开关动作|`a_E[e,t]`|1|binary by exact XOR|
|r4-network-dH|``d^\pm_{p,t}``|正/反方向热输运状态|`u_H_arc[p,t], u_H_arc[p+3,t]`|1|binary|
|r4-network-F|``F^E_{e,t}, F^H_p``|虚拟连通商品流，不是物理流量|`F_E[e,t], F_H[p,1]`|1|real|

## 原式疑点与采用解释

### R4-NC01

4-29用u而文字u=1为闭合。

证据：断开u=0且P=Q=ell=0时原式强制两侧电压相等；闭合反允许电压降松弛。

采用：改用(1-u)，独立N2；旧原式与历史结果保留。

### R4-NC02

4-35/36、4-49/50的索引约定有冲突；仅父数上界不能保证连通。

证据：根孤立，其余三个节点形成环时仍可满足每节点最多一个父节点。

采用：显式N1；全节点连通是本批建模边界。

### R4-NC03

4-38/39对闭合状态u求和，4-40却用方向z表达动作。

证据：d=2、持续闭合u=1且无动作a=0会产生2<=1反例。方向变化也不必是物理开关动作。

采用：按文字动作意图建立N3；动作间隔2步、每线最多2次为冻结项目参数。

### R4-NC04

4-47/48、PDF67文字给整日热阀门；能量流允许带符号，固定损耗须随实际方向处理。

证据：直接把负的Hin/Hout代入正损耗式会颠倒输入/输出能量。

采用：N4正反弧互斥，虚拟连通与实际热方向分离；非完整热水力模型。

### R4-NC05

4-33原页锥中为v_n,t；原4-27与支路发送端电流平方关系采用v_m,t。

证据：PDF66视觉复核；既有台账此前已用发送端规范化，但未单独注明这个下标差异。

采用：保留发送端采用式与旧结果；另记原页差异，不静默更改物理实现。
