using TOML
function sync_r5_duality_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "recourse-duality.toml"))
    io=IOBuffer()
    println(
        io,
        "# 补救对偶：项目推导与符号\n\n此页由recourse-duality.toml生成；编号R5-DK属于项目推导，不能冒用论文式号。\n",
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
            "\n\nAPI：[`",
            x["api"],
            "`](@ref)，测试：`",
            x["test"],
            "`。\n",
        )
    end
    println(io, "## 符号\n\n| ID | 数学符号 | 含义 | 单位 | Julia映射 |\n|---|---|---|---|---|")
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
            "` |",
        )
    end
    println(io, "\n## 采用边界\n")
    for x in d["issue"]
        println(io, "- **", x["id"], "：**", x["adopted"])
    end
    text=String(take!(io))
    path=joinpath(root, "docs", "src", "ch05-recourse-equations.md")
    (!isfile(path)||read(path, String)!=text)&&write(path, text)
end
