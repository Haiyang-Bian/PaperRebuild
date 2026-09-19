using TOML

function ch06_audit_markdown(root)
    d = TOML.parsefile(joinpath(root, "docs/reading/ch06/audit.toml"))
    io = IOBuffer()
    println(io, "# 第6章选定关系、符号与疑点\n\n<!-- generated: ch06-audit -->\n")
    println(io, "由`docs/reading/ch06/audit.toml`生成。当前是实施前的选定关系审计，")
    println(io, "不是全部原式核查或已实现调度API。原件PDF107–119（印刷90–102）。\n")
    for e in d["equation"]
        println(io, "## ", e["id"], "\n\n~~~math\n", e["latex"], "\n\\tag{", e["id"], "}\n~~~\n")
        println(
            io,
            e["meaning"],
            "\n\n原式/步骤：",
            join(e["source_equations"], "、"),
            "；分类：`",
            e["classification"],
            "`。\n",
        )
        println(
            io,
            "解析核查：`scripts/audit_ch06.jl`；测试：`",
            e["test"],
            "`，位于`test/ch06_audit.jl`。模型API尚未实现，不生成虚假链接。\n",
        )
    end
    println(io, "## 符号\n\nJulia栏为下一批接口命名约定，`planned`表示尚未实现。\n")
    println(io, "| ID | 符号 | 含义 | 单位 | Julia命名计划 |\n|---|---|---|---|---|")
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
            "` |",
        )
    end
    println(io, "\n## 原页与采用解释\n")
    for f in d["finding"]
        println(
            io,
            "### ",
            f["id"],
            "\n\n",
            f["location"],
            "；`",
            f["status"],
            "`。\n\n原页记录：",
            f["original"],
            "\n\n项目处理：",
            f["adopted"],
            "\n",
        )
    end
    println(io, "## 独立参考\n")
    for r in d["reference"]
        println(
            io,
            "- [",
            r["id"],
            "](",
            r["url"],
            ")：",
            r["role"],
            "。查阅日期",
            r["accessed"],
            "。",
        )
    end
    rstrip(String(take!(io)))*"\n"
end

function sync_ch06_docs()
    root = normpath(joinpath(@__DIR__, ".."))
    path = joinpath(root, "docs/src/ch06-audit-equations.md")
    text = ch06_audit_markdown(root)
    (!isfile(path) || read(path, String) != text) && write(path, text)
    nothing
end
