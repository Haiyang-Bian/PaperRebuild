# region r1-model
"""
    build_r1_model(case; optimizer, modes=nothing)

构建首批合成两节点 JuMP 模型，不求解、不写文件。
返回模型、变量字典、按稳定公式 ID 组织的约束和案例。`modes=(bs, hs)` 固定全窗口互斥状态；
省略时使用两个二元变量，需要 MISOCP 求解器。电网式（2-28）采用锥松弛，原等式另行验证。
CHP 为作者常效率近似；HS 为单位充放效率特例；热网为给定流量运行点，不含水压优化。
"""
function build_r1_model(c::R1Case; optimizer, modes = nothing)
    d = c.data
    T, Δt = d["time"]["T"], d["time"]["dt_h"]
    dev, e, h, b, dem = (d[k] for k in ("devices", "electric", "heat", "building", "demand"))
    m = Model(optimizer)
    set_silent(m)
    vars = Dict{String,Any}()
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
        vars[name] = @variable(m, [1:T], lower_bound = 0, base_name = name)
    end
    for name in ("v", "tau_S_in", "tau_S_out", "tau_R_in", "tau_R_out")
        vars[name] = @variable(m, [1:T], base_name = name)
    end
    for name in ("E_BS", "E_HS", "tau_IN")
        vars[name] = @variable(m, [0:T], base_name = name)
    end
    for (i, name) in enumerate(("z_BS", "z_HS"))
        vars[name] = @variable(m, binary = true, base_name = name)
        if !isnothing(modes)
            length(modes) == 2 && all(x -> x in (0, 1), modes) ||
                throw(ArgumentError("互斥模式必须为两个 0/1"))
            unset_binary(vars[name])
            fix(vars[name], modes[i]; force = true)
        end
    end
    con = Dict{String,Vector{Any}}()
    record(id, ref) = push!(get!(con, id, Any[]), ref)
    bound(id, name, lo, hi) = foreach(x -> record(id, @constraint(m, lo <= x <= hi)), vars[name])
    bound("ch02-002", "P_CHP", dev["P_CHP_min"], dev["P_CHP_max"])
    bound("ch02-003", "H_CHP", dev["H_CHP_min"], dev["H_CHP_max"])
    bound("ch02-009", "P_EB", 0, dev["P_EB_max"])
    bound("ch02-011", "P_HP", 0, dev["P_HP_max"])
    bound("ch02-014", "E_BS", 0, dev["E_BS_max"])
    bound("ch02-018", "E_HS", 0, dev["E_HS_max"])
    bound("ch02-026", "v", e["V_min_pu"]^2, e["V_max_pu"]^2)
    bound("ch02-027", "l", 0, e["l_max_pu"])
    for (id, name) in (
        ("ch02-031", "tau_S_in"),
        ("ch02-031", "tau_S_out"),
        ("ch02-033", "tau_R_in"),
        ("ch02-033", "tau_R_out"),
    )
        # 所有端点的共同温度界是教学案例附加边界；原式只对节点端点给界。
        bound(id, name, h["tau_min"], h["tau_max"])
    end
    bound("ch02-073", "tau_IN", b["tau_min"], b["tau_max"])
    bound("ch02-076", "P_DH", 0, b["P_DH_max"])
    for (s, id) in (("BS", "ch02-015"), ("HS", "ch02-019"))
        record(id, @constraint(m, vars["E_$s"][0] == dev["E_$(s)_initial"]))
        record(id, @constraint(m, vars["E_$s"][T] == vars["E_$s"][0]))
    end
    record("ch02-072", @constraint(m, vars["tau_IN"][0] == b["tau_initial"]))
    kernel =
        fixed_flow_kernel(h["m"], h["rho_w"], h["A"], h["L"], Δt, h["epsilon_W_mK"]; c_w = h["c_w"])
    for side in ("S", "R")
        τ_out = pipe_outlet(vars["tau_$(side)_in"], h["history_$side"], kernel, h["tau_AM"])
        for t in 1:T
            record("ch02-047", @constraint(m, vars["tau_$(side)_out"][t] == τ_out[t]))
        end
    end
    for t in 1:T
        v(name) = vars[name][t]
        record(
            "ch02-001",
            @constraint(m, v("H_CHP") == chp_heat(v("P_CHP"), dev["eta_G"], dev["eta_loss"]))
        )
        record("ch02-006", @constraint(m, v("P_PV") <= dem["P_PV_available"][t]))
        record("project-wt-disabled", @constraint(m, v("P_WT") == 0))
        for (name, id) in (("EB", "ch02-008"), ("HP", "ch02-010"))
            record(id, @constraint(m, v("H_$name") == dev["COP_$name"] * v("P_$name")))
        end
        for (s, power, id) in (("BS", "P", "ch02-013"), ("HS", "H", "ch02-017"))
            record(
                id,
                @constraint(m, v("$(power)_$(s)_ch") <= dev["$(s)_power_max"] * vars["z_$s"])
            )
            record(
                id,
                @constraint(
                    m,
                    v("$(power)_$(s)_dis") <= dev["$(s)_power_max"] * (1 - vars["z_$s"])
                )
            )
        end
        # 状态 t 对应第 t 段结束；原文的 E_{t+1} 对应这里的 E[t]，详见索引表。
        record(
            "ch02-012",
            @constraint(
                m,
                vars["E_BS"][t] == battery_step(
                    vars["E_BS"][t-1],
                    v("P_BS_ch"),
                    v("P_BS_dis"),
                    dev["eta_BS_ch"],
                    dev["eta_BS_dis"],
                    Δt,
                )
            )
        )
        record(
            "ch02-016",
            @constraint(
                m,
                vars["E_HS"][t] == heat_storage_step_paper(
                    vars["E_HS"][t-1],
                    v("H_HS_ch"),
                    v("H_HS_dis"),
                    dev["eta_HS_ch"],
                    dev["eta_HS_dis"],
                    dev["eta_HS_loss"],
                    Δt,
                )
            )
        )
        S, r, x = e["S_base_MVA"], e["r_pu"], e["x_pu"]
        # CHP/PV/BS 接于节点 2。式 2-20 原文漏 EB，案例显式加入 EB 与户用电热消耗。
        P_net =
            v("P_CHP") + v("P_PV") - v("P_HP") - v("P_EB") - v("P_BS_ch") + v("P_BS_dis") -
            dem["P_D"][t] - v("P_DH")
        record("ch02-022", @constraint(m, P_net + v("P_grid") - S * r * v("l") == 0))
        record("ch02-023", @constraint(m, v("Q_grid") - S * x * v("l") == dem["Q_D"][t]))
        record(
            "ch02-024",
            @constraint(
                m,
                v("v") ==
                1 - 2 * (r * v("P_grid") / S + x * v("Q_grid") / S) + (r^2 + x^2) * v("l")
            )
        )
        # 根电压平方为 1 pu；l 是电流平方，不是电流幅值。
        record(
            "ch02-028",
            @constraint(
                m,
                [v("l") + 1, 2v("P_grid") / S, 2v("Q_grid") / S, v("l") - 1] in SecondOrderCone()
            )
        )
        H_source = v("H_CHP") + v("H_HP") + v("H_EB") - v("H_HS_ch") + v("H_HS_dis")
        record(
            "ch02-029",
            @constraint(
                m,
                H_source == heat_power(h["m"], v("tau_S_in"), v("tau_R_out"); c_w = h["c_w"])
            )
        )
        record(
            "ch02-032",
            @constraint(
                m,
                v("H_D") == heat_power(h["m"], v("tau_S_out"), v("tau_R_in"); c_w = h["c_w"])
            )
        )
        record(
            "ch02-072",
            @constraint(
                m,
                b["eta_H"] * v("H_D_hat") + b["U"] * (dem["tau_AM"][t] - v("tau_IN")) ==
                v("tau_IN") - vars["tau_IN"][t-1]
            )
        )
        record("ch02-075", @constraint(m, v("H_D") == v("H_D_hat") - v("H_DH")))
        record("ch02-076", @constraint(m, v("H_DH") == b["eta_DH"] * v("P_DH")))
    end
    # 教学成本，非第 2 章市场出清模型；不允许售电，不增加隐形失负荷松弛。
    @objective(
        m,
        Min,
        Δt * sum(
            d["cost"]["grid_per_MWh"][t] * vars["P_grid"][t] +
            d["cost"]["CHP_per_MWh"] * vars["P_CHP"][t] for t in 1:T
        )
    )
    return (model = m, variables = vars, constraints = con, case = c)
