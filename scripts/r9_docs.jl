using TOML

function r9_markdown(root = normpath(joinpath(@__DIR__, "..")))
    bundle=load_r9_sources(joinpath(root, "docs/reading/ch07"))
    a=audit_r9_sources(bundle)
    d=bundle.data["inputs.toml"]
    targets=bundle.data["reported-results.toml"]
    io=IOBuffer()
    println(io, "# 第7章输入与原表核查索引\n\n<!-- generated: r9-source-ledgers -->\n")
    println(
        io,
        "权威记录为 `docs/reading/ch07/` 的原页转录。本页由 Julia 生成；作者数值不是本项目优化结果。\n",
    )
    println(io, "## 场景差异\n\n| 节 | 父输入 | 已核实的独立改动 |\n|---|---|---|")
    println(io, "| 7.2 | 7.1 | E22光伏从2增至6 MW；四种流量/源温模式 |")
    println(io, "| 7.3 | 7.1 | 八聚合商、节点负荷1.5倍、设备与联络线；表7-9是否已放大仍未明 |")
    println(io, "| 7.4 | 7.1 | 价格接受者、100代表、ε=0.05、四个P2H设备 |")
    println(io, "| 7.5 | 7.1 | 独立CHP扩容/启停成本、GT、0.4新能源、关键负荷与四小时故障 |\n")
    println(io, "## 设备与量纲\n\n44电节点/43条边、38热节点/37对管；两张原图均通过连通树检查。")
    println(io, "电负荷峰值 `45.67 MVA` 是视在功率，热峰值为 `7.23 MW`；功率因数仍缺。\n")
    println(
        io,
        "基准额定电源合计16.5 MW、光伏8 MW；按表列设备推算供热能力为 ",
        a["base_derived_heat_capacity_MW"],
        " MW，正文写8.1 MW，两者保留。",
    )
    println(
        io,
        "两个电锅炉的额定热输出为1、1.2 MW，派生额定电输入为 ",
        join(round.(a["eb_electric_capacities_MW"]; digits = 6), "、"),
        " MW。\n",
    )
    println(io, "## 作者四模式目标：表7-5\n\n| 模式 | 日费用 CNY | 光伏利用率 % |\n|---|---:|---:|")
    modes=targets["four_modes"]
    for k in eachindex(modes["mode"])
        println(
            io,
            "| ",
            modes["mode"][k],
            " | ",
            modes["cost_CNY"][k],
            " | ",
            modes["pv_utilization_percent"][k],
            " |",
        )
    end
    println(
        io,
        "\n由原表首末行重算费用下降 ",
        round(a["four_mode_cost_reduction_percent"]; digits = 6),
        "%，利用率增加 ",
        round(a["four_mode_utilization_gain_percentage_points"]; digits = 6),
        " 个百分点；这不是本项目收益。\n",
    )
    println(
        io,
        "## 超出显示舍入的算术或跨表差异\n\n舍入带由原表显示位数传播，独立于科学A1/A2门槛。跨表口径未明不能直接断言原文计算错误。\n",
    )
    println(io, "| ID | 重算值 | 原记值 | 单位 | 解释类型 |\n|---|---:|---:|---|---|")
    for row in a["rows"]
        row["status"]=="difference_requires_interpretation" || continue
        println(
            io,
            "| ",
            row["id"],
            " | ",
            round(row["derived"]; digits = 6),
            " | ",
            row["reported"],
            " | ",
            row["unit"],
            " | ",
            row["meaning"],
            " |",
        )
    end
    println(
        io,
        "\n全部 ",
        length(a["rows"]),
        " 行（包括通过和尾数误差）保存在审计报告，未用修正值覆盖原表。\n",
    )
    println(io, "## 原始输入缺口\n\n| ID | 场景 | 仍缺或需澄清 |\n|---|---|---|")
    for gap in d["gaps"]
        println(io, "| ", gap["id"], " | ", join(gap["scope"], " / "), " | ", gap["missing"], " |")
    end
    println(io, "\n## 迁移约束\n")
    migration=TOML.parsefile(joinpath(root, "docs/reading/ch07/migration.toml"))
    for route in migration["route"]
        println(
            io,
            "### ",
            route["section"],
            "\n\n复用：",
            route["reuse"],
            "。\n\n接口缺口：",
            route["known_interface_gap"],
            "\n\n不得默认继承：",
            route["must_not_inherit"],
            "。\n",
        )
    end
    println(io, "迁移状态：`specified_not_executed`；详见[输入说明与后续顺序](ch07-inputs.md)。")
    String(take!(io))
end
