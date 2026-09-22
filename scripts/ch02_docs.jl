using TOML
using Markdown

const CH02_ROOT = normpath(joinpath(@__DIR__, ".."))

function ch02_records()
    base = joinpath(CH02_ROOT, "docs", "reading", "ch02")
    return (
        formulas = TOML.parsefile(joinpath(base, "formulas.toml"))["formula"],
        symbols = TOML.parsefile(joinpath(base, "symbols.toml"))["symbol"],
    )
end

function ch02_equation(f)
    return "```math\n" * f["latex"] * "\n\\tag{" * f["number"] * "}\n```\n"
end

# 正文和公式目录共用同一份转录；@eval 只返回排版结果，不显示生成代码。
function ch02_equations(numbers...)
    fs = ch02_records().formulas
    selected = map(numbers) do number
        only(filter(f -> f["number"] == number, fs))
    end
    return Markdown.parse(join(ch02_equation.(selected), "\n"))
end

function check_ch02_source_marker(path, marker)
    code = read(joinpath(CH02_ROOT, path), String)
    start = "# region " * marker
    stop = "# endregion " * marker
    length(findall(start, code)) == length(findall(stop, code)) == 1 ||
        error("源码标记缺失/重复：$path $marker")
    first(findfirst(start, code)) < first(findfirst(stop, code)) ||
        error("源码标记顺序错误：$path $marker")
    return nothing
end

function check_ch02()
    records = ch02_records()
    fs, ss = records.formulas, records.symbols
    expected = ["ch02-" * lpad(n, 3, '0') for n in 1:76]
    [r["id"] for r in fs] == expected || error("公式编号存在遗漏、重复或顺序错误")
    ids = [s["id"] for s in ss]
    allunique(ids) || error("符号 ID 重复")
    tests = read(joinpath(CH02_ROOT, "test", "r1.jl"), String)
    input_records =
        TOML.parsefile(joinpath(CH02_ROOT, "docs", "reading", "ch02", "inputs.toml"))["input"]
    case = TOML.parsefile(joinpath(CH02_ROOT, "configs", "r1", "micro.toml"))
    listed = [key for entry in input_records for key in entry["keys"]]
    actual = [
        section * "." * key for
        section in ("time", "electric", "heat", "devices", "building", "demand", "cost") for
        key in keys(case[section])
    ]
    allunique(listed) && Set(listed) == Set(actual) || error("输入清单与配置字段不一致")
    for f in fs
        occursin(r"^2-\d+$", f["number"]) || error("非法公式编号")
        length(strip(f["latex"])) > 1 || error("公式 $(f["id"]) 转录缺失或被截断")
        all(s -> s in ids, f["symbols"]) || error("公式 $(f["id"]) 引用未定义符号")
        if !isempty(f["source"])
            startswith(f["source"], "src/") && !occursin("..", f["source"]) || error("源码路径越界")
            check_ch02_source_marker(f["source"], f["marker"])
            occursin(f["test"], tests) || error("公式 $(f["id"]) 的测试不存在")
        else
            f["implementation"] in ("blocked", "deferred") || error("已实现公式缺少源码")
        end
    end
    for s in ss,
        key in (
            "latex",
            "meaning",
            "kind",
            "indices",
            "unit",
            "domain",
            "julia",
            "dimensions",
            "source",
            "verification",
            "ascii_alias",
        )

        !isempty(s[key]) || error("符号 $(s["id"]) 缺少 $key")
    end
    println(
        "Chapter 2 mapping: 76 formulas, ",
        length(ss),
        " symbol entries; source markers and test IDs valid.",
    )
    return records
end

