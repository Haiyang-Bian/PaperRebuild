using TOML
function update_r4_network_records()
    root=normpath(joinpath(@__DIR__, ".."))
    path=joinpath(root, "docs", "reading", "ch04", "formulas.toml")
    d=TOML.parsefile(path)
    for x in d["formula"]
        if x["number"] in (22, 29, 34, 35, 36, 37, 38, 39, 40, 48, 49, 50, 51)
            x["api"]="build_r4_reconfiguration"
            x["test"]="R4 network reconfiguration"
            x["status"]="adopted_scope"
            x["scope_note"]="r4_reconfiguration_checked_v1；原式与N1–N6补全区别见network.toml。"
        elseif x["number"]==33
            x["latex"]="\\|(2P_{mn,t},2Q_{mn,t},l_{mn,t}-v_{n,t})\\|_2\\le l_{mn,t}+v_{n,t}"
            x["issues"]=["R4-C05"]
            x["scope_note"]="PDF66原页为接收端v_n；实现仍采用发送端v_m，差异见R4-NC05，历史数值不改写。"
        end
    end
    open(path, "w") do io
        TOML.print(io, d; sorted = true)
    end
end
function sync_r4_network()
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "network.toml"))
    io=IOBuffer()
    tick=string(Char(96))
    fence=repeat(tick, 3)
    println(io, "# 重构采用式与符号\n\n<!-- Generated from docs/reading/ch04/network.toml. -->\n")
    for x in d["equation"]
        println(
            io,
            "## ",
            x["id"],
            "：",
            x["title"],
            "\n\n",
            fence,
            "math\n",
            x["latex"],
            "\\tag{",
            x["id"],
            "}\n",
            fence,
            "\n\n",
            x["interpretation"],
            "\n",
        )
        println(
            io,
            "API：[",
            x["api"],
            "](@ref PaperRebuild.",
            x["api"],
            ")；测试：",
            x["test"],
            "。\n",
        )
    end
    println(io, "## 符号\n\n|稳定ID|符号|含义|Julia|单位|定义域|\n|---|---|---|---|---|---|")
    for x in d["symbol"]
        println(
            io,
            "|",
            join(
                (
                    x["id"],
                    tick^2*x["latex"]*tick^2,
                    x["meaning"],
                    tick*x["julia"]*tick,
                    x["unit"],
                    x["domain"],
                ),
                "|",
            ),
            "|",
        )
    end
    println(io, "\n## 原式疑点与采用解释\n")
    for x in d["issue"]
        println(
            io,
            "### ",
            x["id"],
            "\n\n",
            x["original"],
            "\n\n证据：",
            x["evidence"],
            "\n\n采用：",
            x["adopted"],
            "\n",
        )
    end
    write(joinpath(root, "docs", "src", "ch04-network-equations.md"), rstrip(String(take!(io)))*"\n")
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    "--update-records" in ARGS && update_r4_network_records()
    sync_r4_network()
end
