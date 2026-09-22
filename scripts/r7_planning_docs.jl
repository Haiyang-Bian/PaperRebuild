using TOML

function r7_planning_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/planning.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7有限故障规划：方程、符号与边界\n\n<!-- generated: r7-planning -->\n\n",
        d["scope"],
        "。\n",
    )
    for e in d["original_equation"]
        println(
            io,
            "## 原式",
            e["id"],
            "\n\n~~~math\n",
            e["latex"],
            "\n\\tag{",
            e["id"],
            "}\n~~~\n\nPDF",
            e["pdf_page"],
            "：",
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
            "\n\n原式：",
            join(e["source_equations"], "、"),
            "；分类`",
            e["classification"],
            "`。\n\n实现：[`",
            e["api"],
            "`](@ref)。测试：`test/r7_planning.jl` / `",
            e["test"],
            "`。\n",
        )
    end
    println(io, "## 原文与采用解释\n")
    for f in d["finding"]
        println(
            io,
            "### ",
            f["id"],
            "\n\n原文：",
            f["original"],
            "\n\n采用：",
            f["adopted"],
            "\n\n状态：`",
            f["status"],
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
sync_r7_planning_docs(root = normpath(joinpath(@__DIR__, ".."))) =
    write(joinpath(root, "docs/src/ch06-planning-equations.md"), r7_planning_markdown(root))
