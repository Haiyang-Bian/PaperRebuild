using TOML
function r9_reserve_markdown()
    ledger=TOML.parsefile(joinpath(dirname(@__DIR__), "docs/reading/ch07/reserve.toml"))
    io=IOBuffer()
    println(io, "# 第7.4节输入：公式、符号和研究边界\n\n由`docs/reading/ch07/reserve.toml`生成。\n")
    println(io, "| 编号 | 含义 | Julia API |\n|---|---|---|")
    for q in ledger["equations"]
        println(io, "| $(q["id"]) | $(q["meaning"]) | [`$(q["api"])`](@ref) |")
    end
    println(io, "\n| ID | 数学符号 | 含义 | 代码 | 单位 |\n|---|---|---|---|---|")
    for s in ledger["symbols"]
        println(
            io,
            "| $(s["id"]) | ``$(s["latex"])`` | $(s["meaning"]) | `$(s["code"])` | $(s["unit"]) |",
        )
    end
    println(io, "\n| 疑点 | 状态 | 采用解释或缺口 |\n|---|---|---|")
    for x in ledger["issues"]
        println(io, "| $(x["id"]) | $(x["status"]) | $(x["meaning"]) |")
    end
    String(take!(io))
end
