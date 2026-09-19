using TOML
function sync_r5_risk_docs()
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "risk.toml"))
    io=IOBuffer()
    println(
        io,
        "# 有限支持风险：方程与符号\n\n由risk.toml生成。原文PDF92–94已复核；R5-R为项目采用推导编号。\n",
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
            "\n\n原式对应：",
            isempty(x["original_ids"]) ? "项目新增" : join(x["original_ids"], "、"),
            "。API：[`",
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
    path=joinpath(root, "docs", "src", "ch05-risk-equations.md")
    (!isfile(path)||read(path, String)!=text)&&write(path, text)
end
