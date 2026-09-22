using TOML
function r9_pv_markdown(root = normpath(joinpath(@__DIR__, "..")))
    d=TOML.parsefile(joinpath(root, "docs/reading/ch07/pv-adoption.toml"))
    n=TOML.parsefile(joinpath(root, "docs/reading/ch07/numerics.toml"))
    append!(d["equations"], n["equations"])
    append!(d["symbols"], n["symbols"])
    f=TOML.parsefile(joinpath(root, "docs/reading/ch07/flow.toml"))
    append!(d["equations"], f["equations"])
    append!(d["symbols"], f["symbols"])
    io=IOBuffer()
    println(io, "# R9采用式与符号索引\n")
    println(
        io,
        "<!-- generated from docs/reading/ch07/{pv-adoption,numerics,flow}.toml; edit those ledgers -->\n",
    )
    println(
        io,
        "推导和边界见[固定模式基准](ch07-pv.md)，结果见[数值边界报告](ch07-pv-results.md)。\n",
    )
    println(io, "| ID | 含义 | 解释类别 | Julia API |\n|---|---|---|---|")
    for r in d["equations"]
        println(
            io,
            "| ",
            r["id"],
            " | ",
            r["meaning"],
            " | `",
            r["status"],
            "` | [`",
            r["api"],
            "`](@ref) |",
        )
    end
    println(
        io,
        "\n## 符号\n\n| 稳定ID | 原形 | 含义 | 单位 | Julia/配置映射 |\n|---|---|---|---|---|",
    )
    for s in d["symbols"]
        println(
            io,
            "| `",
            s["id"],
            "` | ``",
            s["latex"],
            "`` | ",
            s["meaning"],
            " | ",
            s["unit"],
            " | `",
            s["code"],
            "` |",
        )
    end
    println(
        io,
        "\n测试：`test/r9_pv.jl` / **",
        d["test"],
        "**。冻结重读及求解验证另见`scripts/test_r9_pv_evidence.jl`。",
    )
    println(
        io,
        "\n数值推导见[前向与终端解释](ch07-numerics.md)。R9-N1–N6对应`test/r9_reduced.jl`、`scripts/check_r9_affine_certificate.jl`及`scripts/check_r9_numerics_results.jl`。",
    )
    println(
        io,
        "\n连续流量推导见[输运与周期记忆](ch07-flow.md)。R9-V1–V4对应`test/r9_flow.jl`，R9-V5对应`test/r9_heat_memory.jl`；[直接参考](ch07-flow-results.md)有三项合格候选，CF-VT字面版本仍失败，PG尚未迁移。",
    )
    flow=TOML.parsefile(joinpath(root, "docs/reading/ch07/flow.toml"))
    println(
        io,
        "\n## 连续流量与记忆符号\n\n| 稳定ID | 原形 | 含义 | 单位 | Julia映射 |\n|---|---|---|---|---|",
    )
    for s in flow["symbols"]
        println(
            io,
            "| `",
            s["id"],
            "` | ``",
            s["latex"],
            "`` | ",
            s["meaning"],
            " | ",
            s["unit"],
            " | `",
            s["code"],
            "` |",
        )
    end
    return String(take!(io))
end
