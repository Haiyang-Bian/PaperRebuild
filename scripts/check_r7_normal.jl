using PaperRebuild, JuMP
include("r7_normal_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_normal.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
"--sync" in ARGS && sync_r7_normal_docs(root)
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/normal-dispatch.toml"))
for key in ("original_equation", "equation", "finding", "symbol")
    ids=[e["id"] for e in d[key]]
    length(unique(ids))==length(ids) || error("正常台账ID重复")
end
for e in d["equation"]
    tests=read(joinpath(root, get(e, "test_file", "test/r7_normal.jl")), String)
    isdefined(PaperRebuild, Symbol(e["api"])) && occursin(e["test"], tests) ||
        error("正常公式映射失步")
end
c=load_r7_normal_case(joinpath(root, "configs/r7/normal-hand.toml"))
b=build_r7_normal(c)
b.model_class=="MILP" || error("正常条件模型类型改变")
for id in (
    "6-14",
    "6-15",
    "6-18:19",
    "6-26",
    "6-28",
    "R7-D-transport",
    "R7-D-inventory",
    "R7-D-pressure-S",
    "R7-D-pressure-R",
)
    haskey(b.constraints, id) || error("缺实际约束映射：$id")
end
read(joinpath(root, "docs/src/ch06-normal-equations.md"), String)==r7_normal_markdown(root) ||
    error("正常公式生成页失步")
println(
    "R7 conditional normal dispatch: 3 source formulas, 6 derivations, 4 findings, 5 symbol groups; full variable-flow planning remains open.",
)
