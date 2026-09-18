using TOML
function sync_r4_heat_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "heat-compatibility.toml"))
    io=IOBuffer()
    println(
        io,
        "# 热状态相容性：公式、符号与映射\n\n由docs/reading/ch04/heat-compatibility.toml生成；HC式均为项目推导。\n",
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
    println(io, "## 符号\n\n|稳定ID|数学符号|Julia名称|含义/维度|单位|\n|---|---|---|---|---|")
    tick=string(Char(96))
    for s in d["symbol"]
        println(
            io,
            "|",
            s["id"],
            "|",
            tick,
            tick,
            s["latex"],
            tick,
            tick,
            "|",
            s["julia"],
            "|",
            s["meaning"],
            "|",
            s["unit"],
            "|",
        )
    end
    println(io, "\n## 适用条件与疑点\n")
    for x in d["issue"]
        println(io, "### ", x["id"], "\n\n", x["statement"], "\n\n", x["decision"], "\n")
    end
    write(joinpath(root, "docs", "src", "ch04-heat-equations.md"), rstrip(String(take!(io)))*"\n")
end
abspath(PROGRAM_FILE)==(@__FILE__) && sync_r4_heat_docs()
