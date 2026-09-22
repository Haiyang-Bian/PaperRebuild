# region r1-validate
"""
    validate_r1_solution(case, result)

从保存数值独立重算方程、边界、初末状态、互斥及成本；不读取 JuMP 约束残差。
按 A1 固定尺度输出逐项残差、单位、阈值与通过状态。返回 `relaxed_pass` 和
`original_branch_pass` 两种判定；SOCP 可行不自动代表原支路等式成立。
不验证未建模的水压、变流量、风电疑点、市场和论文结论。缺解返回明确未评估状态。
"""
function validate_r1_solution(c::R1Case, result)
    result["input_sha256"] == c.sha256 || throw(ArgumentError("结果与输入哈希不符"))
    rows = NamedTuple{
        (:id, :t, :residual, :unit, :tolerance, :pass),
        Tuple{String,Int,Float64,String,Float64,Bool},
    }[]
    haskey(result, "values") || return (
        status = "not_assessed_no_solution",
        relaxed_pass = false,
        original_branch_pass = false,
        rows = rows,
    )
    d, s = c.data, result["values"]
    T, Δt = d["time"]["T"], d["time"]["dt_h"]
    dev, e, h, b, dem = (d[k] for k in ("devices", "electric", "heat", "building", "demand"))
    # 固定于输入的尺度，不使用求解结果放大阈值。
    scales = Dict(
        "MW" => max(1.0, e["S_base_MVA"]),
        "MWh" => max(1.0, dev["E_BS_max"], dev["E_HS_max"]),
        "kg/s" => max(1.0, h["m"]),
    )
    function add(id, t, r, unit = "1")
        tol =
            unit == "K" ? 1e-4 :
            haskey(scales, unit) ? 1e-6 * (1 + scales[unit]) :
            unit == "cost" ? 1e-6 * max(1, abs(result["objective"])) : 1e-6
        r = abs(Float64(r))
        push!(
            rows,
            (
                id = id,
                t = t,
                residual = r,
                unit = unit,
                tolerance = tol,
                pass = isfinite(r) && r <= tol,
            ),
        )
    end
    function checkbounds(name, lo, hi, unit = "MW")
        for (t, x) in enumerate(s[name])
            add("bound-" * name, t, max(lo - x, x - hi, 0), unit)
        end
    end
    for (name, x) in s
        all(isfinite, x isa Real ? [x] : x) || throw(ArgumentError("结果包含非有限数：$name"))
        if x isa AbstractVector
            length(x) == (name in ("E_BS", "E_HS", "tau_IN") ? T + 1 : T) ||
                throw(ArgumentError("结果维度错误：$name"))
        end
    end
    for name in (
        "P_CHP",
        "H_CHP",
        "P_EB",
        "H_EB",
        "P_HP",
        "H_HP",
        "P_PV",
        "P_WT",
        "P_BS_ch",
        "P_BS_dis",
        "H_HS_ch",
        "H_HS_dis",
        "H_D_hat",
        "H_D",
        "P_DH",
        "H_DH",
        "P_grid",
        "Q_grid",
        "l",
    )
        checkbounds(name, 0, Inf, name == "l" ? "1" : "MW")
    end
    for name in ("P_CHP", "H_CHP")
        checkbounds(name, dev[name*"_min"], dev[name*"_max"])
    end
    for name in ("EB", "HP")
        checkbounds("P_$name", 0, dev["P_$(name)_max"])
    end
    for q in ("BS", "HS")
        checkbounds("E_$q", 0, dev["E_$(q)_max"], "MWh")
        add("initial-E_$q", 0, s["E_$q"][1] - dev["E_$(q)_initial"], "MWh")
        add(q == "BS" ? "ch02-015" : "ch02-019", T, s["E_$q"][end] - s["E_$q"][1], "MWh")
        z = s["z_$q"]
        add("binary-$q", 0, min(abs(z), abs(z - 1)))
        for suffix in ("ch", "dis")
            name = (q == "BS" ? "P" : "H") * "_$(q)_$suffix"
            checkbounds(name, 0, dev["$(q)_power_max"] * (suffix == "ch" ? z : 1 - z))
        end
    end
    checkbounds("v", e["V_min_pu"]^2, e["V_max_pu"]^2, "1")
    checkbounds("l", 0, e["l_max_pu"], "1")
    checkbounds("tau_IN", b["tau_min"], b["tau_max"], "K")
    checkbounds("P_DH", 0, b["P_DH_max"])
    add("initial-tau_IN", 0, s["tau_IN"][1] - b["tau_initial"], "K")
    for name in ("tau_S_in", "tau_S_out", "tau_R_in", "tau_R_out")
        checkbounds(name, h["tau_min"], h["tau_max"], "K")
    end
    # 以入流时间箱与流出水体的体积重叠独立重算权重，不调用建模的 pipe_outlet。
    delay = h["rho_w"] * h["A"] * h["L"] / (h["m"] * Δt * 3600)
    lastlag = ceil(Int, delay)
    J = exp(
        -h["epsilon_W_mK"] * Δt * 3600 * (lastlag - 0.5) / (h["c_w"] * 1000 * h["rho_w"] * h["A"]),
    )
    for t in 1:T
        v(name) = s[name][t]
        add(
            "ch02-001",
            t,
            v("H_CHP") - v("P_CHP") * (1 - dev["eta_G"] - dev["eta_loss"]) / dev["eta_G"],
            "MW",
        )
        add("ch02-006", t, max(v("P_PV") - dem["P_PV_available"][t], 0), "MW")
        add("project-wt-disabled", t, v("P_WT"), "MW")
        for (q, id) in (("EB", "ch02-008"), ("HP", "ch02-010"))
            add(id, t, v("H_$q") - dev["COP_$q"] * v("P_$q"), "MW")
        end
        add(
            "ch02-012",
            t,
            s["E_BS"][t+1] - s["E_BS"][t] -
            Δt * (dev["eta_BS_ch"] * v("P_BS_ch") - v("P_BS_dis") / dev["eta_BS_dis"]),
            "MWh",
        )
        add(
            "ch02-016",
            t,
            s["E_HS"][t+1] - dev["eta_HS_loss"] * s["E_HS"][t] -
            Δt * (v("H_HS_ch") / dev["eta_HS_ch"] - dev["eta_HS_dis"] * v("H_HS_dis")),
            "MWh",
        )
        S, r, x = e["S_base_MVA"], e["r_pu"], e["x_pu"]
        add(
            "ch02-022",
            t,
            v("P_grid") + v("P_CHP") + v("P_PV") - v("P_HP") - v("P_EB") - v("P_BS_ch") +
            v("P_BS_dis") - dem["P_D"][t] - v("P_DH") - S * r * v("l"),
            "MW",
        )
        add("ch02-023", t, v("Q_grid") - S * x * v("l") - dem["Q_D"][t], "MW")
        add(
            "ch02-024",
            t,
            v("v") - 1 + 2 * (r * v("P_grid") + x * v("Q_grid")) / S - (r^2 + x^2) * v("l"),
        )
        exact = (v("P_grid") / S)^2 + (v("Q_grid") / S)^2 - v("l")
        add("ch02-025-original", t, exact)
        add("ch02-028", t, max(exact, 0))
        add(
            "ch02-029",
            t,
            v("H_CHP") + v("H_HP") + v("H_EB") - v("H_HS_ch") + v("H_HS_dis") -
            h["c_w"] / 1000 * h["m"] * (v("tau_S_in") - v("tau_R_out")),
            "MW",
        )
        add(
            "ch02-032",
            t,
            v("H_D") - h["c_w"] / 1000 * h["m"] * (v("tau_S_out") - v("tau_R_in")),
            "MW",
        )
        for side in ("S", "R")
            τstar = 0.0
            for lag in 0:lastlag
                w = max(0, min(lag + 1.0, delay + 1) - max(lag, delay))
                u = t - lag
                τstar += w * (u > 0 ? s["tau_$(side)_in"][u] : h["history_$side"][end+u])
            end
            add(
                "ch02-047-$side",
                t,
                v("tau_$(side)_out") - (h["tau_AM"] + J * (τstar - h["tau_AM"])),
                "K",
            )
        end
        add(
            "ch02-072",
            t,
            b["eta_H"] * v("H_D_hat") + b["U"] * (dem["tau_AM"][t] - s["tau_IN"][t+1]) -
            s["tau_IN"][t+1] + s["tau_IN"][t],
            "K",
        )
        add("ch02-075", t, v("H_D") - v("H_D_hat") + v("H_DH"), "MW")
        add("ch02-076", t, v("H_DH") - b["eta_DH"] * v("P_DH"), "MW")
    end
    cost =
        Δt * sum(d["cost"]["grid_per_MWh"] .* s["P_grid"] + d["cost"]["CHP_per_MWh"] .* s["P_CHP"])
    add("project-cost", 0, cost - result["objective"], "cost")
    relaxed = all(r -> r.pass, filter(r -> r.id != "ch02-025-original", rows))
    original = all(r -> r.pass, filter(r -> r.id == "ch02-025-original", rows))
    return (
        status = "assessed",
        relaxed_pass = relaxed,
        original_branch_pass = original,
        rows = rows,
    )
end
# endregion r1-validate
