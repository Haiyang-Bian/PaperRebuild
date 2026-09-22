using PaperRebuild, TOML
include("r8_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r8.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/r8-tradeoff.toml"))
for k in ("source_fact", "equation", "symbol")
    ids=[x["id"] for x in d[k]]
    length(ids)==length(unique(ids)) || error("R8台账ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"])) &&
    occursin(e["test"], read(joinpath(root, e["test_file"]), String)) || error("R8映射缺失")
end
page=joinpath(root, "docs/src/ch06-r8-equations.md")
"--sync" in ARGS && write(page, r8_markdown(root))
read(page, String)==r8_markdown(root) || error("R8生成页失步")
println(
    "R8: ",
    length(d["source_fact"]),
    " original-page records, ",
    length(d["equation"]),
    " adopted equations, ",
    length(d["symbol"]),
    " symbol groups checked.",
)
