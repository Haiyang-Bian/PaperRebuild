using TOML
function r9_network_markdown()
    root=dirname(@__DIR__)
    ledger=TOML.parsefile(joinpath(root, "docs/reading/ch07/network.toml"))
    io=IOBuffer()
    println(io, "# 接入参数与重构：台账索引\n\n由 `docs/reading/ch07/network.toml` 生成。\n")
    println(io, "| 编号 | 含义 | Julia API |\n|---|---|---|")
    for x in ledger["equations"]
        println(io, "| $(x["id"]) | $(x["meaning"]) | [`$(x["api"])`](@ref) |")
    end
    println(io, "\n| ID | 原符号 | 含义 | Julia | 单位 |\n|---|---|---|---|---|")
    for x in ledger["symbols"]
        println(
            io,
            "| $(x["id"]) | ``$(x["latex"])`` | $(x["meaning"]) | `$(x["code"])` | $(x["unit"]) |",
        )
    end
    println(io, "\n## 采用解释与边界\n\n| ID | 状态 | 内容 |\n|---|---|---|")
    for x in ledger["issues"]
        println(io, "| $(x["id"]) | $(x["status"]) | $(x["meaning"]) |")
    end
    String(take!(io))
end
