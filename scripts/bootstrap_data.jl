# 第3章数据工具独立环境，不改变科研模型和全局 Julia 默认版本。
using Pkg
VERSION == v"1.12.6" || error("Expected Julia 1.12.6")
Pkg.activate(joinpath(@__DIR__, "..", "tools", "data"))
Pkg.instantiate()
