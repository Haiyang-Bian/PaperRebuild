using TOML
function r7_transport_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/transport-recovery.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7逐管联合恢复：推导与符号\n\n<!-- generated: r7-transport-recovery -->\n\n",
        d["scope"],
        "。\n",
    )
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
            "\n\n来源：",
            join(e["source_equations"], "、"),
            "；分类`",
            e["classification"],
            "`。\n\n实现：[`",
            e["api"],
            "`](@ref)。测试：`test/r7_transport.jl` / `",
            e["test"],
            "`。\n",
        )
    end
    println(
        io,
        "## 符号表\n\n| ID | 数学符号 | 含义 | 单位 | Julia | 维度 |\n|---|---|---|---|---|---|",
    )
    for s in d["symbol"]
        println(
            io,
            "| ",
            s["id"],
            " | ``",
            s["latex"],
            "`` | ",
            s["meaning"],
            " | ",
            s["unit"],
            " | `",
            s["julia"],
            "` | ",
            s["shape"],
            " |",
        )
    end
    String(take!(io))
end
