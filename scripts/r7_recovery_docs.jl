using TOML

function r7_recovery_markdown(root)
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/recovery.toml"))
    io=IOBuffer()
    println(io, "# R7恢复采用式与符号\n\n<!-- generated: r7-recovery -->\n")
    println(io, "来自`docs/reading/ch06/recovery.toml`。原页PDF107–116，")
    println(io, "本页只覆盖给定灾前状态的恢复子问题；不代替111式全覆盖。")
    println(io, "此前[实施前解析台账](ch06-audit-equations.md)保持历史范围。\n")
    for e in d["equation"]
        println(io, "## ", e["id"], "\n\n~~~math\n", e["latex"], "\n\\tag{", e["id"], "}\n~~~\n")
        println(
            io,
            e["meaning"],
            "\n\n原式：",
            join(e["source_equations"], "、"),
            "；分类：`",
            e["classification"],
            "`。\n",
        )
        println(io, "实现：[`", e["api"], "`](@ref)；`test/r7_recovery.jl`：`", e["test"], "`。\n")
    end
    println(io, "## 原式—实现—测试分组\n")
    for g in d["mapping"]
        println(
            io,
            "### ",
            g["id"],
            "\n\n",
            g["meaning"],
            "\n\n来源：",
            g["source_equations"],
            "；测试：`",
            g["test"],
            "`。\n",
        )
    end
    println(
        io,
        "## 符号权威表\n\n变量数组遵循设备/节点、时间、场景顺序；事件拓扑和流量共享是显式限制。\n",
    )
    println(
        io,
        "| ID | 原符号 | 含义 | 类别 | 单位 | Julia字段 | 维度 |\n|---|---|---|---|---|---|---|",
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
    String(take!(io))
end

function sync_r7_recovery_docs(root = normpath(joinpath(@__DIR__, "..")))
    write(joinpath(root, "docs/src/ch06-recovery-equations.md"), r7_recovery_markdown(root))
end
