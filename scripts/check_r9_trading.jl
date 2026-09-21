using PaperRebuild, TOML
root=dirname(@__DIR__)
ARGS in (String[], ["--sync"]) || error("usage: check_r9_trading.jl [--sync]")
ledger=TOML.parsefile(joinpath(root, "docs/reading/ch07/trading.toml"))
ledger["schema"]=="r9-trading-adoption-v1" || error("交易台账版本错误")
for flag in (
    "original_input_reproduction",
    "uses_projected_gradient",
    "network_reconfiguration",
    "distributed_algorithm",
    "bargaining",
    "full_thermal_physics_certified",
)
    !ledger[flag] || error("未实施能力不得升级：$flag")
end
page=read(joinpath(root, ledger["page"]), String)
tests=read(joinpath(root, ledger["test_file"]), String)
all(x->occursin(x, tests), ledger["tests"]) || error("测试映射缺失")
run_tests=read(joinpath(root, ledger["run_test_file"]), String)
all(x->occursin(x, run_tests), ledger["run_tests"]) || error("运行测试映射缺失")
for api in ledger["run_apis"]
    isdefined(PaperRebuild, Symbol(api)) && occursin(api, page) || error("运行API/卡片缺失")
end
Set(x["id"] for x in ledger["equations"])==Set("R9-T$i" for i in 1:6) || error("方程映射缺失")
source=load_r9_sources(joinpath(root, "docs/reading/ch07"))
ledger["source_sha256"]==source.data["inputs.toml"]["source_sha256"] || error("原件来源漂移")
c=r9_trading_case(joinpath(root, "docs/reading/ch07"), joinpath(root, ledger["protocol"]))
io=IOBuffer()
println(io, "# 八聚合商交易：台账索引\n\n由 `docs/reading/ch07/trading.toml` 生成。\n")
println(io, "| 编号 | 含义 | 状态 | Julia API |\n|---|---|---|---|")
for x in ledger["equations"]
    isdefined(PaperRebuild, Symbol(x["api"])) || error("API缺失")
    occursin("\\tag{"*x["id"]*"}", page) || error("缺少居中编号公式")
    println(io, "| $(x["id"]) | $(x["meaning"]) | $(x["status"]) | [`$(x["api"])`](@ref) |")
end
println(io, "\n| ID | 符号 | 含义 | 单位 | Julia |\n|---|---|---|---|---|")
allunique(x["id"] for x in ledger["symbols"]) || error("符号ID重复")
for x in ledger["symbols"]
    println(
        io,
        "| $(x["id"]) | ``$(x["latex"])`` | $(x["meaning"]) | $(x["unit"]) | `$(x["code"])` |",
    )
end
println(io, "\n## 采用解释与缺口\n\n| ID | 出处 | 状态 | 含义 |\n|---|---|---|---|")
for x in ledger["issues"]
    println(io, "| $(x["id"]) | $(x["source"]) | $(x["status"]) | $(x["meaning"]) |")
end
println(io, "\n## 运行与独立重验\n\n| Julia API | 测试位置 |\n|---|---|")
for api in ledger["run_apis"]
    println(io, "| [`$api`](@ref) | `$(ledger["run_test_file"])` |")
end
expected=String(take!(io))
target=joinpath(root, "docs/src/ch07-trading-generated.md")
"--sync" in ARGS && write(target, expected)
read(target, String)==expected || error("交易索引失步")
println("R9 trading mapping/input passed: ", c.sha256, "; no scale optimization performed.")
