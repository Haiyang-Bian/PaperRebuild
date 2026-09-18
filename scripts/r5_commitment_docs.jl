using TOML
function sync_r5_commitment_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "commitment.toml"))
    io=IOBuffer()
    println(
        io,
        "# 共同承诺：项目推导与符号\n\n由commitment.toml生成。原式参照既有第5章台账，R5-SC为项目基准编号。\n",
    )
    for x in ledger["equation"]
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
            "`](@ref)，测试：`",
            x["test"],
            "`。\n",
        )
    end
    println(io, "## 符号\n\n| ID | 数学符号 | 含义 | 单位 | Julia映射 |\n|---|---|---|---|---|")
    for x in ledger["symbol"]
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
    for x in ledger["issue"]
        println(io, "- **", x["id"], "：**", x["adopted"])
    end
    text=String(take!(io))
    path=joinpath(root, "docs", "src", "ch05-commitment-equations.md")
    (!isfile(path)||read(path, String)!=text)&&write(path, text)
end
