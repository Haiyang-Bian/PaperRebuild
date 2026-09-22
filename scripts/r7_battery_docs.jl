using TOML
function r7_battery_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/battery-domain.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7电池域：原式、推导与符号\n\n<!-- generated: r7-battery-domain -->\n\n",
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
            "。实现：[`",
            e["api"],
            "`](@ref)。测试：`test/r7_battery.jl` / `",
            e["test"],
            "`。\n",
        )
    end
    println(
        io,
        "## 符号表\n\n| ID | 符号 | 含义 | 单位 | Julia | 维度 |\n|---|---|---|---|---|---|",
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
