include("r3_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch03", "r3-baseline-differences.toml"))
length(d["difference"])==10 || error("差异清单缺项")
length(unique(x["id"] for x in d["difference"]))==10 || error("差异ID重复")
for x in d["difference"], key in ("author", "project", "status")
    isempty(x[key]) && error("差异证据缺失")
end
doc=read(joinpath(root, "docs", "src", "ch03-r3-baseline.md"), String)
doc*=read(joinpath(root, "docs", "src", "ch03-r3-baseline-results.md"), String)
for id in ("R3-B1", "R3-B2", "R3-B3", "R3-B4")
    occursin("\\tag{"*id*"}", doc) || error("项目公式缺失")
end
source=read(joinpath(root, "src", "algorithms", "r3_baseline.jl"), String)
# 静态调用边界不是算法正确性证明；配合实际轨迹和回归测试使用。
for forbidden in (
    "build_r3_local_step(",
    "build_r3_physical_step(",
    "repair_r3_flow(",
    "solve_r3_reference(",
    "solve_r3_projected_gradient(",
)
    occursin(forbidden, source) && error("独立基线出现额外恢复/参考调用：$forbidden")
end
cfg=TOML.parsefile(joinpath(root, "configs", "r3", "baseline-study.toml"))
ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch03", "r3-baseline-equations.toml"))
length(ledger["equation"])==4 || error("项目公式台账缺项")
for row in ledger["equation"]
    text=read(joinpath(root, row["document"]), String)
    occursin("\\tag{"*row["id"]*"}", text) || error("项目公式锚点缺失")
    isdefined(PaperRebuild, Symbol(row["api"])) || error("API映射缺失")
    occursin(row["test_name"], read(joinpath(root, row["test"]), String)) || error("测试映射缺失")
end
length(cfg["entries"])==42 || error("冻结实验不是42项")
count(e["method"]=="baseline" for e in cfg["entries"])==36 || error("基线数量不同")
for e in cfg["entries"]
    c=load_r2_case(joinpath(root, e["case_path"]))
    c.sha256==e["input_sha256"] || error("冻结输入变化")
    core=get(get(c.data, "r3_mechanism", Dict()), "core_periods", c.data["T"])
    PaperRebuild.r3_core_signature(c, core)==e["core_sha256"] || error("共同核心变化")
    e["method"]=="reference" && continue
    PaperRebuild.r2_flow_hash(PaperRebuild.r2_flow_matrix(c, e["initial_flow"]))==e["initial_flow_sha256"] ||
        error("初值改变")
end
println(
    "R3 baseline: 10 differences, 4 project equations, 42 frozen entries and restricted call boundary checked.",
)
