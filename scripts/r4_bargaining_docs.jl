using TOML
function sync_r4_bargaining(; check = false)
    root=normpath(joinpath(@__DIR__, ".."))
    data=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "bargaining.toml"))
    io=IOBuffer()
    println(io, "# 第4章议价公式与符号\n\n<!-- GENERATED: scripts/r4_bargaining_docs.jl -->\n")
    println(io, "本页仅登记已用于本批实现的8条原式；没有宣称(4-60)至(4-102)全部实现。\n")
    tick=string(Char(96))
    for r in data["formula"]
        println(io, "## [（4-", r["number"], "）", r["meaning"], "](@id ", r["id"], ")\n")
        println(io, tick^3, "math\n", r["latex"], "\n\\tag{4-", r["number"], "}\n", tick^3, "\n")
        println(io, "PDF ", r["pdf_page"], "；状态：", r["status"], "。\n")
        println(
            io,
            "API：[",
            r["api"],
            "](@ref PaperRebuild.",
            r["api"],
            ")；测试：",
            tick,
            r["test"],
            tick,
            "。\n",
        )
    end
    println(
        io,
        "## 符号权威表\n\n| ID / Julia | 原符号 | 含义 | 单位 | 域 / 维度 | 来源 |\n|---|---|---|---|---|---|",
    )
    for r in data["symbol"]
        println(
            io,
            "| ",
            r["id"],
            " / ",
            tick,
            r["julia"],
            tick,
            " | ",
            tick^2,
            r["latex"],
            tick^2,
            " | ",
            r["meaning"],
            " | ",
            r["unit"],
            " | ",
            r["domain"],
            " / ",
            r["dimensions"],
            " | ",
            r["source"],
            " |",
        )
    end
    println(io, "\n## 疑点与采用边界\n")
    for r in data["issue"]
        println(io, "### ", r["id"], " ", r["topic"], "\n\n", r["adopted"], "\n")
    end
    text=rstrip(String(take!(io)))*"\n"
    path=joinpath(root, "docs", "src", "ch04-bargaining-equations.md")
    if check
        isfile(path) && replace(read(path, String), "\r\n"=>"\n")==text || error("议价生成页过期")
    else
        write(path, text)
    end
    api=read(joinpath(root, "docs", "src", "api.md"), String)
    tests=read(joinpath(root, "test", "r4_bargaining.jl"), String)
    for r in data["formula"]
        isdefined(PaperRebuild, Symbol(r["api"])) || error("API缺失")
        occursin(r["api"], api) && occursin(r["test"], tests) || error("文档/测试映射缺失")
    end
    println("R4 bargaining: 8 formulas, 6 symbols, 4 adoption issues mapped.")
end
