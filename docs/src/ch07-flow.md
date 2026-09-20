# R9：变流量输运与周期记忆

本页接续[固定模式结果](ch07-numerics.md)。当前完成连续流量建模接口与组件验证，
**尚未取得R9变流量合格调度，也尚未迁移作者投影梯度**。旧模型、锚定结果及失败记录保持。

## 1. 为什么可以消去WMM的互补变量？

本批冻结管道长度为600 m，按参考流速1 m/s设计截面，时间步为3600 s，
流量下界为参考流量的0.6倍。因此，管内水质量与最少单步输送质量之比为
``600/(3600\times0.6)=1/3.6``。对全部37根管及冻结历史分别核验后，
整个允许流量盒都落在同一WMM分段，消元不需要缩小控制范围。

令``q_p=M_p/\Delta t_s``。当``q_p<\min(m_{p,t},m_{p,t-1})``时，原质量覆盖式给出：

```math
\begin{aligned}
\alpha_{p,t,0}&=q_p/m_{p,t}, & \alpha_{p,t,s\ge1}&=0,\\
\beta_{p,t,0}&=1, &\beta_{p,t,1}&=q_p/m_{p,t-1},\quad
\beta_{p,t,s\ge2}=0.
\end{aligned}
\tag{R9-V1}
```

回代式（3-33），前步流量在温度权重中抵消，但前步**温度**仍不可省略：

```math
T^*_{p,t}=\left(1-\frac{q_p}{m_{p,t}}\right)T^{in}_{p,t}
 +\frac{q_p}{m_{p,t}}T^{in}_{p,t-1}.
\tag{R9-V2}
```

这不是整数时延近似。它只适用于上述严格分段；等号或跨段输入明确拒绝。
输入盒证据由[`audit_r9_flow_domain`](@ref)生成，核对版WMM仍是物理依据。

## 2. 前步流量没有从损耗中消失

```math
\begin{aligned}
a_{p,t}&=\exp\!\left[-\frac{\epsilon_pL_p}{2c_p}
\left(\frac1{m_{p,t}}+\frac1{m_{p,t-1}}\right)\right],\\
T^{out}_{p,t}&=T^a_t+(T^*_{p,t}-T^a_t)a_{p,t},\\
\frac{\partial a_{p,t}}{\partial m_{p,t}}&=
\frac{a_{p,t}\epsilon_pL_p}{2c_pm_{p,t}^2},\qquad
\frac{\partial a_{p,t}}{\partial m_{p,t-1}}=
\frac{a_{p,t}\epsilon_pL_p}{2c_pm_{p,t-1}^2}.
\end{aligned}
\tag{R9-V3}
```

``\epsilon``用W/(m K)，``c_p``用J/(kg K)，指数无量纲。首时段的前步流量来自冻结历史，
其导数不会变成决策变量。后续时段必须保留跨时段导数；这里只验证输运系数，
不将它当作已经认证的网络最优值梯度。

## 3. 周期边界同时恢复什么？

```math
m_{p,T}=m^{hist}_{p,0},\qquad
T^{S,in}_{p,T}=T^{S,hist}_{p,0},\qquad
T^{R,in}_{p,T}=T^{R,hist}_{p,0}.
\tag{R9-V4}
```

在本单步分段内，三者一起恢复下一时段WMM需要的历史状态。单独恢复温度时，
改变末端流量仍会通过式（R9-V3）改变下一时段出口；测试使用独立累计质量回放检查该反例。
这不是连续管内温度场、PDE或任意长管周期状态的证明。

此入口暂保留**字面终端等式**，没有按每个新流量重新锚定旧参考源温。
[此前发现的浮点不相容](ch07-numerics.md)仍是下一步数值研究的边界，
不能因存在容差内的固定模式嵌入就宣称严格字面模型已经闭合。

## 4. Julia接口与验收边界

```julia
domain = audit_r9_flow_domain(case)
model = build_r9_flow_model(case; mode=:VF_VT)
fixed = build_r9_flow_model(case; mode=:VF_VT, flow_schedule=given_flow)
```

构建不运行优化器。CF与显式给定流量下，热关系使用数值系数，模型类别可核查为SOCP；
自由VF保留精确热功率、混合、损耗关系，为非凸模型，不能叫MISOCP。
`physical=true`另恢复原电网及水压辅助量等式。旧接口默认行为不变。

`test/r9_flow.jl`检查整个盒、通用WMM及解析Jacobian对照、三个递减差分步长、
量纲缩放、分段拒绝、末端反例和已有原物理候选的四模式嵌入。
固定候选只用于检查集合包含关系；不会将其优化费用算成VF收益或作者PG成功。
权威方程、符号、单位和映射位于`docs/reading/ch07/flow.toml`。

