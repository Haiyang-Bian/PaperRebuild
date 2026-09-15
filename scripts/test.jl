using Pkg

VERSION == v"1.12.6" || error("Expected Julia 1.12.6")
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.test(; julia_args = ["--startup-file=no", "--threads=1"])
