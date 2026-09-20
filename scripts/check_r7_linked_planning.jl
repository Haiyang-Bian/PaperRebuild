using PaperRebuild, TOML
include("r7_linked_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_linked_planning.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
page=joinpath(root, "docs/src/ch06-linked-equations.md")
"--sync" in ARGS && write(page, r7_linked_markdown(root))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/linked-planning.toml"))
for group in ("original_equation", "equation", "symbol")
    ids=[x["id"] for x in d[group]]
    length(ids)==length(unique(ids)) || error("空间状态台账ID重复")
end
tests=read(joinpath(root, "test/r7_linked_planning.jl"), String)
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(e["test"], tests) ||
        error("空间状态API/测试映射缺失")
end
read(page, String)==r7_linked_markdown(root) || error("空间状态生成页失步")
println("Linked planning: 4 source equations, 3 adopted relations and 3 symbol groups checked.")
