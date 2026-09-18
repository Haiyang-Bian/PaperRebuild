# [API 索引与说明](@id api-reference)

点击索引中的名称可跳到相应条目。每张卡片由当前 Julia 源码中的 **docstring** 自动生成，
展示调用签名、用途、输入输出、单位和适用限制；详细物理解释见 [第 2 章模型说明](@ref ch02-models)
与[第 3 章模型及补全](@ref ch03-models)。

```@index
Pages = ["api.md"]
Modules = [PaperRebuild]
Order = [:type, :function]
```

## 案例数据与输入

输入契约与原始参数缺口见 [R1 运行教程](@ref ch02-status)。本批只接收明确标记的合成案例。

```@docs
PaperRebuild.R1Case
PaperRebuild.load_case
```

## 设备模型

对应 [CHP](@ref eq-ch02-001)、[光伏](@ref eq-ch02-005)、[风电原式疑点](@ref eq-ch02-007)、
[电池](@ref eq-ch02-012) 和 [热储能](@ref eq-ch02-016)。风电诊断函数不代表风电调度模型已经实现。

```@docs
PaperRebuild.chp_heat
PaperRebuild.chp_efficiency
PaperRebuild.pv_available
PaperRebuild.wind_ramp_paper
PaperRebuild.battery_step
PaperRebuild.heat_storage_step_paper
```

## 建筑温控

对应 [建筑温度状态式](@ref eq-ch02-072)；离散系数必须与时间步长匹配。

```@docs
PaperRebuild.building_step
```

## 网络与单位换算

对应 [热交换](@ref eq-ch02-029)、[混合温度](@ref eq-ch02-042)、
[热传输节点法](@ref eq-ch02-047) 和 [支路潮流](@ref eq-ch02-024)。

```@docs
PaperRebuild.heat_power
PaperRebuild.mix_temperature
PaperRebuild.fixed_flow_kernel
PaperRebuild.pipe_outlet
PaperRebuild.electrical_bases
```

## 建模、求解与独立验证

这三个步骤分别负责建立约束、取得数值结果、重算物理关系；
公式与验证位置见 [实现与测试映射](@ref ch02-source)。

```@docs
PaperRebuild.build_r1_model
PaperRebuild.solve_r1_case
PaperRebuild.validate_r1_solution
```

## 运行记录与绘图

运行数据格式和 F01–F04 见 [运行教程与验收状态](@ref ch02-status)。

```@docs
PaperRebuild.save_r1_run
PaperRebuild.read_r1_run
PaperRebuild.plot_r1_run
```

## 第3章模型与独立回代

模型、补全边界与公式见[第3章解释](@ref ch03-models)，运行见[R2教程](@ref ch03-r2)。

```@docs
PaperRebuild.R2Case
PaperRebuild.R2Spec
PaperRebuild.load_r2_case
PaperRebuild.water_mass_weights
PaperRebuild.replay_water_mass
PaperRebuild.mccormick_bounds
PaperRebuild.build_r2_model
PaperRebuild.r2_model_class
PaperRebuild.solve_r2_case
PaperRebuild.validate_r2_solution
PaperRebuild.save_r2_run
PaperRebuild.read_r2_run
PaperRebuild.compare_r2_runs
PaperRebuild.plot_r2_run
```

## 第3章可行性闭环

```@docs
PaperRebuild.reconstruct_r3_pressure
PaperRebuild.build_r3_subproblem
PaperRebuild.repair_r3_flow
PaperRebuild.solve_r3_feasibility
PaperRebuild.validate_r3_solution
PaperRebuild.save_r3_run
PaperRebuild.read_r3_run
PaperRebuild.plot_r3_run
```

## 第3章灵敏度与外层

```@docs
PaperRebuild.r3_transport_jacobian
PaperRebuild.r3_value_sensitivity
PaperRebuild.build_r3_projection
PaperRebuild.solve_r3_projected_gradient
PaperRebuild.validate_r3_iteration
PaperRebuild.R3OperationSpec
PaperRebuild.r3_boundary_case
PaperRebuild.R3BaselineSpec
PaperRebuild.solve_r3_baseline
PaperRebuild.compare_r3_baselines
PaperRebuild.build_r3_local_step
PaperRebuild.solve_r3_reference
PaperRebuild.compare_r3_modes
PaperRebuild.audit_r3_failure
PaperRebuild.r3_stopping_evidence
PaperRebuild.build_r3_physical_step
```

## 第4章集中交易与核算

```@docs
PaperRebuild.R4Case
PaperRebuild.R4Spec
PaperRebuild.load_r4_case
PaperRebuild.build_r4_model
PaperRebuild.solve_r4_case
PaperRebuild.validate_r4_solution
PaperRebuild.r4_ledger
PaperRebuild.r4_preferred_demand
PaperRebuild.r4_coordination_surplus
PaperRebuild.r4_nash_allocation
PaperRebuild.validate_r4_allocation
PaperRebuild.r4_bargaining_weights
PaperRebuild.r4_allocate_coordination
PaperRebuild.R4TSPASpec
PaperRebuild.r4_tspa_scales
PaperRebuild.solve_r4_tspa
PaperRebuild.validate_r4_trading
PaperRebuild.validate_r4_elastic
PaperRebuild.validate_r4_tspa
PaperRebuild.save_r4_tspa_run
PaperRebuild.read_r4_tspa_run
PaperRebuild.R4DistributedSpec
PaperRebuild.build_r4_distributed_block
PaperRebuild.solve_r4_distributed
PaperRebuild.validate_r4_distributed
PaperRebuild.save_r4_distributed_run
PaperRebuild.read_r4_distributed_run
PaperRebuild.r4_battery_patterns
PaperRebuild.reconstruct_r4_cost
PaperRebuild.solve_r4_discrete
PaperRebuild.validate_r4_discrete
PaperRebuild.save_r4_discrete_run
PaperRebuild.read_r4_discrete_run
PaperRebuild.save_r4_run
PaperRebuild.read_r4_run
PaperRebuild.compare_r4_runs
PaperRebuild.plot_r4_run
```

## 工程示例函数说明

以下两个函数保留自初始化模板，只用于验证包加载、测试和 Documenter 集成，不计入论文复现进度。

```@docs
PaperRebuild.hello
PaperRebuild.domath
```

```jldoctest
julia> using PaperRebuild

julia> PaperRebuild.hello("Julia")
"Hello, Julia"

julia> PaperRebuild.domath(2)
7
```
