using PaperRebuild, TOML
include("r7_transport_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_transport.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."));
page=joinpath(root, "docs/src/ch06-transport-equations.md")
"--sync" in ARGS && write(page, r7_transport_markdown(root))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/transport-recovery.toml"))
tests=read(joinpath(root, "test/r7_transport.jl"), String)
for kind in ("equation", "symbol")
    ids=[r["id"] for r in d[kind]]
    length(ids)==length(unique(ids)) || error("输运映射ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(e["test"], tests) ||
        error("输运API/测试映射错误")
end
read(page, String)==r7_transport_markdown(root) || error("输运文档失步")
println("R7 transport: 3 adopted/derived equations and 3 symbol groups checked.")
