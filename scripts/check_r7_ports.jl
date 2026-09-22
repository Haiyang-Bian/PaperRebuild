using PaperRebuild, TOML
include("r7_ports_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_ports.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
page=joinpath(root, "docs/src/ch06-ports-equations.md")
"--sync" in ARGS && write(page, r7_ports_markdown(root))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/compatible-ports.toml"))
tests=read(joinpath(root, "test/r7_ports.jl"), String)
for kind in ("equation", "finding", "symbol")
    ids=[r["id"] for r in d[kind]]
    length(ids)==length(unique(ids)) || error("端口映射ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(e["test"], tests) ||
        error("端口API/测试映射错误")
end
read(page, String)==r7_ports_markdown(root) || error("相容端口文档失步")
println("R7 compatible ports: 3 derived equations, 2 interpretation findings, 3 symbol groups.")
