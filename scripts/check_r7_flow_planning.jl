using PaperRebuild, TOML
include("r7_flow_planning_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_flow_planning.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
page=joinpath(root, "docs/src/ch06-flow-planning-equations.md")
"--sync" in ARGS&&write(page, r7_flow_planning_markdown(root))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/flow-planning.toml"))
original=TOML.parsefile(joinpath(root, d["original_entry"]))
all(id->id in [e["id"] for e in original["original_equation"]], d["original_ids"]) || error("原式链接缺失")
for key in ("equation", "symbol")
    ids=[e["id"] for e in d[key]]
    length(ids)==length(unique(ids)) || error("联合台账ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(
        e["test"],
        read(joinpath(root, e["test_file"]), String),
    ) || error("联合流量API/测试缺失")
end
read(page, String)==r7_flow_planning_markdown(root) || error("联合流量文档生成页失步")
println("R7 joint flow: 3 original references, 4 adopted equations, 3 symbol groups checked.")
