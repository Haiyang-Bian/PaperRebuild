# Install the three locked environments without changing the global Julia default.
using Pkg

VERSION == v"1.12.6" || error("Use Julia 1.12.6: julia +1.12.6 scripts/bootstrap.jl")
root = normpath(joinpath(@__DIR__, ".."))
for folder in (root, joinpath(root, "docs"), joinpath(root, "tools"))
    Pkg.activate(folder)
    Pkg.instantiate()
end
Pkg.activate(root)
println("Environments ready. This does not run a scientific experiment.")
