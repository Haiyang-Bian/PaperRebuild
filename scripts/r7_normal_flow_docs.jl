using TOML
function r7_normal_flow_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/normal-flow.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7连续流量：原式、推导与符号\n\n<!-- generated: r7-normal-flow -->\n\n",
        d["scope"],
        "。\n",
    )
    for e in d["original_equation"]
        println(
            io,
            "## 原式 ",
            e["id"],
            "\n\n~~~math\n",
            e["latex"],
            "\n\\tag{",
            e["id"],
            "}\n~~~\n\nPDF ",
            e["pdf_page"],
            "页。",
            e["note"],
            "\n",
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
            "\n\n分类：",
            e["classification"],
            "。API：[`",
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
