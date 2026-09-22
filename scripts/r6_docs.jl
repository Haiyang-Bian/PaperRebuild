using TOML

function r6_render_docs(source, target, title, intro)
    root = normpath(joinpath(@__DIR__, ".."))
    d = TOML.parsefile(joinpath(root, "docs", "reading", "ch05", source))
    io = IOBuffer()
    println(io, "# ", title, "\n\n", intro, "\n")
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
            "`](@ref)；测试：`",
            x["test"],
            "`。\n",
        )
    end
    println(io, "## 符号\n\n| ID | 符号 | 含义 | 单位 | Julia映射 |\n|---|---|---|---|---|")
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
    println(io, "\n## 原文与采用边界\n")
    for f in d["finding"]
        println(
            io,
            "### ",
            f["id"],
            "\n\n",
            f["location"],
            "；状态：`",
            f["classification"],
            "`。\n\n原文记录：",
            f["original"],
            "\n\n项目处理：",
            f["adopted"],
            "\n",
        )
    end
    text = rstrip(String(take!(io))) * "\n"
    path = joinpath(root, "docs", "src", target)
    (!isfile(path) || read(path, String) != text) && write(path, text)
end

function sync_r6_docs()
    r6_render_docs(
        "sample-out.toml",
        "r6-equations.md",
        "R6统计公式与符号",
        "由sample-out.toml生成；R6-S全部为项目推导编号。",
    )
    r6_render_docs(
        "r6-methods.toml",
        "r6-method-equations.md",
        "R6六方法推导与符号",
        "由r6-methods.toml生成；R6-M全部为项目推导编号，不替换论文式号。",
    )
    r6_render_docs(
        "r6-evaluation.toml",
        "r6-evaluation-equations.md",
        "R6新日策略与诊断公式",
        "由r6-evaluation.toml生成；R6-E全部为项目推导，主策略与诊断分开。",
    )
    r6_render_docs(
        "r6-study.toml",
        "r6-study-equations.md",
        "R6正式选择与压力规则",
        "由r6-study.toml生成；R6-F全部为项目实验约定，不替换作者参数。",
    )
end
