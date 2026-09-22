# 依赖安装/预编译属于环境准备；科学测试仍使用独立Pkg.test及原十分钟时限。
# 调用方使用与Pkg.test一致的check-bounds、depwarn和线程标志，避免冷缓存重复编译。
using Pkg
VERSION == v"1.12.6" || error("Expected Julia 1.12.6")
Pkg.instantiate(; allow_autoprecomp = false)
using PaperRebuild, JuMP, Clarabel, HiGHS, CSV, Test, Tar
println("Test dependencies loaded with bounds checks; no scientific tests executed.")
