# Julia 数据工具环境

Julia 1.12.6；CSV、XLSX、JSON用于公开数据导入、预检和任务配置。
与科学模型、绘图、求解器环境分开，根包导入不读取外部文件。

从仓库根目录执行：

```sh
julia +1.12.6 --startup-file=no --project=tools/data scripts/bootstrap_data.jl
julia +1.12.6 --startup-file=no --project=tools/data scripts/collect_ch03_data.jl
julia +1.12.6 --startup-file=no --project=tools/data scripts/validate_ch03_data.jl
julia +1.12.6 --startup-file=no --project=tools/data test/ch03_data.jl
```

默认收集3个已获取的数值来源。`--include-optional` 另尝试文献[25]的PDF，已知下载返回HTTP403。
Google公开导出的ZIP字节可能随服务变化；若SHA不符，明确失败，需检查新文件并登记新版本，不自动接纳。
不需要 MATLAB、Excel、Gurobi 或私人账户登录；不执行工作簿中的代码。
