using TOML
function sync_r4_tspa(; check = false)
    root=normpath(joinpath(@__DIR__, ".."))
    data=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "tspa.toml"))
    io=IOBuffer()
    println(io, "# 第4章两阶段公式与符号\n\n<!-- GENERATED: scripts/r4_tspa_docs.jl -->\n")
    println(
        io,
        "登记（4-95）—（4-102）的原式结构和采用范围；项目松弛定义见[推导](ch04-tspa.md)。\n",
    )
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
            "R4 TSPA network disagreement and penalty accounting",
            tick,
            "。\n",
        )
    end
    println(
        io,
        "## 符号权威表\n\n| ID / Julia | 符号 | 含义 | 单位 | 域 / 来源 |\n|---|---|---|---|---|",
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
            r["source"],
            " |",
        )
    end
    println(io, "\n## 疑点及采用解释\n")
    for r in data["issue"]
        println(io, "### ", r["id"], " ", r["topic"], "\n\n", r["adopted"], "\n")
    end
    content=rstrip(String(take!(io)))*"\n"
    path=joinpath(root, "docs", "src", "ch04-tspa-equations.md")
    if check
        isfile(path) && replace(read(path, String), "\r\n"=>"\n")==content ||
            error("TSPA生成页过期")
    else
        write(path, content)
    end
    api=read(joinpath(root, "docs", "src", "api.md"), String)
    tests=read(joinpath(root, "test", "r4_tspa.jl"), String)
    occursin("R4 TSPA network disagreement and penalty accounting", tests) || error("测试名称缺失")
    length(data["formula"])==8 && length(unique(r["id"] for r in data["formula"]))==8 ||
        error("公式重复/缺失")
    for r in data["formula"]
        isdefined(PaperRebuild, Symbol(r["api"])) && occursin(r["api"], api) ||
            error("API或文档缺失")
    end
    println("R4 TSPA: 8 formulas, 5 symbols, 4 adoption issues mapped.")
end
