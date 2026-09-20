"""
    audit_r9_pv_input(case)

不求解地检查44/38规模、映射、参考容量、周期热历史、SI换算和日热量守恒。
返回逐项证据；周期参考的入口/出口另由独立累计质量回放核验，不把构造成功当调度通过。
热历史是冻结的CF-CT日周期状态，不是可在优化中自由选择的初态。
"""
function audit_r9_pv_input(c::R2Case)
    d = c.data
    validate_r2_input(d)
    meta, h, e = d["r9"], d["heat"], d["electric"]
    meta["schema"] == "r9-pv-case-v1" || error("R9输入身份错误")
    !meta["original_input_ready"] && !meta["optimized_to_construct_input"] || error("来源声明错误")
    meta["protocol_sha256"] == r9_hash(meta["protocol"]) || error("协议哈希改变")
    meta["currency"] == "CNY" || error("币种错误")
    rows = NamedTuple[]
    function record(id, entity, t, residual, unit, tol)
        r = abs(Float64(residual))
        push!(
            rows,
            (
                equation = id,
                scope = "input",
                entity = string(entity),
                t,
                residual = r,
                unit,
                tolerance = tol,
                pass = isfinite(r)&&r<=tol,
            ),
        )
    end
    length(e["nodes"]) == 44 && length(h["nodes"]) == 38 && d["T"] == 24 || error("R9规模被改变")
    mapping = meta["internal_to_original_electric"]
    mapping == [44; collect(1:43)] && invperm(mapping) == meta["original_to_internal_electric"] ||
        error("根节点映射改变")
    length(meta["line_metadata"]) == length(e["edges"]) || error("线路来源丢失")
    for (i, edge) in enumerate(e["edges"])
        line = meta["line_metadata"][i]
        line["original_from"] == mapping[edge["from"]] &&
        line["original_to"] == mapping[edge["to"]] || error("线路原编号不一致")
        record(
            "R9-P2-pu",
            i,
            0,
            line["r_ohm_at_nominal_voltage"]/(line["nominal_kV"]^2/e["base_MVA"])-edge["r_pu"],
            "pu",
            1e-12,
        )
        record(
            "R9-P2-transformer",
            i,
            0,
            line["r_ohm_referred_10kV"]/line["r_ohm_at_nominal_voltage"]-(
                e["base_kV"]/line["nominal_kV"]
            )^2,
            "1",
            1e-12,
        )
    end
    ref, T = meta["reference"], d["T"]
    m = r2_flow_matrix(c)
    port = r2_fixed_port_flows(d, m)
    for j in eachindex(h["nodes"]), t in 1:T
        node = h["nodes"][j]
        record("R9-P3-mass", j, t, port[j, t]-ref["port_flow_kg_s"][j], "kg/s", 1e-9)
        if node["role"] == "source"
            gs = [g for g in d["devices"] if g["kind"] in ("CHP", "EB") && g["heat_node"] == j]
            lo, hi = sum(g["P_min"]*g["heat_ratio"] for g in gs),
            sum(g["P_max"]*g["heat_ratio"] for g in gs)
            heat = ref["source_heat_MW"][j][t]
            record("R9-P4-capacity", j, t, max(0, lo-heat, heat-hi), "MW", 1e-8)
            record(
                "R9-P4-source",
                j,
                t,
                heat-h["cp_J_kgK"]/1e6*port[j, t]*(h["S_reference_K"]-ref["R_mix"][j][t]),
                "MW",
                1e-8,
            )
        else
            heat = h["cp_J_kgK"]/1e6*port[j, t]*(ref["S_mix"][j][t]-ref["R_load"][j][t])
            record("R9-P4-load", j, t, heat-node["H_MW"][t], "MW", 1e-8)
            record(
                "R9-P4-return-bound",
                j,
                t,
                max(
                    0,
                    h["R_bounds_K"][1]-ref["R_load"][j][t],
                    ref["R_load"][j][t]-h["R_bounds_K"][2],
                ),
                "K",
                1e-8,
            )
        end
    end
    v = Dict("m_pipe"=>r2_extract(m), "tau_S_in"=>ref["S_in"], "tau_R_in"=>ref["R_in"])
    for (p, pipe) in enumerate(h["pipes"]), side in ("S", "R"), t in 1:T
        out = r3_mass_replay(c, v, p, t, side).out
        record("R9-P5-cyclic-replay", side*string(p), t, out-ref[side*"_out"][p][t], "K", 1e-8)
        b = h[side*"_bounds_K"]
        for key in (side*"_in", side*"_out")
            x = ref[key][p][t]
            record("R9-P5-temperature", key*string(p), t, max(0, b[1]-x, x-b[2]), "K", 1e-8)
        end
    end
    # 完整周期内的入口/出口差之和不含库存净变化；两个方向的热损失各计一次。
    source = sum(sum(x) for x in ref["source_heat_MW"])
    load = sum(sum(n["H_MW"]) for n in h["nodes"])
    loss = sum(
        h["cp_J_kgK"]/1e6*m[p, t]*(ref[side*"_in"][p][t]-ref[side*"_out"][p][t]) for
        p in axes(m, 1), t in 1:T, side in ("S", "R")
    )
    record("R9-P6-day-energy", 0, 0, d["dt_h"]*(source-load-loss), "MWh", 1e-7)
    return (;
        pass = all(r.pass for r in rows),
        rows,
        source_MWh = source*d["dt_h"],
        load_MWh = load*d["dt_h"],
        loss_MWh = loss*d["dt_h"],
    )
