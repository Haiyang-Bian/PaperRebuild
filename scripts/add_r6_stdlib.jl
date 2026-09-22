using Pkg

# R6显式随机流属于Julia标准库；不安装新的优化依赖，也不改变全局Julia版本。
VERSION == v"1.12.6" || error("R6使用Julia 1.12.6")
root = normpath(joinpath(@__DIR__, ".."))
haskey(Pkg.project().dependencies, "Random") || Pkg.add(PackageSpec(name = "Random"))
Pkg.resolve()
for folder in ("docs", joinpath("tools", "solvers"))
    Pkg.activate(joinpath(root, folder))
    Pkg.resolve()
end
Pkg.activate(root)
