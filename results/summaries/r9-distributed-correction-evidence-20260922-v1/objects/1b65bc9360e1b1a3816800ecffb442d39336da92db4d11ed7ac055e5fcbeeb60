"""
    audit_r9_sources(bundle)

独立重算第7章设备容量、费率与作者表格算术；返回拓扑/容量/差异行和逐场景输入门槛。
源表舍入容差由显示小数位传播，独立于优化A1/A2，不用于放宽物理验收。
作者原数始终保留；本接口不求解、不写文件，不声称原文目标已复现。
"""
function audit_r9_sources(bundle)
    r9_source_check(bundle.data)
    d, g, a=(bundle.data[n] for n in ("inputs.toml", "topology.toml", "reported-results.toml"))
    rows=Dict{String,Any}[]
    function row(id, label, actual, reported, unit, digits, terms; meaning = "arithmetic")
        # 每个印刷数各有半个末位舍入误差；被比较的总数也计一次。
        tol=(terms+1)*0.5*10.0^(-digits)
        delta=actual-reported
        push!(
            rows,
            Dict(
                "id"=>id,
                "label"=>label,
                "derived"=>actual,
                "reported"=>reported,
                "difference"=>delta,
                "rounding_tolerance"=>tol,
                "unit"=>unit,
                "meaning"=>meaning,
                "status"=>abs(delta)<=tol+1e-9 ? "consistent_with_printed_rounding" :
                          "difference_requires_interpretation",
            ),
        )
    end
    base=d["base"]
    pv=sum(x["P_max_MW"] for x in base["pv"])
    electric=pv+sum(x["P_max_MW"] for x in base["chp"])
    heat=sum(x["P_max_MW"]*x["H_over_P"] for x in base["chp"])+sum(
        x["H_max_MW"] for x in base["eb"]
    )
    row(
        "R9-C01",
        "base electric capacity",
        electric,
        base["reported_distributed_electric_capacity_MW"],
        "MW",
        1,
        0,
    )
    row("R9-C02", "base renewable capacity", pv, base["reported_renewable_capacity_MW"], "MW", 1, 0)
    row(
        "R9-Q01",
        "H/P times CHP electricity plus rated EB heat",
        heat,
        base["reported_heat_capacity_MW"],
        "MW",
        1,
        0,
    )
    rc=d["resilience"]
    expanded=pv+sum(x["P_max_MW"] for x in rc["chp"])+sum(x["P_max_MW"] for x in rc["gt"])
    row(
        "R9-C03",
        "disaster electric capacity",
        expanded,
        rc["reported_distributed_electric_capacity_MW"],
        "MW",
        1,
        0,
    )
    modes=a["four_modes"]
    b=a["bargaining"]
    for k in eachindex(b["actor"])
        row(
            "7-10-stage1-"*b["actor"][k],
            "disagreement plus first payment",
            b["disagreement_CNY"][k]+b["stage1_payment_CNY"][k],
            b["stage1_utility_CNY"][k],
            "CNY",
            2,
            2,
        )
        row(
            "7-10-stage2-"*b["actor"][k],
            "first utility plus second payment",
            b["stage1_utility_CNY"][k]+b["stage2_payment_CNY"][k],
            b["stage2_utility_CNY"][k],
            "CNY",
            2,
            2,
        )
    end
    for key in (
        "disagreement",
        "stage1_payment",
        "stage1_utility",
        "stage2_payment",
        "stage2_utility",
        "sspa_utility",
    )
        row(
            "7-10-sum-"*key,
            "eight actor sum",
            sum(b[key*"_CNY"]),
            b["reported_"*key*"_sum_CNY"],
            "CNY",
            2,
            8,
        )
    end
    for key in ("stage1", "stage2", "sspa")
        row(
            "7-10-system-"*key,
            "operator plus aggregator printed total",
            b["operator_"*key*"_CNY"]+b["reported_"*key*"_utility_sum_CNY"],
            b["reported_system_"*key*"_CNY"],
            "CNY",
            2,
            2,
        )
    end
    tr=a["trading"]
    for k in eachindex(tr["scheme"])
        row(
            "7-11-"*tr["scheme"][k],
            "operator plus aggregators",
            tr["operator_utility_CNY"][k]+tr["aggregator_utility_CNY"][k],
            tr["system_utility_CNY"][k],
            "CNY",
            2,
            2,
        )
    end
    row(
        "7-10-vs-7-11",
        "printed first-cooperation aggregator totals",
        b["reported_stage1_utility_sum_CNY"],
        tr["aggregator_utility_CNY"][2],
        "CNY",
        2,
        1;
        meaning = "cross_table_comparability_unresolved",
    )
    r=a["resilience"]
    for k in eachindex(r["scheme"])
        total=r["purchase_CNY"][k]+r["local_operation_CNY"][k]+r["startup_CNY"][k]
        row(
            "7-19-cost-"*r["scheme"][k],
            "normal cost components",
            total,
            r["normal_cost_CNY"][k],
            "CNY",
            0,
            3,
        )
        k==1 && continue
        percent=100*(r["normal_cost_CNY"][k]/first(r["normal_cost_CNY"])-1)
        row(
            "Q08-"*r["scheme"][k],
            "cost increase versus 4A",
            percent,
            r["prose_cost_increase_percent"][k],
            "percent",
            2,
            0,
        )
    end
    row(
        "Q08-unserved",
        "unserved reduction 4C versus 4A",
        100*(1-r["unserved_MWh"][3]/r["unserved_MWh"][1]),
        r["prose_unserved_reduction_4C_percent"],
        "percent",
        2,
        0,
    )
    # 不比较不同单位的目标，也不把小时容量和式冒充瞬时备用或备用电量。
    Dict{String,Any}(
        "schema"=>"r9-input-audit-v1",
        "origin"=>"author_source_audit_not_optimization",
        "source_hashes"=>bundle.hashes,
        "source_pdf_sha256"=>d["source_sha256"],
        "rows"=>rows,
        "electric"=>r9_graph(
            g["electric"]["nodes"],
            g["electric"]["edges"],
            g["electric"]["root"];
            tree = true,
        ),
        "heat"=>r9_graph(g["heat"]["nodes"], g["heat"]["edges"], g["heat"]["root"]; tree = true),
        "tariff_CNY_MWh"=>r9_tariff(d, collect(0:23)),
        "base_derived_heat_capacity_MW"=>heat,
        "eb_electric_capacities_MW"=>[x["H_max_MW"]/x["eta"] for x in base["eb"]],
        "four_mode_cost_reduction_percent"=>100*(
            1-last(modes["cost_CNY"])/first(modes["cost_CNY"])
        ),
        "four_mode_utilization_gain_percentage_points"=>last(modes["pv_utilization_percent"])-first(
            modes["pv_utilization_percent"],
        ),
        "gates"=>[
            r9_original_input_gate(bundle, section) for section in ("7.2", "7.3", "7.4", "7.5")
        ],
        "original_input_complete"=>false,
        "optimization_performed"=>false,
    )
end