end

function r9_terminal_rows(c, stage)
    rows = NamedTuple[]
    haskey(stage, "values") || return rows
    d, v = c.data, stage["values"]
    for (p, pipe) in enumerate(d["heat"]["pipes"])
        L = ceil(
            Int,
            d["heat"]["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]/(
                3600d["dt_h"]*pipe["flow_min"]
            ),
        )
        for t in (d["T"]-L+1):d["T"], side in ("S", "R")
            x = abs(v["tau_"*side*"_in"][p][t]-pipe[side*"_history_K"][end+t-d["T"]])
            push!(
                rows,
                (
                    equation = "R9-P6-terminal-memory",
                    scope = "model",
                    entity = side*string(p),
                    t,
                    residual = x,
                    unit = "K",
                    tolerance = 1e-4,
                    pass = isfinite(x)&&x<=1e-4,
                ),
            )
        end
    end
    return rows
end

"""
    validate_r9_pv_solution(case, result)

从保存原值重新计算成本、逐式A1、独立热输运和终端记忆；原SOCP和κ重构值分别保留。
模型通过、原电网/采用热关系通过、周期记忆通过与费用界分别返回。
终端认证仅属于声明WMM离散模型，不升级为连续网络PDE或作者同输入复现。
"""
function validate_r9_pv_solution(c::R2Case, r)
    r["schema"] == "r9-pv-run-v1" && r["input_sha256"] == c.sha256 || error("R9运行身份不同")
    r["mode"] in ("CF_CT", "CF_VT") || error("本批未实现VF模式")
    stages = [r["stage"]]
    haskey(r, "reconstructed") && push!(stages, r["reconstructed"])
    reports = Any[]
    for stage in stages
        if haskey(stage, "values")
            stage["operation"]["mode"] == r["mode"] || error("运行模式改变")
        end
        base = validate_r3_solution(c, stage)
        terminal = r9_terminal_rows(c, stage)
        terminal_pass = !isempty(terminal) && all(x.pass for x in terminal)
        push!(
            reports,
            (
                model_pass = base.model_pass&&terminal_pass,
                physical_pass = base.physical_pass&&terminal_pass,
                terminal_pass,
                rows = vcat(base.rows, terminal),
            ),
        )
    end
    selected = length(reports)
    if haskey(r, "reconstructed")
        original, fixed = r["stage"], r["reconstructed"]
        fixed["transformation"] == "kappa_equal_mu_m2_v1" || error("未声明重构")
        for key in keys(original["values"])
            startswith(key, "kappa_") && continue
            original["values"][key] == fixed["values"][key] || error("重构改变控制/状态：$key")
        end
        original["operating_cost"] == fixed["operating_cost"] || error("重构改变费用")
    end
    return (;
        model_pass = reports[selected].model_pass,
        physical_pass = reports[selected].physical_pass,
        terminal_pass = reports[selected].terminal_pass,
        rows = reports[selected].rows,
        stages = reports,
    )
end
