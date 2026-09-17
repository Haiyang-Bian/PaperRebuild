using TOML, Markdown
const CH03_ROOT = normpath(joinpath(@__DIR__, ".."))
function check_ch03()
    base = joinpath(CH03_ROOT, "docs", "reading", "ch03")
    f = TOML.parsefile(joinpath(base, "formulas.toml"))
    s = TOML.parsefile(joinpath(base, "symbols.toml"))
    count = f["declared_equation_count"]
    count > 0 && [r["number"] for r in f["formula"]] == collect(1:count) || error("第3章声明范围内的公式编号不完整")
    for r in f["formula"]
        !isempty(r["latex"]) && 46 <= r["page"] <= 55 || error("无效公式转录")
        g = f["groups"][r["group"]]
        all(id -> haskey(s["symbols"], id), g["symbols"]) || error("未定义符号")
        state = get(r, "implementation", "implemented")
        state in ("implemented", "documented") || error("非法实现状态")
        if state == "implemented"
            tests = read(joinpath(CH03_ROOT, get(g, "test_path", "test/r2.jl")), String)
            occursin(g["test"], tests) || error("映射测试缺失")
            source = read(joinpath(CH03_ROOT, g["source"]), String)
            occursin("function "*g["api"], source) || error("API映射失效")
        else
            !isempty(get(r, "reason", "")) || error("未实现公式缺少说明")
        end
    end
    for (id, row) in s["symbols"],
        key in ("latex", "meaning", "kind", "unit", "domain", "julia", "dimensions")

        haskey(row, key) && !isempty(row[key]) || error("符号$id 缺$key")
    end
    println(
        "Chapter 3: ",
        count,
        " equations, ",
        length(s["symbols"]),
        " symbols; source/API/test mappings checked.",
    )
    return f, s
end
function render_ch03()
    f, s = check_ch03()
    io = IOBuffer()
    outputs = Dict{String,String}()
    println(io, "# [第3章公式与符号索引](@id ch03-equations)\n")
    println(
        io,
        "<!-- GENERATED: scripts/ch03_docs.jl; edit docs/reading/ch03/formulas.toml and symbols.toml. -->\n",
    )
    println(
        io,
        "本页为原式规范化转录，不是修正后的模型。疑点、角色边界与补全式见[模型解释](@ref ch03-models)。\n",
    )
    println(
        io,
        "索引分页：[热网与简化式](@ref ch03-heat-equations) · [符号表](@ref ch03-symbols)。\n",
    )
    for r in f["formula"]
        if r["number"] in (27, 58)
            outputs[r["number"] == 27 ? "ch03-equations.md" : "ch03-heat-equations.md"] =
                String(take!(io))
            println(
                io,
                r["number"] == 27 ? "# [第3章热网与简化式](@id ch03-heat-equations)\n" :
                "# [第3章算法公式](@id ch03-algorithm-equations)\n",
            )
            println(
                io,
                "<!-- GENERATED: scripts/ch03_docs.jl -->\n\n[设备、电网与水力](@ref ch03-equations) · [符号表](@ref ch03-symbols)。\n",
            )
        end
        g = f["groups"][r["group"]]
        id = "ch03-"*lpad(r["number"], 3, '0')
        println(io, "## [（3-", r["number"], "）", r["meaning"], "](@id eq-", id, ")\n")
        println(io, "```math\n", r["latex"], "\n\\tag{3-", r["number"], "}\n```\n")
        println(
            io,
            "出处：PDF ",
            r["page"],
            " / 正文 ",
            r["page"]-17,
            "；状态：原页视觉核读；采用解释和实现状态另列。\n",
        )
        if get(r, "implementation", "implemented") == "implemented"
            println(
                io,
                "本批作用：",
                get(r, "role", "项目补全版/适用特例中的约束或边界"),
                "。 ",
                g["assumptions"],
                "\n",
            )
            haskey(r, "issue") && println(io, "**疑点：", r["issue"], "。**\n")
            println(
                io,
                "实现入口：[`",
                g["api"],
                "`](@ref)；源码 `",
                g["source"],
                "`；测试 `",
                g["test"],
                "`。\n",
            )
        else
            println(io, "实现状态：已说明、未实现。", r["reason"], "\n")
        end
        println(
            io,
            "符号：",
            join(["["*id*"](@ref sym-ch03-"*id*")" for id in g["symbols"]], "、"),
            "。\n",
        )
    end
    outputs["ch03-algorithm-equations.md"] = String(take!(io))
    println(
        io,
        "# [第3章符号权威表](@id ch03-symbols)\n<!-- GENERATED: scripts/ch03_docs.jl -->\n",
        s["index_rule"],
        "\n",
    )
    for (id, row) in sort(collect(s["symbols"]); by = first)
        println(io, "### [", id, "：", row["meaning"], "](@id sym-ch03-", id, ")\n")
        println(io, "```math\n", row["latex"], "\n```\n")
        println(io, "| 项目 | 定义 |\n| --- | --- |")
        for (label, key) in (
            ("类别", "kind"),
            ("单位", "unit"),
            ("定义域", "domain"),
            ("Julia映射", "julia"),
            ("数组维度/上下标", "dimensions"),
        )
            println(io, "| ", label, " | ", row[key], " |")
        end
        println(
            io,
            "| ASCII检索别名 | `",
            id,
            "` |\n| 来源 | ",
            s["source"],
            " |\n| 核查 | ",
            s["verification"],
            " |\n",
        )
    end
    outputs["ch03-symbols.md"] = String(take!(io))
    return Dict(file => rstrip(text)*"\n" for (file, text) in outputs)
end
function sync_ch03(; check = false)
    for (file, text) in render_ch03()
        path = joinpath(CH03_ROOT, "docs", "src", file)
        same = isfile(path) && replace(read(path, String), "\r\n"=>"\n") == text
        check && !same && error("第3章生成索引失步；执行 scripts/check_ch03.jl --sync")
        !check && !same && write(path, text)
    end
    return nothing
end
