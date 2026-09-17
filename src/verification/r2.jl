# region r2-verify
"""
    validate_r2_solution(case, result)

独立数值回代：不调用建模器、不读取求解器约束值。A1功率/质量阈值为1e-6+1e-6×冻结尺度，
温度1e-4 K，无量纲1e-6。model行检查采用模型，physics行检查松弛前关系和WMM回放。
original_physics_pass仅指本批明确列出的补全物理关系，不代表论文全部物理已核清。
缺解保留状态，不生成零数组或假残差。
"""
function validate_r2_solution(c::R2Case, result)
    rows = NamedTuple[]
    if !haskey(result, "values")
        return (
            status = get(result, "status", "no_solution"),
            model_pass = false,
            original_physics_pass = false,
            rows = rows,
        )
    end
    result["input_sha256"] == c.sha256 || throw(ArgumentError("解与输入哈希不同"))
    d = c.data
    e = d["electric"]
    h = d["heat"]
    s = result["values"]
    T = d["T"]
    cp = h["cp_J_kgK"]
    dt = d["dt_h"]*3600
    spec = r2_spec_from_dict(result["spec"])
    # 独立用历史回放到 t=0，再得到同一初始管温均值；不调用建模器的初值助手。
    function initial_average(pipe, side)
        history = pipe[side*"_history_K"]
        flowhistory = pipe["flow_history"]
        r = replay_water_mass(
            [last(history)],
            [last(flowhistory)],
            history[1:(end-1)],
            flowhistory[1:(end-1)];
            mass_kg = h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"],
            dt_h = d["dt_h"],
            epsilon_W_mK = pipe["epsilon_W_mK"],
            area_m2 = pipe["area_m2"],
            rho_kg_m3 = h["rho_kg_m3"],
            cp_J_kgK = cp,
            ambient_K = first(d["ambient_K"]),
        )
        return (last(history)+only(r.outlet))/2
    end
    V(key, i, t) = s[key][i][t]
    function record(id, scope, entity, t, residual, unit, tol)
        value = abs(Float64(residual))
        push!(
            rows,
            (
                equation = id,
                scope = scope,
                entity = string(entity),
                t = t,
                residual = value,
                unit = unit,
                tolerance = tol,
                pass = isfinite(value) && value <= tol,
            ),
        )
    end
    function bound(id, key, i, t, lo, hi, unit, tol)
        record(id, "model", i, t, max(lo-V(key, i, t), V(key, i, t)-hi, 0), unit, tol)
    end
    # 参考尺度取输入容量上界，而非解或残差。
    power_tol = 1e-6*(1+e["grid_max_MW"])
    flow_tol = 1e-6*(1+maximum(p["flow_max"] for p in h["pipes"]))
    for g in eachindex(d["devices"]), t in 1:T
        dev = d["devices"][g]
        kind = dev["kind"]
        bound(
            "3-3:8",
            "P_device",
            g,
            t,
            dev["P_min"],
            kind == "PV" ? dev["availability"][t] : dev["P_max"],
            "MW",
            power_tol,
        )
        expected = kind in ("CHP", "EB") ? dev["heat_ratio"]*V("P_device", g, t) : 0
        record(
            kind == "CHP" ? "3-2" : "3-7",
            "model",
            g,
            t,
            V("H_device", g, t)-expected,
            "MW",
            power_tol,
        )
    end
    for n in eachindex(e["nodes"]), t in 1:T
        node = e["nodes"][n]
        base = e["base_MVA"]
        gen = sum(
            (g["kind"] == "EB" ? -1 : 1)*V("P_device", i, t) for
            (i, g) in enumerate(d["devices"]) if g["electric_node"] == n;
            init = 0.0,
        )
        pbal = gen-node["P_MW"][t]+(n == 1 ? s["P_grid"][t] : 0.0)
        qbal = -node["Q_Mvar"][t]+(n == 1 ? s["Q_grid"][t] : 0.0)
        for (b, edge) in enumerate(e["edges"])
            if edge["to"] == n
                pbal += base*(V("P_branch", b, t)-edge["r_pu"]*V("ell", b, t))
                qbal += base*(V("Q_branch", b, t)-edge["x_pu"]*V("ell", b, t))
            elseif edge["from"] == n
                pbal -= base*V("P_branch", b, t)
                qbal -= base*V("Q_branch", b, t)
            end
        end
        record("3-9", "model", n, t, pbal, "MW", power_tol)
        record("3-10", "model", n, t, qbal, "Mvar", power_tol)
        bound("3-13", "v", n, t, e["v_min_pu"]^2, e["v_max_pu"]^2, "pu2", 1e-6)
        n == 1 && record("R2-root-voltage", "model", n, t, V("v", n, t)-1, "pu2", 1e-6)
    end
    for (b, edge) in enumerate(e["edges"]), t in 1:T
        p, q, l = V("P_branch", b, t), V("Q_branch", b, t), V("ell", b, t)
        vi, vj = V("v", edge["from"], t), V("v", edge["to"], t)
        r, x = edge["r_pu"], edge["x_pu"]
        record("3-11", "model", b, t, vj-vi+2*(r*p+x*q)-(r*r+x*x)*l, "pu2", 1e-6)
        record("3-12", "model", b, t, max(0, p*p+q*q-vi*l), "pu", 1e-6)
        record("pre-SOC-electric", "physics", b, t, p*p+q*q-vi*l, "pu", 1e-6)
        bound("3-14", "ell", b, t, 0, edge["ell_max_pu"], "pu2", 1e-6)
    end
    for t in 1:T
        record(
            "R2-grid-bounds",
            "model",
            1,
            t,
            max(
                0,
                -s["P_grid"][t],
                s["P_grid"][t]-e["grid_max_MW"],
                abs(s["Q_grid"][t])-e["grid_max_MW"],
            ),
            "MW",
            power_tol,
        )
    end
    for (j, node) in enumerate(h["nodes"]), t in 1:T
        role = node["role"]
        f = V("m_port", j, t)
        balance = (role == "source" ? f : role == "load" ? -f : 0.0)
        for (p, pipe) in enumerate(h["pipes"])
            pipe["to"] == j && (balance += V("m_pipe", p, t))
            pipe["from"] == j && (balance -= V("m_pipe", p, t))
        end
        record("3-21", "model", j, t, balance, "kg/s", flow_tol)
        bound("3-43", "m_port", j, t, node["flow_min"], node["flow_max"], "kg/s", flow_tol)
        delta = V("tau_S_port", j, t)-V("tau_R_port", j, t)
        heat = V("H_port", j, t)
        if role != "transit"
            scope = spec.heat_balance == :exact || result["fixed_flows"] ? "model" : "physics"
            record("3-17", scope, j, t, heat-cp/1e6*f*delta, "MW", power_tol)
            record("3-17-original", "physics", j, t, heat-cp/1e6*f*delta, "MW", power_tol)
            if spec.heat_balance == :mc && !result["fixed_flows"]
                db = (h["S_bounds_K"][1]-h["R_bounds_K"][2], h["S_bounds_K"][2]-h["R_bounds_K"][1])
                l, u = node["flow_min"], node["flow_max"]
                a, b = db
                # 独立展开四个半空间；不调用建模包络函数。
                w = heat*1e6/cp
                residual = max(
                    l*delta+a*f-l*a-w,
                    u*delta+b*f-u*b-w,
                    w-u*delta-a*f+u*a,
                    w-l*delta-b*f+l*b,
                    0,
                )
                record("3-42", "model", j, t, residual*cp/1e6, "MW", power_tol)
            end
        end
        target =
            role == "load" ? node["H_MW"][t] :
            role == "source" ?
            sum(
                V("H_device", g, t) for
                g in eachindex(d["devices"]) if d["devices"][g]["heat_node"] == j;
                init = 0.0,
            ) : 0.0
        record("3-19:20", "model", j, t, heat-target, "MW", power_tol)
        if role == "load"
            record("3-38", "model", j, t, V("tau_S_port", j, t)-V("tau_S_mix", j, t), "K", 1e-4)
            if !get(get(result, "operation", Dict()), "bounded_return", false)
                record(
                    "R2-load-return",
                    "model",
                    j,
                    t,
                    V("tau_R_port", j, t)-node["return_K"],
                    "K",
                    1e-4,
                )
            end
        elseif role == "source"
            record("3-37", "model", j, t, V("tau_R_port", j, t)-V("tau_R_mix", j, t), "K", 1e-4)
        end
        for side in ("S", "R")
            lo, hi = h[side*"_bounds_K"]
            for suffix in ("mix", "port")
                bound("3-41", "tau_"*side*"_"*suffix, j, t, lo, hi, "K", 1e-4)
            end
            bound(
                "3-24",
                "Phi_"*side,
                j,
                t,
                0,
                h["pressure_max_kPa"],
                "kPa",
                1e-6*h["pressure_max_kPa"],
            )
        end
        record(
            "3-24-order",
            "model",
            j,
            t,
            max(0, V("Phi_R", j, t)-V("Phi_S", j, t))/h["pressure_max_kPa"],
            "normalized",
            1e-6,
        )
    end
    zi = 0
    for side in ("S", "R"), j in eachindex(h["nodes"]), t in 1:T
        # 独立按端点和节点角色确定真实入流，不调用构建器的入流列表。
        inflows = Tuple{Float64,Float64}[]
        for (p, pipe) in enumerate(h["pipes"])
            pipe[side == "S" ? "to" : "from"] == j &&
                push!(inflows, (V("m_pipe", p, t), V("tau_"*side*"_out", p, t)))
        end
        role = h["nodes"][j]["role"]
        (side == "S" && role == "source" || side == "R" && role == "load") &&
            push!(inflows, (V("m_port", j, t), V("tau_"*side*"_port", j, t)))
        total = sum(first, inflows)
        mixed = total > 0 ? sum(f*τ for (f, τ) in inflows)/total : NaN
        actual = V("tau_"*side*"_mix", j, t)
        record(
            "3-35:36",
            spec.mixing == :exact || length(inflows) == 1 ? "model" : "physics",
            side*string(j),
            t,
            actual-mixed,
            "K",
            1e-4,
        )
        record("mix-original", "physics", side*string(j), t, actual-mixed, "K", 1e-4)
        if spec.mixing == :dominant && length(inflows) > 1
            zs = s["z_mix"][(zi+1):(zi+length(inflows))]
            zi += length(inflows)
            record("3-55", "model", side*string(j), t, sum(zs)-1, "1", 1e-6)
            maxflow = maximum(first, inflows)
            for (i, (f, τ)) in enumerate(inflows)
                record(
                    "3-55-binary",
                    "model",
                    side*string(j)*"/"*string(i),
                    t,
                    zs[i]-round(zs[i]),
                    "1",
                    1e-6,
                )
                # 先检查整数残差，再使用选择权重检查最大入流和温度关联。
                record("3-53:54", "model", side*string(j), t, zs[i]*(maxflow-f), "kg/s", flow_tol)
                record("3-56:57", "model", side*string(j), t, zs[i]*(actual-τ), "K", 1e-4)
            end
        end
    end
    for (p, pipe) in enumerate(h["pipes"])
        M = h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]
        for t in 1:T
            flow = V("m_pipe", p, t)
            bound("3-23", "m_pipe", p, t, pipe["flow_min"], pipe["flow_max"], "kg/s", flow_tol)
            result["fixed_flows"] && record(
                "R2-fixed-flow",
                "model",
                p,
                t,
                flow-(
                    haskey(result, "flow_schedule") ? result["flow_schedule"][p][t] :
                    pipe["fixed_flow"][t]
                ),
                "kg/s",
                flow_tol,
            )
            if spec.dynamics == :wmm
                α, β = s["alpha_"*string(p)][t], s["beta_"*string(p)][t]
                fs = [
                    t-lag > 0 ? V("m_pipe", p, t-lag) : pipe["flow_history"][end+t-lag] for
                    lag in 0:(length(α)-1)
                ]
                record("3-27", "model", p, t, sum(α .* fs)-M/dt, "kg/s", flow_tol)
                record("3-30", "model", p, t, sum(β[2:end] .* fs[2:end])-M/dt, "kg/s", flow_tol)
                record("3-32", "model", p, t, β[1]-1, "1", 1e-6)
                for (label, a) in (("3-28", α), ("3-31", β))
                    record(
                        label,
                        "model",
                        p,
                        t,
                        maximum(abs.((1 .- a[1:(end-1)]) .* a[2:end])),
                        "1",
                        1e-6,
                    )
                    record("3-29:32", "model", p, t, max(0, -minimum(a), maximum(a)-1), "1", 1e-6)
                end
            end
        end
        for side in ("S", "R")
            inlet, outlet = s["tau_"*side*"_in"][p], s["tau_"*side*"_out"][p]
            replay = replay_water_mass(
                inlet,
                s["m_pipe"][p],
                pipe[side*"_history_K"],
                pipe["flow_history"];
                mass_kg = M,
                dt_h = d["dt_h"],
                epsilon_W_mK = pipe["epsilon_W_mK"],
                area_m2 = pipe["area_m2"],
                rho_kg_m3 = h["rho_kg_m3"],
                cp_J_kgK = cp,
                ambient_K = d["ambient_K"][1],
            )
            for t in 1:T
                flow = V("m_pipe", p, t)
                lo, hi = h[side*"_bounds_K"]
                i, j = side == "S" ? (pipe["from"], pipe["to"]) : (pipe["to"], pipe["from"])
                record(
                    "3-39:40",
                    "model",
                    side*string(p),
                    t,
                    inlet[t]-V("tau_"*side*"_mix", i, t),
                    "K",
                    1e-4,
                )
                for suffix in ("in", "out")
                    bound("3-41", "tau_"*side*"_"*suffix, p, t, lo, hi, "K", 1e-4)
                end
                κ = V("kappa_"*side, p, t)
                drop = V("Phi_"*side, i, t)-V("Phi_"*side, j, t)
                bound(
                    "3-23-kappa",
                    "kappa_"*side,
                    p,
                    t,
                    0,
                    h["pressure_max_kPa"],
                    "kPa",
                    1e-6*h["pressure_max_kPa"],
                )
                record(
                    "3-22",
                    "model",
                    side*string(p),
                    t,
                    max(0, κ-drop)/h["pressure_max_kPa"],
                    "normalized",
                    1e-6,
                )
                record(
                    "3-26",
                    "model",
                    side*string(p),
                    t,
                    max(0, pipe["mu_kPa_s2_kg2"]*flow^2-κ)/h["pressure_max_kPa"],
                    "normalized",
                    1e-6,
                )
                record(
                    "3-25",
                    "physics",
                    side*string(p),
                    t,
                    (κ-pipe["mu_kPa_s2_kg2"]*flow^2)/h["pressure_max_kPa"],
                    "normalized",
                    1e-6,
                )
                # 环境逐时变化时对当前出管水应用该时刻环境，和建模约定相同。
                J = exp(
                    -pipe["epsilon_W_mK"]*replay.residence_s[t]/(h["rho_kg_m3"]*cp*pipe["area_m2"]),
                )
                expected = d["ambient_K"][t]+(replay.lossless[t]-d["ambient_K"][t])*J
                record("WMM-replay", "physics", side*string(p), t, outlet[t]-expected, "K", 1e-4)
                if spec.dynamics == :wmm
                    target =
                        spec.loss == :wmm ? expected :
                        replay.lossless[t]-pipe["epsilon_W_mK"]*pipe["length_m"]*(
                            h[side*"_reference_K"]-d["ambient_K"][t]
                        )/(cp*flow)
                    record("3-33:34", "model", side*string(p), t, outlet[t]-target, "K", 1e-4)
                else
                    average = (inlet[t]+outlet[t])/2
                    previous = t > 1 ? (inlet[t-1]+outlet[t-1])/2 : initial_average(pipe, side)
                    loss =
                        pipe["epsilon_W_mK"]*pipe["length_m"]*(
                            (spec.loss == :reference ? h[side*"_reference_K"] : average)-d["ambient_K"][t]
                        )
                    implied_product = -(M*cp/dt*(average-previous)+loss)/cp
                    delta = outlet[t]-inlet[t]
                    if spec.dynamics_product == :mc && !result["fixed_flows"]
                        l, u = pipe["flow_min"], pipe["flow_max"]
                        a, b = lo-hi, hi-lo
                        r = max(
                            l*delta+a*flow-l*a-implied_product,
                            u*delta+b*flow-u*b-implied_product,
                            implied_product-u*delta-a*flow+u*a,
                            implied_product-l*delta-b*flow+l*b,
                            0,
                        )
                        record("3-52-MC", "model", side*string(p), t, r*cp/1e6, "MW", power_tol)
                    else
                        record(
                            "3-52",
                            "model",
                            side*string(p),
                            t,
                            (implied_product-flow*delta)*cp/1e6,
                            "MW",
                            power_tol,
                        )
                    end
                    record(
                        "3-52-unrelaxed",
                        "physics",
                        side*string(p),
                        t,
                        (implied_product-flow*delta)*cp/1e6,
                        "MW",
                        power_tol,
                    )
                end
            end
        end
    end
    if haskey(s, "E_DHN")
        E0 = 0.0
        Emax = 0.0
        for pipe in h["pipes"], side in ("S", "R")
            factor = h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]*cp/3.6e9
            E0 += factor*(initial_average(pipe, side)-h[side*"_bounds_K"][1])
            Emax += factor*(h[side*"_bounds_K"][2]-h[side*"_bounds_K"][1])
        end
        etol = 1e-6*(1+Emax)
        record("3-46-project", "model", 0, 0, s["E_DHN"][1]-E0, "MWh", etol)
        for t in 0:T
            record(
                "3-45",
                "model",
                0,
                t,
                max(0, -s["E_DHN"][t+1], s["E_DHN"][t+1]-Emax),
                "MWh",
                etol,
            )
            t == 0 && continue
            net = sum(
                (node["role"] == "source" ? 1 : -1)*V("H_port", j, t) for
                (j, node) in enumerate(h["nodes"])
            )
            losses = sum(
                pipe["epsilon_W_mK"]*pipe["length_m"]*(
                    (
                        spec.loss == :reference ? h[side*"_reference_K"] :
                        (V("tau_"*side*"_in", p, t)+V("tau_"*side*"_out", p, t))/2
                    )-d["ambient_K"][t]
                )/1e6 for (p, pipe) in enumerate(h["pipes"]), side in ("S", "R")
            )
            record(
                "3-44",
                "model",
                0,
                t,
                s["E_DHN"][t+1]-s["E_DHN"][t]-d["dt_h"]*(net-losses),
                "MWh",
                etol,
            )
            temperature_inventory = sum(
                h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]*cp/3.6e9 * (
                    (V("tau_"*side*"_in", p, t)+V("tau_"*side*"_out", p, t))/2-h[side*"_bounds_K"][1]
                ) for (p, pipe) in enumerate(h["pipes"]), side in ("S", "R")
            )
            record(
                "energy-temperature-consistency",
                "physics",
                0,
                t,
                s["E_DHN"][t+1]-temperature_inventory,
                "MWh",
                etol,
            )
        end
    end
    total =
        d["dt_h"]*(
            sum(d["grid_price"] .* s["P_grid"])+sum(
                g["cost_per_MWh"]*sum(s["P_device"][i]) for (i, g) in enumerate(d["devices"])
            )
        )
    record("3-1", "model", 0, 0, total-result["objective"], "currency", 1e-6*max(1, abs(total)))
    r3_operation_rows!(record, c, result)
    model_pass = all(row -> row.pass, filter(r -> r.scope == "model", rows))
    physics_pass = model_pass && all(row -> row.pass, filter(r -> r.scope == "physics", rows))
    return (
        status = !model_pass ? "model_residual_failed" :
                 physics_pass ? "checked_relations_pass" : "original_physics_failed",
        model_pass = model_pass,
        original_physics_pass = physics_pass,
        rows = rows,
    )
end
# endregion r2-verify
