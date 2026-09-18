using TOML
function sync_r5_market_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "market.toml"))
    io=IOBuffer()
    println(io, "# 第5章市场：原式映射与符号\n")
    println(io, "由docs/reading/ch05/market.toml生成。原件PDF89–90；本页覆盖固定报价LP的9条原式。")
    println(io, "为便于阅读，原主体索引J/l改记g/b/i；上下界和类别上标的物理含义保留。")
    println(io, "完整推导、单位和边界见[市场说明](ch05-market.md)，未宣称实现双层或风险调度。\n")
    for x in ledger["equation"]
        println(io, "## 式（", x["id"], "）：", x["meaning"], "\n")
        println(io, "~~~math\n", x["original"], "\n\\tag{", x["id"], "}\n~~~\n")
        println(io, "采用解释：", x["adopted"], "\n")
        println(io, "API：[`", x["api"], "`](@ref)；测试组：", x["test"], "。\n")
    end
    println(io, "## 符号表\n")
    println(io, "| 稳定ID / 原符号 | 含义与类别 | 单位 / 定义域 | Julia与维度 | 来源 |")
    println(io, "|---|---|---|---|---|")
    for x in ledger["symbol"]
        println(
            io,
            "| ",
            x["id"],
            " / ``",
            x["latex"],
            "`` | ",
            x["meaning"],
            "；",
            x["category"],
            " | ",
            x["unit"],
            "；",
            x["domain"],
            " | `",
            x["julia"],
            "`；",
            x["dimensions"],
            " | ",
            x["source"],
            " |",
        )
    end
    println(io, "\n## 采用边界\n")
    for x in ledger["issue"]
        println(io, "- ", x["id"], "：", x["decision"])
    end
    target=joinpath(root, "docs", "src", "ch05-market-equations.md")
    text=String(take!(io))
    (!isfile(target)||read(target, String)!=text)&&write(target, text)
end
