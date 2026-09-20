using PaperRebuild, TOML
include("r7_normal_flow_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_normal_flow.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."));
page=joinpath(root, "docs/src/ch06-normal-flow-equations.md")
"--sync" in ARGS && write(page, r7_normal_flow_markdown(root))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/normal-flow.toml"))
for k in ("original_equation", "equation", "symbol")
    ids=[x["id"] for x in d[k]]
    length(ids)==length(unique(ids)) || error("流量台账ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(
        e["test"],
        read(joinpath(root, e["test_file"]), String),
    ) || error("流量API/测试映射缺失")
end
read(page, String)==r7_normal_flow_markdown(root) || error("流量台账生成页失步")
println("Continuous normal flow: 3 original, 6 adopted equations and 3 symbol groups checked.")
