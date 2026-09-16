# [第 2 章 API 导览与手算例](@id ch02-api)

与 [模型详解](@ref ch02-models)、[逐式索引](@ref ch02-generated) 交叉阅读。
原式疑点保持显式边界；API 存在不表示相应整章科学结论已复现。

全部函数的签名和中文 docstring 统一展示在 [API 索引与说明](@ref api-reference)。
下表帮助按研究步骤选择入口；这里的短例用于手算核对。

| 步骤 | API 入口 |
| --- | --- |
| 读取合成案例 | [`R1Case`](@ref)、[`load_case`](@ref) |
| 计算设备关系 | [`chp_heat`](@ref)、[`pv_available`](@ref)、[`battery_step`](@ref)、[`heat_storage_step_paper`](@ref) |
| 计算建筑温度 | [`building_step`](@ref) |
| 热网与单位换算 | [`heat_power`](@ref)、[`mix_temperature`](@ref)、[`fixed_flow_kernel`](@ref)、[`pipe_outlet`](@ref)、[`electrical_bases`](@ref) |
| 建模、求解、核验 | [`build_r1_model`](@ref)、[`solve_r1_case`](@ref)、[`validate_r1_solution`](@ref) |
| 保存、重读、绘图 | [`save_r1_run`](@ref)、[`read_r1_run`](@ref)、[`plot_r1_run`](@ref) |

## 可直接执行的手算例

```jldoctest
julia> using PaperRebuild

julia> chp_heat(0.2, 0.4, 0.1)
0.25

julia> round(battery_step(1.0, 0.4, 0.0, 0.9, 0.9, 0.25); digits=2)
1.09

julia> round(building_step(294.15, 0.11, 283.15, 10.0, 0.1); digits=2)
294.15

julia> k = fixed_flow_kernel(2.0, 1000.0, 0.02, 135.0, 0.25, 0.0);

julia> pipe_outlet([320.0, 330.0], [300.0, 310.0], k, 280.0)
2-element Vector{Float64}:
 305.0
 315.0
```
