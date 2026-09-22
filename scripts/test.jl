using Pkg

VERSION == v"1.12.6" || error("Expected Julia 1.12.6")
Pkg.activate(joinpath(@__DIR__, ".."))
ARGS in (String[], ["r1_r4"], ["r5_r6"], ["r7_r9"], ["r7_r8"], ["r9_physics"], ["r9_markets"]) ||
    error(
        "usage: test.jl [r1_r4|r5_r6|r7_r8|r9_physics|r9_markets|r7_r9]; no argument runs every test",
    )
Pkg.test(; julia_args = ["--startup-file=no", "--threads=1"], test_args = copy(ARGS))
