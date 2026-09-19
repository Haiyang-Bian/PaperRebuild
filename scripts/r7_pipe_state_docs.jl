using TOML

function r7_pipe_state_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch06/pipe-state.toml"))
    io=IOBuffer()
    println(
        io,
        "# R7管内状态参考推导与符号\n\n<!-- generated: r7-pipe-state -->\n\n",
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
            "}\n~~~\n\n",
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
            "\n",
        )
        println(
            io,
            "实现：[`",
            e["api"],
            "`](@ref)；测试：`test/r7_pipe_state.jl` / `",
            e["test"],
            "`。\n",
        )
    end
    println(io, "## 采用假设\n")
    foreach(x->println(io, "- ", x), d["assumptions"])
    println(io, "\n## 符号\n\n|ID|符号|含义|单位|Julia|\n|---|---|---|---|---|")
    for s in d["symbol"]
        println(
            io,
            "|",
            s["id"],
            "|``",
            s["latex"],
            "``|",
            s["meaning"],
            "|",
            s["unit"],
            "|`",
            s["julia"],
            "`|",
        )
    end
    println(io, "\n## 外部对照\n")
    for r in d["reference"]
        println(
            io,
            "[",
            r["version"],
            "](",
            r["url"],
            ")：",
            r["role"],
            "；查阅",
            r["accessed"],
            "。",
        )
    end
    String(take!(io))
end
function sync_r7_pipe_state_docs(root = normpath(joinpath(@__DIR__, "..")))
    write(joinpath(root, "docs/src/ch06-pipe-equations.md"), r7_pipe_state_markdown(root))
end
