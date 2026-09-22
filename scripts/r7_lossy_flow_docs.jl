using TOML
function r7_lossy_flow_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/lossy-flow.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7有损输运：方程与符号\n\n<!-- generated: r7-lossy-flow -->\n\n",
        d["scope"],
        "。\n\n",
        d["source_note"],
        "\n",
    )
    println(io, "参考推导见[逐管参考](ch06-pipe-equations.md)。\n")
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
    println(
        io,
        "## 符号表\n\n| ID | 符号 | 含义 | 单位 | Julia | 维度 |\n|---|---|---|---|---|---|",
    )
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
