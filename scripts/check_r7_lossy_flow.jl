using PaperRebuild, TOML
include("r7_lossy_flow_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_lossy_flow.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/lossy-flow.toml"))
parent=TOML.parsefile(joinpath(root, d["reference_entry"]))
all(id in [e["id"] for e in parent["equation"]] for id in d["reference_ids"]) || error("有损参考推导缺失")
for k in ("equation", "symbol")
    ids=[x["id"] for x in d[k]]
    length(ids)==length(unique(ids)) || error("有损台账ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"])) &&
    occursin(e["test"], read(joinpath(root, e["test_file"]), String)) ||
        error("有损API/测试映射缺失")
end
page=joinpath(root, "docs/src/ch06-lossy-flow-equations.md")
"--sync" in ARGS && write(page, r7_lossy_flow_markdown(root))
read(page, String)==r7_lossy_flow_markdown(root) || error("有损生成页失步")
println(
    "R7 lossy transport: ",
    length(d["reference_ids"]),
    " reference derivations, ",
    length(d["equation"]),
    " equations and ",
    length(d["symbol"]),
    " symbol groups checked.",
)