function render_ch02()
    fs, ss = let r = check_ch02()
        (r.formulas, r.symbols)
    end
    io = IOBuffer()
    println(
        io,
        "```@raw html\n<!-- GENERATED: scripts/ch02_docs.jl; edit docs/reading/ch02 and current Julia sources. -->\n```\n",
    )
    println(io, "# [第 2 章公式索引](@id ch02-generated)\n")
    println(
        io,
        "此页由权威 TOML 生成，并校验当前源码标记与测试名称。已实现公式直接链接到 Julia docstring 的 API 条目；核查状态不代表科学验收通过，数值证据见 [本批状态](@ref ch02-status)。\n",
    )
    println(io, "## 公式逐条清单\n")
    println(io, "每组首式列出共同假设；各式的完整独立记录仍保存在权威 TOML 中。\n")
    last_model = ""
    for f in fs
        println(io, "### [式（", f["number"], "）：", f["meaning"], "](@id eq-", f["id"], ")\n")
        println(io, ch02_equation(f))
        println(
            io,
            "出处：PDF ",
            f["pdf_page"],
            " / 正文 ",
            f["printed_page"],
            "；核查：`",
            f["verification"],
            "`；实现：`",
            f["implementation"],
            "`。\n",
        )
        if f["model"] != last_model
            println(io, "本组共同假设：", f["assumptions"], "\n")
            last_model = f["model"]
        end
        isempty(f["issue"]) ||
            println(io, "疑点：**", f["issue"], "**，见 [核查边界](@ref ch02-issues)。\n")
        println(
            io,
            "符号：",
            join(["[" * id * "](@ref symbol-" * id * ")" for id in f["symbols"]], "、"),
            "。\n",
        )
        if !isempty(f["source"])
            println(
                io,
                "API：[`",
                f["api"],
                "`](@ref) · [实现与测试映射](@ref source-",
                f["marker"],
                ")。\n",
            )
        else
            println(io, "本批不生成实现链接；阻断/后续用途见 [模型详解](@ref ch02-models)。\n")
        end
    end
    formulas_page = String(take!(io))
    println(
        io,
        "```@raw html\n<!-- GENERATED: scripts/ch02_docs.jl; edit docs/reading/ch02 and current Julia sources. -->\n```\n",
    )
    println(
        io,
        "# [符号权威表](@id ch02-symbols)\n\n分组列出，避免宽表挤压。每个稳定 ID 可单独链接。公式引用见 [逐式索引](@ref ch02-generated)。\n",
    )
    for s in ss
        println(io, "### [", s["meaning"], "](@id symbol-", s["id"], ")\n")
        println(io, "```math\n", s["latex"], "\n```\n")
        println(
            io,
            "- ID / ASCII 别名：`",
            s["id"],
            "` / `",
            s["ascii_alias"],
            "`\n- 类别：",
            s["kind"],
            "；上下标：",
            s["indices"],
            "。\n- 单位：",
            s["unit"],
            "；定义域：",
            s["domain"],
            "。\n- Julia / 配置映射：`",
            s["julia"],
            "`；维度：",
            s["dimensions"],
            "。\n- 来源 PDF 页：",
            s["source"],
            "；状态：`",
            s["verification"],
            "`。\n",
        )
    end
    symbols_page = String(take!(io))
    println(
        io,
        "```@raw html\n<!-- GENERATED: scripts/ch02_docs.jl; edit docs/reading/ch02 and current Julia sources. -->\n```\n",
    )
    println(
        io,
        "# [实现与测试映射](@id ch02-source)\n\n函数签名、参数、单位和适用范围统一读取 [API docstring](@ref api-reference)。本页只登记公式、源码位置和测试名称，便于回到项目定位。\n",
    )
    seen = Set{String}()
    for f in fs
        isempty(f["source"]) && continue
        marker = f["marker"]
        marker in seen && continue
        push!(seen, marker)
        related = filter(row -> row["marker"] == marker && row["source"] == f["source"], fs)
        println(
            io,
            "### [",
            f["api"],
            "](@id source-",
            marker,
            ")\n\nAPI：[`",
            f["api"],
            "`](@ref)。\n\n对应公式：",
            join(
                ["[式（" * row["number"] * "）](@ref eq-" * row["id"] * ")" for row in related],
                "、",
            ),
            "。\n\n源码定位：`",
            f["source"],
            "`，标记 `",
            marker,
            "`。\n\n验证：",
            join(["`" * name * "`" for name in unique(row["test"] for row in related)], "、"),
            "（`test/r1.jl`）。\n",
        )
    end
    println(
        io,
        "## [测试入口](@id tests-r1)\n\n上述测试集保存在 `test/r1.jl`，运行入口为 `scripts/test.jl`。具体判定与实际通过状态见 [本批状态](@ref ch02-status)，原始测试代码保留在项目中。\n",
    )
    return Dict(
        "ch02-generated.md" => rstrip(formulas_page) * "\n",
        "ch02-symbols.md" => rstrip(symbols_page) * "\n",
        "ch02-source.md" => rstrip(String(take!(io))) * "\n",
    )
end

function sync_ch02(; check = false)
    for (name, content) in render_ch02()
        target = joinpath(CH02_ROOT, "docs", "src", name)
        previous = isfile(target) ? read(target, String) : ""
        previous == content && continue
        check && error(
            "Chapter 2 generated documentation is stale: $name; run scripts/check_ch02.jl --sync",
        )
        isempty(previous) ||
            startswith(previous, "<!-- GENERATED: scripts/ch02_docs.jl;") ||
            startswith(previous, "```@raw html\n<!-- GENERATED: scripts/ch02_docs.jl;") ||
            error("拒绝覆盖未标记的人类文档")
        write(target, content)
    end
end
