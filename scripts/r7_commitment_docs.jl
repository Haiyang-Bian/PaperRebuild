using TOML

function r7_commitment_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/normal-prerequisites.toml"))
    io=IOBuffer()
    println(io, "# R7灾前启停推导与符号\n\n<!-- generated: r7-commitment -->\n")
    println(io, "来源：`docs/reading/ch06/normal-prerequisites.toml`。", d["scope"], "。\n")
    println(io, "## 关键原式\n")
    for e in d["original_equation"]
        println(
            io,
            "### 原式",
            e["id"],
            "\n\n~~~math\n",
            e["latex"],
            "\n\\tag{",
            e["id"],
            "}\n~~~\n",
        )
        println(io, "PDF", e["pdf_page"], "：", e["note"], "\n")
    end
    for e in d["equation"]
        println(io, "## ", e["id"], "\n\n~~~math\n", e["latex"], "\n\\tag{", e["id"], "}\n~~~\n")
        println(
            io,
            e["meaning"],
            "\n\n原式：",
            join(e["source_equations"], "、"),
            "；`",
            e["classification"],
            "`。\n",
        )
        isempty(e["api"]) || println(io, "实现：[`", e["api"], "`](@ref)。\n")
        println(io, "验证：`test/r7_commitment.jl` / `", e["test"], "`。\n")
    end
    println(io, "## 原页与采用解释\n")
    for f in d["finding"]
        println(
            io,
            "### ",
            f["id"],
            "\n\n",
            f["location"],
            "。\n\n原文：",
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
        "## 符号表\n\n| ID | 原符号 | 含义 | 类别 | 单位 | Julia | 维度 |\n|---|---|---|---|---|---|---|",
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
            s["kind"],
            " | ",
            s["unit"],
            " | `",
            s["julia"],
            "` | ",
            s["shape"],
            " |",
        )
    end
    println(io, "\n## 理论对照\n")
    for r in d["reference"]
        println(io, "- [", r["id"], "](", r["url"], ")：", r["role"], "。查阅", r["accessed"], "。")
    end
    String(take!(io))
end
function sync_r7_commitment_docs(root = normpath(joinpath(@__DIR__, "..")))
    write(joinpath(root, "docs/src/ch06-commitment-equations.md"), r7_commitment_markdown(root))
end
