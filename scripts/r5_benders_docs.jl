using TOML
function sync_r5_benders_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "benders.toml"))
    io=IOBuffer()
    println(
        io,
        "# 条件Benders：采用推导与符号\n\n由benders.toml生成。PDF94–97为原算法出处；R5-BD为项目推导编号。\n",
    )
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
            "\n\n原式对应：",
            join(x["original_ids"], "、"),
            "。API：[`",
            x["api"],
            "`](@ref)，测试：`",
            x["test"],
            "`。\n",
        )
    end
    println(io, "## 符号\n\n| ID | 数学符号 | 含义 | 单位 | Julia映射 |\n|---|---|---|---|---|")
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
    println(io, "\n## 采用边界\n")
    for x in d["issue"]
        println(io, "- **", x["id"], "：**", x["adopted"])
    end
    text=String(take!(io))
    path=joinpath(root, "docs", "src", "ch05-benders-equations.md")
    (!isfile(path)||read(path, String)!=text)&&write(path, text)
end
