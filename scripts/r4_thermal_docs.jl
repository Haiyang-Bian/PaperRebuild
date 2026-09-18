using TOML
function sync_r4_thermal_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "thermal.toml"))
    io=IOBuffer()
    println(
        io,
        "# 稳态循环热网：公式与符号\n\n由docs/reading/ch04/thermal.toml生成；全部T式为项目采用方程。\n",
    )
    for x in d["equation"]
        println(
            io,
            "## ",
            x["id"],
            "\n\n~~~math\n",
            x["latex"],
            "\n\\tag{",
            x["id"],
            "}\n~~~\n\n",
            x["meaning"],
            "\n\nAPI：[",
            x["api"],
            "](@ref PaperRebuild.",
            x["api"],
            ")；测试：",
            x["test"],
            "。\n",
        )
    end
    println(io, "## 符号\n\n|稳定ID|原符号|Julia名称|含义与维度|单位|\n|---|---|---|---|---|")
    tick=string(Char(96))
    for x in d["symbol"]
        println(
            io,
            "|",
            x["id"],
            "|",
            tick,
            tick,
            x["latex"],
            tick,
            tick,
            "|",
            x["julia"],
            "|",
            x["meaning"],
            "|",
            x["unit"],
            "|",
        )
    end
    println(io, "\n## 边界与疑点\n")
    for x in d["issue"]
        println(io, "### ", x["id"], "\n\n", x["statement"], "\n\n", x["decision"], "\n")
    end
    write(
        joinpath(root, "docs", "src", "ch04-thermal-equations.md"),
        rstrip(String(take!(io)))*"\n",
    )
end
abspath(PROGRAM_FILE)==(@__FILE__) && sync_r4_thermal_docs()