end
# endregion r1-model

# region r1-solve
"""
    solve_r1_case(case; optimizer, enumerate_modes=true, budget_sec=60.0)

求解并返回状态、目标、可得的界、分支日志和数值解，不写文件。
默认穷举原文两个全窗口储能状态的四种组合，每个子问题为 SOCP，可用 Clarabel。
全部组合均被求解器报告最优或不可行才标记完成；预算耗尽/未知状态不伪装为最优。
`enumerate_modes=false` 直接求解 MISOCP（如 Gurobi），只在获得可行结果时提取数值。
"""
function solve_r1_case(c::R1Case; optimizer, enumerate_modes = true, budget_sec = 60.0)
    budget_sec > 0 || throw(ArgumentError("预算必须为正"))
    started = time()
    patterns = enumerate_modes ? [(i, j) for i in 0:1 for j in 0:1] : [nothing]
    logs = Dict{String,Any}[]
    best = nothing
    for pattern in patterns
        remaining = budget_sec - (time() - started)
        remaining > 0 || break
        built = build_r1_model(c; optimizer, modes = pattern)
        remaining = budget_sec - (time() - started)
        remaining > 0 || break
        set_time_limit_sec(built.model, remaining)
        optimize!(built.model)
        status = termination_status(built.model)
        feasible = primal_status(built.model) == MOI.FEASIBLE_POINT
        entry = Dict{String,Any}(
            "mode" => isnothing(pattern) ? "binary" : join(pattern, ","),
            "termination" => string(status),
            "primal" => string(primal_status(built.model)),
        )
        entry["solver"] = solver_name(built.model)
        entry["JuMP_version"] = string(Base.pkgversion(JuMP))
        try
            entry["solver_version"] = MOI.get(backend(built.model), MOI.SolverVersion())
        catch err
            err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed} || rethrow()
            entry["solver_version"] = "unavailable; see environment manifest hash"
        end
        if feasible
            entry["objective"] = objective_value(built.model)
            try
                entry["bound"] = objective_bound(built.model)
            catch err
                err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed} || rethrow()
                if dual_status(built.model) == MOI.FEASIBLE_POINT
                    entry["bound"] = dual_objective_value(built.model)
                    entry["bound_kind"] = "solver_dual_objective"
                end
            end
            if isnothing(best) || entry["objective"] < best["objective"]
                vals = Dict{String,Any}(
                    k => v isa VariableRef ? value(v) : collect(value.(v)) for
                    (k, v) in built.variables
                )
                best = Dict{String,Any}("objective" => entry["objective"], "values" => vals)
            end
        end
        push!(logs, entry)
    end
    complete =
        length(logs) == length(patterns) && all(
            x ->
                x["termination"] == "INFEASIBLE" ||
                (x["termination"] == "OPTIMAL" && x["primal"] == "FEASIBLE_POINT"),
            logs,
        )
    status = complete ? (isnothing(best) ? "infeasible" : "solver_optimal") : "incomplete"
    result = Dict{String,Any}(
        "status" => status,
        "elapsed_sec" => time() - started,
        "budget_sec" => budget_sec,
        "subproblems" => logs,
        "input_sha256" => c.sha256,
        "method" => enumerate_modes ? "four_horizon_modes_socp" : "misocp",
        "case_origin" => "synthetic",
    )
    if !isnothing(best)
        merge!(result, best)
        bounds = [x["bound"] for x in logs if haskey(x, "bound") && isfinite(x["bound"])]
        feasible_logs = filter(x -> x["termination"] != "INFEASIBLE", logs)
        if complete && length(bounds) == length(feasible_logs)
            result["bound"] = minimum(bounds)
        end
    end
    return result
end
# endregion r1-solve
