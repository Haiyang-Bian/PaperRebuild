using PaperRebuild, JuMP, SHA
include("r7_planning_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_planning.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
"--sync" in ARGS && sync_r7_planning_docs(root)
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/planning.toml"))
for key in ("original_equation", "equation", "finding", "symbol")
    ids=[e["id"] for e in d[key]]
    length(ids)==length(unique(ids)) || error("规划台账ID重复")
end
tests=read(joinpath(root, "test/r7_planning.jl"), String)
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"]))&&occursin(e["test"], tests) ||
        error("规划公式-API-测试失步")
end
freeze=TOML.parsefile(joinpath(root, "configs/r7/reserve-hand-freeze.toml"))
for (p, hash) in freeze["files"]
    bytes2hex(sha256(read(joinpath(root, p))))==hash || error("解析配置被修改")
end
c=load_r7_planning_case(
    joinpath(root, "configs/r7/normal-reserve-hand.toml"),
    joinpath(root, "configs/r7/planning-reserve-hand.toml"),
)
b=build_r7_planning(c)
length(b.recovery)==4&&b.model_class=="MILP" || error("实际规划覆盖或模型类型改变")
read(joinpath(root, "docs/src/ch06-planning-equations.md"), String)==r7_planning_markdown(root) ||
    error("规划生成页失步")
println(
    "R7 finite planning: 4 source formulas, 5 derivations, 4 findings, 4 symbol groups; prescribed normal domain; native-indicator oracle checked separately.",
)
