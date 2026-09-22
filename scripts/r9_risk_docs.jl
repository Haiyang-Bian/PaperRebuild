using TOML
function r9_risk_markdown()
    x=TOML.parsefile(joinpath(@__DIR__, "..", "docs/reading/ch07/risk-study.toml"))
    io=IOBuffer()
    println(
        io,
        "# 第7.4节风险比较台账\n\n由`docs/reading/ch07/risk-study.toml`生成；仅保证声明有限支持，未完成样本外验收。\n",
    )
    println(io, "| 公式 | 含义 | Julia API |\n|---|---|---|")
    for q in x["equations"]
        println(io, "| ", q["id"], " | ", q["meaning"], " | [`", q["api"], "`](@ref) |")
    end
    println(io, "\n| 符号ID | 原记号 | 含义 | 单位 | 代码 |\n|---|---|---|---|---|")
    for q in x["symbols"]
        println(
            io,
            "| ",
            q["id"],
            " | ``",
            q["latex"],
            "`` | ",
            q["meaning"],
            " | ",
            q["unit"],
            " | `",
            q["code"],
            "` |",
        )
    end
    String(take!(io))
end
