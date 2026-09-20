using TOML
function r8_markdown(root = normpath(joinpath(@__DIR__, "..")); ledger = "r8-tradeoff.toml")
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06", ledger))
    io=IOBuffer()
    println(
        io,
        "# ",
        get(d, "title", "R8：目标、恢复界与符号"),
        "\n\n<!-- generated: ",
        replace(ledger, ".toml"=>""),
        " -->\n\n",
        d["scope"],
        "。\n\n",
        d["source_note"],
        "\n",
    )
    for x in d["source_fact"]
        println(
            io,
            "## ",
            x["id"],
            " 原页核查\n\n",
            x["location"],
            "。",
            x["fact"],
            "\n\n状态：`",
            x["status"],
            "`。\n",
        )
    end
    for e in d["equation"]
        println(
            io,
            "## ",
            e["id"],
            "\n\n~~~math\n",
            e["latex"],
            "\n\\tag{",
            e["id"],
            "}\n~~~\n\n",
            e["meaning"],
            "\n\nAPI：[`",
            e["api"],
            "`](@ref)。测试：`",
            e["test_file"],
            "` / `",
            e["test"],
            "`。\n",
        )
    end
    println(io, "## 符号\n\n| ID | 符号 | 含义 | 单位 | Julia | 维度 |\n|---|---|---|---|---|---|")
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
            "` | ",
            x["shape"],
            " |",
        )
    end
    String(take!(io))
end
