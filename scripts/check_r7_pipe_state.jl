using PaperRebuild
include("r7_pipe_state_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_pipe_state.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
"--sync" in ARGS && sync_r7_pipe_state_docs(root)
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/pipe-state.toml"))
tests=read(joinpath(root, "test/r7_pipe_state.jl"), String)
for group in ("original_equation", "equation", "symbol")
    ids=[x["id"] for x in d[group]]
    length(ids)==length(unique(ids)) || error("台账ID重复")
end
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(e["test"], tests) ||
        error("API/测试映射缺失")
end
read(joinpath(root, "docs/src/ch06-pipe-equations.md"), String)==r7_pipe_state_markdown(root) ||
    error("生成页失步")
println(
    "R7 pipe reference: original 6-90, four project equations and six symbol groups; no normal-dispatch certification.",
)