```sh
julia +1.12.6 --startup-file=no --project=. scripts/test_r9_flow.jl
```

下一步先核验连续变流量模型的数值表现，冻结一致的终端解释，再执行同输入四模式对照。
在此之前，不将固定流量的0.381%推广成变流量收益，也不据此解释作者全部收益。

## 5. 开发探针说明了什么？

五次预先冻结输入与源码的VF-VT原物理直接参考探针，均使用120秒预算：

| 对照 | 初值日志 | 末次求解器原始残差指标 | 终止与候选 |
|---|---|---:|---|
| 全局默认路径 | 未确认载入 | 未提供 | 限时，无候选 |
| 局部路径初版 | 忽略 | 0.0288 | 迭代上限，无候选 |
| 完成原生模型更新 | 不完整 | 0.0347 | 迭代上限，无候选 |
| 补齐转换辅助量 | 确认载入 | 0.00883 | 迭代上限，无候选 |
| 再去掉被原等式蕴含的锥 | 确认载入 | 1.07×10⁻⁹ | 迭代上限，无候选 |

后四项均进行了1000次局部迭代，总耗时约30–38秒；这是求解器迭代限制，未用完共享预算。
表中指标是求解器自己的缩放量，**不替代A1、独立输运回放或最优性验收**。
没有保存的候选，日志中的费用不能计作可实施收益；这些记录也不是物理不可行证明。

初值修正补齐了1776个固定辅助量和9456个由线性等式确定的辅助量，
原21576个JuMP变量的数值不变。新增脚本回读全部32808个底层初值，日志另确认实际载入。
完整载入后仍失败，说明初值缺失并非全部原因。

### 5.1 为什么原等式模型可以删除这两类锥？

仅在原等式存在并保留符号边界时，有以下蕴含关系：

```math
\begin{aligned}
v>0,\ \ell\ge0,\quad v\ell=P^2+Q^2
&\Longrightarrow v+\ell\ge\|(2P,2Q,\ell-v)\|_2,\\
\kappa\ge0,\ \mu\ge0,\quad\kappa=\mu m^2
&\Longrightarrow \kappa+1\ge\|(2\sqrt{\mu}m,\kappa-1)\|_2.
\end{aligned}
\tag{R9-D1}
```

第一行两侧平方差为``4(v\ell-P^2-Q^2)=0``，第二行为``4(\kappa-\mu m^2)=0``。
非负边界保证平方前后方向一致；反例测试证明省掉符号边界会破坏该推导。
对照只删除1032个式（3-12）和1776个式（3-26）锥，保留设备、电热关系、原等式和所有边界。
浮点``sqrt(\mu)^2``与``\mu``的微小差异另记全流量盒界，本例不超过5.10×10⁻¹⁴ kPa。
这不是新的物理恢复算法，也不改变旧建模入口的默认行为。

这一对照支持**冗余表示参与了数值困难**；尚不足以断言已经解除全部困难或取得调度。
另一次本地开发检查使用``T=333.15+80\theta``的可逆坐标变换，输入和全部温区不变；
初值处新旧约束函数最大差约1.48×10⁻¹²，局部求解仍停在相同的1.07×10⁻⁹指标，未返回候选。
该附加探针未混入下述五项冻结对照，说明单独平移/归一化温度还不能解除当前停滞。
下一步须取得可逐约束审计的数值输出，核查终端相容与数值停止，不继续用日志费用作比较。

局部非线性路径显式使用`OptimalityTarget=1`与`PStart`，与全局求解路径分别保存。
初值属性与模型更新要求依据[Gurobi官方说明](https://docs.gurobi.com/projects/optimizer/en/current/features/warmstart.html)。
已有固定模式合格调度只作独立参考的声明初值；没有进入投影梯度或被计为新的变流量结果。

证据在`results/summaries/r9-flow-diagnostics-20260921-v2/`；输入、29个科学源码文件和原始状态逐字节保存。
公开日志仅隐去本机路径与许可标识，索引同时记录原日志和公开副本哈希。旧失败结果不改写。

```sh
# 不需要Gurobi许可，只读核验来源、状态及比较表
julia +1.12.6 --startup-file=no --project=. scripts/r9_flow_diagnostics.jl check results/summaries/r9-flow-diagnostics-20260921-v2
# 可选商用专项，不执行科研优化
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/test_r9_gurobi_start.jl
# 新开发探针；输出目录必须尚不存在
julia +1.12.6 --startup-file=no --project=tools/solvers scripts/r9_flow_probe.jl results/runs/r9-flow-probe-new VF_VT true 120 local drop_implied_cones
```

```@index
Pages = ["ch07-flow.md"]
```

```@docs
r9_transport_coefficients
audit_r9_flow_domain
build_r9_flow_model
r9_flow_terminal_rows
```
