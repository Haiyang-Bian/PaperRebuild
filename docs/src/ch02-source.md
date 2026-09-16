```@raw html
<!-- GENERATED: scripts/ch02_docs.jl; edit docs/reading/ch02 and current Julia sources. -->
```

# [实现与测试映射](@id ch02-source)

函数签名、参数、单位和适用范围统一读取 [API docstring](@ref api-reference)。本页只登记公式、源码位置和测试名称，便于回到项目定位。

### [chp_heat](@id source-eq-ch02-001)

API：[`chp_heat`](@ref)。

对应公式：[式（2-1）](@ref eq-ch02-001)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-001`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

### [build_r1_model](@id source-r1-model)

API：[`build_r1_model`](@ref)。

对应公式：[式（2-2）](@ref eq-ch02-002)、[式（2-3）](@ref eq-ch02-003)、[式（2-6）](@ref eq-ch02-006)、[式（2-8）](@ref eq-ch02-008)、[式（2-9）](@ref eq-ch02-009)、[式（2-10）](@ref eq-ch02-010)、[式（2-11）](@ref eq-ch02-011)、[式（2-13）](@ref eq-ch02-013)、[式（2-14）](@ref eq-ch02-014)、[式（2-15）](@ref eq-ch02-015)、[式（2-17）](@ref eq-ch02-017)、[式（2-18）](@ref eq-ch02-018)、[式（2-19）](@ref eq-ch02-019)、[式（2-20）](@ref eq-ch02-020)、[式（2-21）](@ref eq-ch02-021)、[式（2-22）](@ref eq-ch02-022)、[式（2-23）](@ref eq-ch02-023)、[式（2-24）](@ref eq-ch02-024)、[式（2-26）](@ref eq-ch02-026)、[式（2-27）](@ref eq-ch02-027)、[式（2-28）](@ref eq-ch02-028)、[式（2-30）](@ref eq-ch02-030)、[式（2-31）](@ref eq-ch02-031)、[式（2-33）](@ref eq-ch02-033)、[式（2-34）](@ref eq-ch02-034)、[式（2-44）](@ref eq-ch02-044)、[式（2-45）](@ref eq-ch02-045)、[式（2-73）](@ref eq-ch02-073)、[式（2-74）](@ref eq-ch02-074)、[式（2-75）](@ref eq-ch02-075)、[式（2-76）](@ref eq-ch02-076)。

源码定位：`src/formulations/r1.jl`，标记 `r1-model`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

### [chp_efficiency](@id source-eq-ch02-004)

API：[`chp_efficiency`](@ref)。

对应公式：[式（2-4）](@ref eq-ch02-004)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-004`。

验证：`R1-devices ch02-001:019 ch02-072:076`（`test/r1.jl`）。

### [pv_available](@id source-eq-ch02-005)

API：[`pv_available`](@ref)。

对应公式：[式（2-5）](@ref eq-ch02-005)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-005`。

验证：`R1-devices ch02-001:019 ch02-072:076`（`test/r1.jl`）。

### [battery_step](@id source-eq-ch02-012)

API：[`battery_step`](@ref)。

对应公式：[式（2-12）](@ref eq-ch02-012)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-012`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

### [heat_storage_step_paper](@id source-eq-ch02-016)

API：[`heat_storage_step_paper`](@ref)。

对应公式：[式（2-16）](@ref eq-ch02-016)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-016`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

### [validate_r1_solution](@id source-r1-validate)

API：[`validate_r1_solution`](@ref)。

对应公式：[式（2-25）](@ref eq-ch02-025)。

源码定位：`src/verification/r1.jl`，标记 `r1-validate`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

### [heat_power](@id source-eq-ch02-029)

API：[`heat_power`](@ref)。

对应公式：[式（2-29）](@ref eq-ch02-029)、[式（2-32）](@ref eq-ch02-032)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-029`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

### [mix_temperature](@id source-eq-ch02-042)

API：[`mix_temperature`](@ref)。

对应公式：[式（2-42）](@ref eq-ch02-042)、[式（2-43）](@ref eq-ch02-043)。

源码定位：`src/networks/fixed_flow_heat.jl`，标记 `eq-ch02-042`。

验证：`R1-pipe ch02-042 ch02-047:054`（`test/r1.jl`）。

### [fixed_flow_kernel](@id source-eq-ch02-047)

API：[`fixed_flow_kernel`](@ref)。

对应公式：[式（2-47）](@ref eq-ch02-047)、[式（2-48）](@ref eq-ch02-048)、[式（2-49）](@ref eq-ch02-049)、[式（2-50）](@ref eq-ch02-050)、[式（2-51）](@ref eq-ch02-051)、[式（2-52）](@ref eq-ch02-052)、[式（2-53）](@ref eq-ch02-053)、[式（2-54）](@ref eq-ch02-054)。

源码定位：`src/networks/fixed_flow_heat.jl`，标记 `eq-ch02-047`。

验证：`R1-pipe ch02-042 ch02-047:054`（`test/r1.jl`）。

### [building_step](@id source-eq-ch02-072)

API：[`building_step`](@ref)。

对应公式：[式（2-72）](@ref eq-ch02-072)。

源码定位：`src/components/devices.jl`，标记 `eq-ch02-072`。

验证：`R1-input and integration ch02-022:028`（`test/r1.jl`）。

## [测试入口](@id tests-r1)

上述测试集保存在 `test/r1.jl`，运行入口为 `scripts/test.jl`。具体判定与实际通过状态见 [本批状态](@ref ch02-status)，原始测试代码保留在项目中。
