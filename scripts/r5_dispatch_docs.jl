using TOML
function sync_r5_dispatch_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "dispatch.toml"))
    io=IOBuffer()
    println(io, "# 第5章确定性补救：原式与符号\n")
    println(io, "由docs/reading/ch05/dispatch.toml生成；原PDF85–88，建筑对照PDF43。")
    println(io, "为展示省略共同量词；原冲突下标保留，采用方程单独解释。不是全文公式审核完成。")
    println(io, "见[物理补救说明](ch05-dispatch.md)及[`build_r5_dispatch`](@ref)。\n")
    for x in ledger["equation"]
        println(
            io,
            "## 式（",
            x["id"],
            "）\n\n~~~math\n",
            x["original"],
            "\n\\tag{",
            x["id"],
            "}\n~~~\n",
        )
        println(io, "采用解释：", x["adopted"], "\n")
    end
    println(
        io,
        "## 符号表\n\n| ID / 原符号 | 含义 / 类别 | 单位 / 定义域 | Julia / 维度 | 来源 |\n|---|---|---|---|---|",
    )
    for x in ledger["symbol"]
        println(
            io,
            "| ",
            x["id"],
            " / ``",
            x["latex"],
            "`` | ",
            x["meaning"],
            " / ",
            x["category"],
            " | ",
            x["unit"],
            " / ",
            x["domain"],
            " | `",
            x["julia"],
            "` / ",
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
    target=joinpath(root, "docs", "src", "ch05-dispatch-equations.md")
    text=String(take!(io))
    (!isfile(target)||read(target, String)!=text)&&write(target, text)
end
