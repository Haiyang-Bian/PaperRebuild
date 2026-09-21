"""
    audit_r9_reserve_input(case)

核对第7.4节模板的原节点、额定设备、币种和稳态历史；从保存温度独立重算混合、输运和热源容量。
不求解；只认证声明的预运行热参考，不代表整日零备用、100情景或样本外调度可行。
R9-RS1/RS2采用固定正流和作者J历史。温度1e-4K、功率1e-6MW，保持原A1边界。
"""
function audit_r9_reserve_input(c::R5DispatchCase)
    r5_dispatch_assert_case(c)
    d=c.data
    d["schema"]=="r5-dispatch-case-v2" && r5_dispatch_currency(d)=="CNY" ||
        error("R9备用需要显式CNY v2")
    x=d["r9_reserve"]
    x["schema"]=="r9-reserve-template-v1" &&
    !x["optimized_to_construct_input"] &&
    !x["original_input_ready"] &&
    r9_hash(x["protocol"])==x["protocol_sha256"] || error("R9备用来源或协议改变")
    p=x["protocol"]
    h=d["heat"]
    r=x["reference"]
    failures=String[]
    residuals=Dict{String,Any}[]
    function row(name, value, tolerance, unit = "1")
        pass=isfinite(value)&&abs(value)<=tolerance
        pass || push!(failures, name*"="*string(value))
        push!(
            residuals,
            Dict(
                "id"=>name,
                "residual"=>abs(value),
                "tolerance"=>tolerance,
                "unit"=>unit,
                "pass"=>pass,
            ),
        )
    end
    S, R=r["S_K"], r["R_K"]
    amb=r["ambient_K"]
    cp=h["c_J_kgK"]/1e6
    src=h["sources"]
    bs=d["buildings"]
    pipes=h["pipes"]
    # 读取绑定于输入的原表摘录；逐设备查额定侧，不能仅靠整体synthetic标签。
    contract=x["source_contract"]
    row("electric-node-count", d["electric"]["nodes"]-44, 0.0)
    row("electric-root", d["electric"]["root"]-44, 0.0)
    row("heat-node-count", h["nodes"]-38, 0.0)
    row("time-periods", d["T"]-24, 0.0)
    row("time-step", d["dt_h"]-1.0, 0.0, "h")
    for (name, entries, key) in
        (("electric", d["electric"]["lines"], "electric_edges"), ("heat", pipes, "heat_edges"))
        observed=Set((a["from"], a["to"]) for a in entries)
        expected=Set((a[1], a[2]) for a in contract[key])
        row(name*"-topology", length(symdiff(observed, expected)), 0.0)
    end
    expected_devices=vcat(contract["base"]["chp"], contract["base"]["eb"], contract["base"]["pv"])
    row(
        "device-inventory",
        length(symdiff(Set(g["id"] for g in d["devices"]), Set(g["id"] for g in expected_devices))),
        0.0,
    )
    for kind in ("chp", "eb", "pv"), original in contract["base"][kind]
        found=filter(g->g["id"]==original["id"], d["devices"])
        length(found)==1 || continue
        g=only(found)
        id=g["id"]
        row("device-kind/$id", g["kind"]==uppercase(kind) ? 0 : 1, 0.0)
        row("device-node/$id", g["node"]-original["electric_node"], 0.0)
        cap=kind=="eb" ? original["H_max_MW"]/original["eta"] : original["P_max_MW"]
        row("device-capacity/$id", g["p_max_MW"]-cap, 1e-6, "MW")
        expected_cost=kind=="chp" ? original["fuel_CNY_MWh_electric"] :
                      kind=="pv" ? original["cost_CNY_MWh"] : 0.0
        row("device-cost/$id", r5_dispatch_device_cost(d, g)-expected_cost, 1e-6, "CNY/MWh")
        if kind!="pv"
            row(
                "device-heat-port/$id",
                g["source_id"]=="H"*string(original["heat_node"]) ? 0 : 1,
                0.0,
            )
            row(
                "device-heat-ratio/$id",
                g["heat_ratio"]-(kind=="eb" ? original["eta"] : original["H_over_P"]),
                1e-6,
            )
        end
    end
    row("local-heater-count", count(b->b["P_DH_max_MW"]>0, bs)-length(contract["p2h"]), 0.0)
    row("building-count", length(bs)-36, 0.0)
    for original in contract["p2h"]
        found=filter(b->b["heat_node"]==original["heat_node"], bs)
        row("local-heater-port/"*original["id"], length(found)-1, 0.0)
        length(found)==1 || continue
        b=only(found)
        id=original["id"]
        row("local-heater-node/$id", b["electric_node"]-original["electric_node"], 0.0)
        row("local-heater-capacity/$id", b["P_DH_max_MW"]-original["capacity_MW"], 1e-6, "MW")
        row("local-heater-efficiency/$id", b["COP_DH"]-original["eta"], 1e-6)
    end
    row("terminal-pipe-rule", h["terminal_rule"]==p["heat"]["terminal_rule"] ? 0 : 1, 0.0)
    for b in bs
        row(
            "terminal-building/"*b["id"],
            b["terminal_rule"]==p["building"]["terminal_rule"] ? 0 : 1,
            0.0,
        )
        row(
            "building-time-constant/"*b["id"],
            b["C_MWh_K"]/b["G_MW_K"]-p["building"]["time_constant_h"],
            1e-6,
            "h",
        )
    end
    tariff=p["market"]["transmission_CNY_MWh"]
    for (field, expected) in (
        ("energy_price", p["market"]["energy_price_CNY_MWh"] .+ tariff),
        ("up_price", p["market"]["up_price_CNY_MW_h"]),
        ("down_price", p["market"]["down_price_CNY_MW_h"]),
    )
        row(
            "price/"*field,
            maximum(abs.(d["award"][field] .- expected)),
            1e-6,
            field=="energy_price" ? "CNY/MWh" : "CNY/(MW*h)",
        )
    end
    row(
        "price/realtime",
        maximum(abs.(d["realtime"]["price"] .- p["market"]["energy_price_CNY_MWh"] .- tariff)),
        1e-6,
        "CNY/MWh",
    )
    for i in 1:h["nodes"]
        row("source-temp-bound/$i", max(0, h["S_min_K"]-S[i], S[i]-h["S_max_K"]), 1e-4, "K")
        row("return-temp-bound/$i", max(0, h["R_min_K"]-R[i], R[i]-h["R_max_K"]), 1e-4, "K")
        mi=sum(q["m_kg_s"] for q in pipes if q["to"]==i; init = 0.0)+sum(
            s["m_kg_s"] for s in src if s["node"]==i;
            init = 0.0,
        )
        mr=sum(q["m_kg_s"] for q in pipes if q["from"]==i; init = 0.0)+sum(
            b["m_kg_s"] for b in bs if b["heat_node"]==i;
            init = 0.0,
        )
        sin=sum(
            q["m_kg_s"]*r["S_out_K"][j] for (j, q) in enumerate(pipes) if q["to"]==i;
            init = 0.0,
        ) + sum(
            s["m_kg_s"]*p["heat"]["source_reference_K"] for s in src if s["node"]==i;
            init = 0.0,
        )
        rin=sum(
            q["m_kg_s"]*r["R_out_K"][j] for (j, q) in enumerate(pipes) if q["from"]==i;
            init = 0.0,
        ) + sum(
            b["m_kg_s"]*r["load_return_K"][j] for (j, b) in enumerate(bs) if b["heat_node"]==i;
            init = 0.0,
        )
        row("supply-mix/$i", S[i]-sin/mi, 1e-4, "K")
        row("return-mix/$i", R[i]-rin/mr, 1e-4, "K")
        row("mass/$i", mi-mr, 1e-6, "kg/s")
    end
    for (j, q) in enumerate(pipes)
        # 独立由质量时间和原J公式计算；不调用建模fixed_flow_kernel。
        delay=q["rho_kg_m3"]*q["area_m2"]*q["length_m"]/(q["m_kg_s"]*3600*d["dt_h"])
        a=ceil(Int, delay)
        attenuation=exp(
            -q["loss_W_mK"]*3600*d["dt_h"]/(h["c_J_kgK"]*q["rho_kg_m3"]*q["area_m2"])*(a-0.5),
        )
        for (side, node) in (("S", q["from"]), ("R", q["to"]))
            inlet=side=="S" ? S[node] : R[node]
            row("transport/$side/$j", r[side*"_out_K"][j]-amb-attenuation*(inlet-amb), 1e-4, "K")
            row("history/$side/$j", maximum(abs.(q["history_"*side*"_K"] .- inlet)), 1e-4, "K")
        end
    end
    for (j, b) in enumerate(bs)
        ret=r["load_return_K"][j]
        row("load-return/$j", max(0, b["R_min_K"]-ret, ret-b["R_max_K"]), 1e-4, "K")
        heat=cp*b["m_kg_s"]*(S[b["heat_node"]]-ret)
        row("building-heat/$j", heat-b["G_MW_K"]*(b["T_initial_K"]-amb), 1e-6, "MW")
    end
    for (j, s) in enumerate(src)
        heat=cp*s["m_kg_s"]*(p["heat"]["source_reference_K"]-R[s["node"]])
        row("source-heat/$j", heat-r["source_heat_MW"][j], 1e-6, "MW")
        cap=sum(
            g["p_max_MW"]*g["heat_ratio"] for g in d["devices"] if get(g, "source_id", "")==s["id"];
            init = 0.0,
        )
        row("source-capacity/$j", max(0, -heat, heat-cap), 1e-6, "MW")
    end
    Dict(
        "reference_pass"=>isempty(failures),
        "failures"=>failures,
        "rows"=>residuals,
        "case_sha256"=>c.sha256,
        "whole_day_dispatch_verified"=>false,
        "reference_source_heat_MW"=>r["source_heat_MW"],
        "electric_nodes"=>d["electric"]["nodes"],
        "heat_nodes"=>h["nodes"],
        "buildings"=>length(bs),
        "local_P2H_count"=>count(b->b["P_DH_max_MW"]>0, bs),
    )
end
