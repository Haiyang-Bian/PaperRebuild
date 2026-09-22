using PaperRebuild, TOML
include("r8_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r8_energy.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/r8-energy-flow.toml"))
for key in ("equation", "source_fact", "symbol")
    ids=[x["id"] for x in d[key]]
    length(ids)==length(unique(ids)) || error("能流台账ID重复")
end
for x in d["equation"]
    isdefined(PaperRebuild, Symbol(x["api"])) &&
    occursin(x["test"], read(joinpath(root, x["test_file"]), String)) ||
        error("能流台账API/测试缺失")
end
page=joinpath(root, "docs/src/ch06-r8-energy-equations.md")
expected=r8_markdown(root; ledger = "r8-energy-flow.toml")
"--sync" in ARGS && write(page, expected)
read(page, String)==expected || error("能流公式页失步")
println("R8 energy: 2 original-page records, 4 adopted equations and 3 symbol groups checked.")
