# 循环、闲置与温度相关散热

## 为什么需要新版本

[上一批相容性核查](ch04-heat-results.md)留下8项开放交易反例：闲置叶支路被要求持续散热，
却没有符合端口温差和质量守恒的循环去向。新版本r4_thermal_checked_v1将阀门连通、
实际运行和温度分开建模，并重新优化设备与热交付。它不改写旧运行。

这是一项项目扩展：论文PDF66–67、(4-41)–(4-48)仍保留原式；
日阀门连通树保留，实际流量允许在某时段停止。采用方程与定义见[公式和符号](ch04-thermal-equations.md)。

## 一条管道的推导

单位长度管壁向环境散热为U(T-Ta)，稳态水流携带的焓差为m cp dT。
沿长度积分得到指数温降。输入使用kg/s、J/(kg K)、W/(m K)、m和K，
结果热损耗除以10^6转换为MW；供回水两根管道分别计算，不能只算一侧。

~~~math
T^{out}-T_a=(T^{in}-T_a)\exp[-UL/(c_pm)].
\tag{R4-T2a}
~~~

例如入口353.15K、环境283.15K、流量1kg/s、UL=18W/K，比热4180J/(kg K)。
调用[r4_steady_pipe](@ref PaperRebuild.r4_steady_pipe)可算出口温度和MW损耗。
U=0时无温降；大流量极限的热损耗趋于UL(Tin-Ta)，这两个极限均有解析测试。
零流量不使用上述表达式，避免将除零或管内冷却解释为输运。

## 本版本包含什么

- reference：运行弧计入参考供回温冻结损耗，但加入完整稳态温度、端口和混合。
- exponential：运行弧损耗随实际入口温度和流量变化。
- 两版本都将设备出力、热负荷、逐管热量和流量联合优化，费用仍含原资源、购电、不满意度及开关动作。
- 原电网等式与SOCP显式选择，松弛回代状态单列；不将非凸热模型称MISOCP。

两版本都采用**独立稳态时段**：闲置弧没有热量输运，温度变量只作占位。
本批没有管内储热及停流冷却方程，因而不认证停流/重启过程或周期总能量。
不引入未声明旁通；未计算水压和泵耗，质量流改变不代表实际工程代价为零。

## Julia入口与验证

[build_r4_thermal](@ref PaperRebuild.build_r4_thermal)只构建模型，
[solve_r4_thermal](@ref PaperRebuild.solve_r4_thermal)在共享预算下求解，
[validate_r4_thermal](@ref PaperRebuild.validate_r4_thermal)用保存的K/kg/s/MW重新计算。
存档仍使用[save_r4_run](@ref PaperRebuild.save_r4_run)和[read_r4_run](@ref PaperRebuild.read_r4_run)。
输入哈希不变，新模型、温度带、循环与固定流量计划另行记录。

固定流量时双线性温度关系变成仿射式，指数衰减变成常数；
进一步固定离散量并选SOCP，可以用Clarabel核对手算和闲置支路特例。
流量可变时由Gurobi处理非凸关系，独立A1及有效界仍决定结果能支持什么。
[JuMP非线性建模接口](https://jump.dev/JuMP.jl/stable/manual/nonlinear/)支持原生约束表达；
实际类型在每次运行中保存。

~~~powershell
julia +1.12.6 --startup-file=no --project=. scripts/test_r4_thermal.jl
julia +1.12.6 --startup-file=no --project=. scripts/test_r4_thermal.jl --gurobi
julia +1.12.6 --startup-file=no --project=. scripts/check_r4_thermal.jl
~~~

本页是模型与操作说明；正式实验结果须在冻结输入/源码后另行生成，不能由单元测试代替。
