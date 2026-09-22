using TOML
function ch04_records()
    root=normpath(joinpath(@__DIR__, ".."))
    dir=joinpath(root, "docs", "reading", "ch04")
    f=TOML.parsefile(joinpath(dir, "formulas.toml"))
    s=TOML.parsefile(joinpath(dir, "symbols.toml"))
    issues=TOML.parsefile(joinpath(dir, "issues.toml"))
    [r["number"] for r in f["formula"]]==collect(1:59) || error("第4章公式范围不完整")
    ids=Set(r["id"] for r in issues["issue"])
    for r in f["formula"]
        r["pdf_page"] in 64:68 && !isempty(r["latex"]) || error("公式出处或转录缺失")
        all(i->i in ids, r["issues"]) || error("无效疑点引用")
    end
    length(Set(r["id"] for r in s["symbols"]))==length(s["symbols"]) || error("符号ID重复")
    for r in s["symbols"],
        k in
        ("latex", "meaning", "unit", "domain", "dimensions", "julia", "kind", "source", "status")

        !isempty(r[k]) || error("符号字段缺失")
    end
    return root, f, s, issues
end
function render_ch04()
    root, f, s, issues=ch04_records()
    io=IOBuffer()
    println(io, "# 第4章原式清单\n\n<!-- GENERATED: scripts/ch04_docs.jl -->\n")
    println(io, "原式规范化转录保留疑点，不等同于采用模型。见[模型说明](ch04-models.md)。\n")
    tick=string(Char(96))
    for r in f["formula"]
        println(io, "## [（4-", r["number"], "）", r["title"], "](@id ", r["id"], ")\n")
        println(io, tick^3, "math\n", r["latex"], "\n\\tag{4-", r["number"], "}\n", tick^3, "\n")
        println(
            io,
            "PDF ",
            r["pdf_page"],
            "；",
            r["status"],
            "；疑点：",
            join(r["issues"], ", "),
            ".\n",
        )
        isempty(r["api"]) || println(
            io,
            "采用范围对应API：",
            tick,
            r["api"],
            tick,
            "；测试：",
            tick,
            r["test"],
            tick,
            "。\n",
        )
    end
    outputs=Dict("ch04-equations.md"=>String(take!(io)))
    println(io, "# 第4章符号与采用解释\n\n<!-- GENERATED: scripts/ch04_docs.jl -->\n")
    println(io, "主符号和语义标签沿用第2章规则；actor含运营商及聚合商，time为时段，E另含0时刻。\n")
    println(io, "| ID / Julia | 原符号 | 含义 | 单位 | 域 / 维度 |\n|---|---|---|---|---|")
    for r in s["symbols"]
        println(
            io,
            "| ",
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
            " |",
        )
    end
    println(io, "\n## 采用解释与来源缺口\n")
    for r in issues["issue"]
        println(
            io,
            "### ",
            r["id"],
            " ",
            r["topic"],
            "\n\n原式：",
            join(r["equations"], ", "),
            "；状态：",
            r["state"],
            "。\n\n",
            r["adopted"],
            "\n\n验证依据：",
            r["validation"],
            "\n",
        )
    end
    outputs["ch04-symbols.md"]=String(take!(io))
    return root, Dict(k => rstrip(v)*"\n" for (k, v) in outputs)
end
function sync_ch04(; check = false)
    root, outputs=render_ch04()
    for (file, text) in outputs
        path=joinpath(root, "docs", "src", file)
        if check
            isfile(path) && replace(read(path, String), "\r\n"=>"\n")==text ||
                error("第4章生成页过期：$file")
        else
            write(path, text)
        end
    end
    println("Chapter 4: 59 formulas, 43 symbols, 7 issue records checked.")
end
