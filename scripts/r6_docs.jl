using TOML

function sync_r6_docs()
    root = normpath(joinpath(@__DIR__, ".."))
    d = TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "sample-out.toml"))
    io = IOBuffer()
    println(io, "# R6统计公式与符号\n\n由sample-out.toml生成；R6-S全部为项目推导编号。\n")
    for x in d["equation"]
        println(
            io,
            "## ",
            x["id"],
            "\n\n~~~math\n",
            x["latex"],
            "\n\\tag{",
            x["id"],
            "}\n~~~\n\n",
            x["meaning"],
            "\n\nAPI：[`",
            x["api"],
            "`](@ref)；测试：`",
            x["test"],
            "`。\n",
        )
    end
    println(io, "## 符号\n\n| ID | 符号 | 含义 | 单位 | Julia映射 |\n|---|---|---|---|---|")
    for x in d["symbol"]
        println(
            io,
            "| ",
            x["id"],
            " | ``",
            x["latex"],
            "`` | ",
            x["meaning"],
            " | ",
            x["unit"],
            " | `",
            x["julia"],
            "` |",
        )
    end
    println(io, "\n## 原文与采用边界\n")
    for f in d["finding"]
        println(
            io,
            "### ",
            f["id"],
            "\n\n",
            f["location"],
            "；状态：`",
            f["classification"],
            "`。\n\n原文记录：",
            f["original"],
            "\n\n项目处理：",
            f["adopted"],
            "\n",
        )
    end
    text = rstrip(String(take!(io))) * "\n"
    path = joinpath(root, "docs", "src", "r6-equations.md")
    (!isfile(path) || read(path, String) != text) && write(path, text)
end
