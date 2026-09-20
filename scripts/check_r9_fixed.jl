using PaperRebuild, TOML
root=dirname(@__DIR__)
ledger=TOML.parsefile(joinpath(root, "docs/reading/ch07/fixed.toml"))
ledger["schema"]=="r9-fixed-adoption-v1" &&
!ledger["original_input_reproduction"] &&
!ledger["uses_projected_gradient"] || error("固定子问题身份改变")
page=read(joinpath(root, ledger["page"]), String)
tests=read(joinpath(root, ledger["test_file"]), String)
occursin(ledger["test"], tests) || error("测试映射缺失")
Set(x["id"] for x in ledger["equations"])==Set("R9-F$i" for i in 1:3) || error("方程遗漏")
io=IOBuffer()
println(io, "# 固定流量子问题：台账索引\n\n由 `docs/reading/ch07/fixed.toml` 生成。\n")
println(io, "| 编号 | 含义 | 状态 | Julia API |\n|---|---|---|---|")
for x in ledger["equations"]
    isdefined(PaperRebuild, Symbol(x["api"])) || error("API缺失")
    occursin("\\tag{"*x["id"]*"}", page) || error("公式编号缺失")
    println(io, "| $(x["id"]) | $(x["meaning"]) | $(x["status"]) | [`$(x["api"])`](@ref) |")
end
println(io, "\n| ID | 符号 | 含义 | 单位 | Julia |\n|---|---|---|---|---|")
for x in ledger["symbols"]
    println(
        io,
        "| $(x["id"]) | ``$(x["latex"])`` | $(x["meaning"]) | $(x["unit"]) | `$(x["code"])` |",
    )
end
expected=String(take!(io))
target=joinpath(root, "docs/src/ch07-fixed-generated.md")
ARGS in (String[], ["--sync"]) || error("usage: check_r9_fixed.jl [--sync]")
"--sync" in ARGS && write(target, expected)
read(target, String)==expected || error("固定子问题符号页失步")
println("R9 fixed-flow mapping passed; no optimization.")
