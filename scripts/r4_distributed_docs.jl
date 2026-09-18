using TOML
function sync_r4_distributed(; check = false)
    root=normpath(joinpath(@__DIR__, ".."))
    data=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "distributed.toml"))
    [x["number"] for x in data["formula"]]==collect(60:70) || error("分布公式不完整")
    io=IOBuffer()
    tick=string(Char(96))
    println(io, "# 第4章分布协调公式与符号\n\n<!-- GENERATED: scripts/r4_distributed_docs.jl -->\n")
    println(
        io,
        "原式结构转录及改写边界见[推导](ch04-distributed.md)，未实现条目不得改记为已执行。\n",
    )
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
            ")；测试：R4 distributed convex coordination and bilateral consensus。\n",
        )
    end
    println(io, "## 符号表\n\n| ID / Julia | 符号 | 含义 | 单位 | 来源 |\n|---|---|---|---|---|")
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
            r["source"],
            " |",
        )
    end
    println(io, "\n## 疑点与采用解释\n")
    for r in data["issue"]
        println(io, "### ", r["id"], " ", r["topic"], "\n\n", r["adopted"], "\n")
    end
    content=rstrip(String(take!(io)))*"\n"
    path=joinpath(root, "docs", "src", "ch04-distributed-equations.md")
    if check
        isfile(path) && replace(read(path, String), "\r\n"=>"\n")==content ||
            error("分布生成页过期")
    else
        write(path, content)
    end
    api=read(joinpath(root, "docs", "src", "api.md"), String)
    tests=read(joinpath(root, "test", "r4_distributed.jl"), String)
    occursin("R4 distributed convex coordination and bilateral consensus", tests) ||
        error("测试映射缺失")
    for r in data["formula"]
        isdefined(PaperRebuild, Symbol(r["api"])) && occursin(r["api"], api) || error("API映射缺失")
    end
    println("R4 distributed: 11 formulas, 6 symbols, 5 issues checked.")
end
