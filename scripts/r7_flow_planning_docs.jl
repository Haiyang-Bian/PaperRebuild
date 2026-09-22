using TOML
function r7_flow_planning_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/flow-planning.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7联合流量：推导与符号\n\n<!-- generated: r7-flow-planning -->\n\n",
        d["scope"],
        "。\n",
    )
    println(io, d["source_note"], " 原式见[共同空间状态台账](ch06-linked-equations.md)。\n")
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
