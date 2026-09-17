# 所有约束通过公式 ID 登记；变量界由输入契约给出，禁止任意大 M。
function r2_add!(cs, id, constraint)
    push!(get!(cs, id, Any[]), constraint)
    return constraint
end

function r2_product!(model, cs, x, y, xb, yb, mode, id)
    l, u = xb
    a, b = yb
    mccormick_bounds(l, a, xb, yb) # 包络界的共同前置检查。
    w = @variable(
        model,
        lower_bound = minimum((l*a, l*b, u*a, u*b)),
        upper_bound = maximum((l*a, l*b, u*a, u*b))
    )
    if x isa Real || y isa Real || mode == :exact
        r2_add!(cs, id, @constraint(model, w == x * y))
    else
        for (sense, expression) in
            ((:lo, l*y+a*x-l*a), (:lo, u*y+b*x-u*b), (:hi, u*y+a*x-u*a), (:hi, l*y+b*x-l*b))
            r2_add!(
                cs,
                id,
                sense == :lo ? @constraint(model, w >= expression) :
                @constraint(model, w <= expression),
            )
        end
    end
    return w
end

function r2_inflows(d, side, node)
    p = d["heat"]["pipes"]
    # 回水方向与供水相反；本地热源只向供水注入，本地负荷只向回水注入。
    edges = findall(e -> e[side == "S" ? "to" : "from"] == node, p)
    local_role = side == "S" ? "source" : "load"
    return edges, d["heat"]["nodes"][node]["role"] == local_role
end

function r2_choice_keys(d)
    keys = Tuple{String,Int,Int,Int}[]
    for side in ("S", "R"), j in eachindex(d["heat"]["nodes"]), t in 1:d["T"]
        edges, local_in = r2_inflows(d, side, j)
        count = length(edges) + Int(local_in)
        count > 1 && push!(keys, (side, j, t, count))
    end
    return keys
end

"""
    r2_model_class(model)

检查实际 MOI 约束类型。仅线性、变量界、整数和二阶锥时返回 SOCP/MISOCP；
发现二次等式或非线性表达式返回 nonconvex。分类不构成可行性或最优性证明。
"""
function r2_model_class(model)
    nonlinear = any(list_of_constraint_types(model)) do (F, S)
        !(
            F in (VariableRef, AffExpr, Vector{AffExpr}, Vector{VariableRef}) && (
                S <: Union{
                    MOI.EqualTo,
                    MOI.LessThan,
                    MOI.GreaterThan,
                    MOI.Interval,
                    MOI.ZeroOne,
                    MOI.Integer,
                    MOI.SecondOrderCone,
                    MOI.RotatedSecondOrderCone,
                }
            )
        )
    end
    nonlinear && return "nonconvex"
    return any(is_binary, all_variables(model)) ? "MISOCP" : "SOCP"
end

# region r2-model
"""
    build_r2_model(case; spec=R2Spec(), optimizer=nothing, fixed_flows=false, flow_schedule=nothing, choices=nothing)

建立第3章固定方向径向电热模型。单位与适用范围见 [`load_r2_case`](@ref)。
返回 model、variables、constraints（式号映射）、class 和 status；不求解或写文件。
literal 版本返回 blocked 和问题 ID。`fixed_flows` 固定流量得到子问题；
可选 `flow_schedule[p,t]` 使用kg/s且独立于案例来源，只允许在固定模式传入；省略时沿用案例计划。
`choices` 为最大入流选择的枚举索引，省略时建立二进制变量。
WMM 保留 α/β 互补和热输运非线性；SCHPD 补全版对剩余乘积逐项建包络。
"""
function build_r2_model(
    c::R2Case;
    spec = R2Spec(),
    optimizer = nothing,
    fixed_flows = false,
    flow_schedule = nothing,
    choices = nothing,
)
    validate_r2_input(c.data)
    !fixed_flows &&
        !isnothing(flow_schedule) &&
        throw(ArgumentError("flow_schedule仅用于固定流量模式"))
    mf = fixed_flows ? r2_flow_matrix(c, flow_schedule) : nothing
    if spec.formulation in (:wmm_literal, :schpd_literal)
        issues =
            spec.formulation == :wmm_literal ? ["R2-C01", "R2-C02"] :
            ["R2-C01", "R2-C03", "R2-C04", "R2-C05", "Q10"]
        return (; status = "blocked", issues, model = nothing, class = "unresolved")
    end
    d = c.data
    e = d["electric"]
    h = d["heat"]
    T = d["T"]
    N = length(e["nodes"])
    K = length(h["nodes"])
    G = length(d["devices"])
    B = length(e["edges"])
    E = length(h["pipes"])
    model = isnothing(optimizer) ? Model() : Model(optimizer)
    vars = Dict{String,Any}()
    cs = Dict{String,Vector{Any}}()
    add(id, constraint) = r2_add!(cs, id, constraint)
    var(key, array) = (vars[key] = array)
    base = e["base_MVA"]
    cp = h["cp_J_kgK"]
    dt = d["dt_h"] * 3600
    PG = var("P_device", @variable(model, [1:G, 1:T]))
    HG = var("H_device", @variable(model, [1:G, 1:T]))
    grid = var("P_grid", @variable(model, [1:T], lower_bound = 0, upper_bound = e["grid_max_MW"]))
    qgrid = var(
        "Q_grid",
        @variable(model, [1:T], lower_bound = -e["grid_max_MW"], upper_bound = e["grid_max_MW"])
    )
    for g in 1:G, t in 1:T
        dev = d["devices"][g]
        kind = dev["kind"]
        set_lower_bound(PG[g, t], dev["P_min"])
        set_upper_bound(PG[g, t], kind == "PV" ? dev["availability"][t] : dev["P_max"])
        if kind in ("CHP", "EB")
            set_lower_bound(HG[g, t], dev["heat_ratio"] * dev["P_min"])
            set_upper_bound(HG[g, t], dev["heat_ratio"] * dev["P_max"])
            add(
                kind == "CHP" ? "3-2" : "3-7",
                @constraint(model, HG[g, t] == dev["heat_ratio"] * PG[g, t])
            )
        else
            fix(HG[g, t], 0; force = true)
        end
    end
    P = var(
        "P_branch",
        @variable(
            model,
            [1:B, 1:T],
            lower_bound = -e["grid_max_MW"] / base,
            upper_bound = e["grid_max_MW"] / base
        )
    )
    Q = var(
        "Q_branch",
        @variable(
            model,
            [1:B, 1:T],
            lower_bound = -e["grid_max_MW"] / base,
            upper_bound = e["grid_max_MW"] / base
        )
    )
    v = var(
        "v",
        @variable(model, [1:N, 1:T], lower_bound = e["v_min_pu"]^2, upper_bound = e["v_max_pu"]^2)
    )
    ell = var("ell", @variable(model, [1:B, 1:T], lower_bound = 0))
    for b in 1:B, t in 1:T
        ed = e["edges"][b]
        i = ed["from"]
        j = ed["to"]
        r = ed["r_pu"]
        x = ed["x_pu"]
        set_upper_bound(ell[b, t], ed["ell_max_pu"])
        add(
            "3-11",
            @constraint(model, v[j, t] == v[i, t] - 2*(r*P[b, t]+x*Q[b, t]) + (r^2+x^2)*ell[b, t])
        )
        add(
            "3-12",
            @constraint(
                model,
                [v[i, t]+ell[b, t], 2P[b, t], 2Q[b, t], ell[b, t]-v[i, t]] in SecondOrderCone()
            )
        )
    end
    for t in 1:T
        fix(v[1, t], 1; force = true)
    end
    for n in 1:N, t in 1:T
        inc = findall(b -> b["to"] == n, e["edges"])
        out = findall(b -> b["from"] == n, e["edges"])
        gs = findall(g -> g["electric_node"] == n, d["devices"])
        injection =
            sum((d["devices"][g]["kind"] == "EB" ? -1 : 1)*PG[g, t] for g in gs; init = 0.0) -
            e["nodes"][n]["P_MW"][t]
        add(
            "3-9",
            @constraint(
                model,
                injection/base +
                (n == 1 ? grid[t]/base : 0) +
                sum(P[b, t]-e["edges"][b]["r_pu"]*ell[b, t] for b in inc; init = 0.0) ==
                sum(P[b, t] for b in out; init = 0.0)
            )
        )
        # 项目边界：所有设备单位功率因数，根节点提供无功。
        add(
            "3-10",
            @constraint(
                model,
                (n == 1 ? qgrid[t]/base : 0) - e["nodes"][n]["Q_Mvar"][t]/base +
                sum(Q[b, t]-e["edges"][b]["x_pu"]*ell[b, t] for b in inc; init = 0.0) ==
                sum(Q[b, t] for b in out; init = 0.0)
            )
        )
    end
    m = var("m_pipe", @variable(model, [1:E, 1:T]))
    port = var("m_port", @variable(model, [1:K, 1:T]))
    for p in 1:E, t in 1:T
        pipe = h["pipes"][p]
        set_lower_bound(m[p, t], pipe["flow_min"])
        set_upper_bound(m[p, t], pipe["flow_max"])
        fixed_flows && fix(m[p, t], mf[p, t]; force = true)
    end
    for j in 1:K, t in 1:T
        node = h["nodes"][j]
        role = node["role"]
        set_lower_bound(port[j, t], node["flow_min"])
        set_upper_bound(port[j, t], node["flow_max"])
        role == "transit" && fix(port[j, t], 0; force = true)
        inflow = sum(m[p, t] for p in 1:E if h["pipes"][p]["to"] == j; init = 0.0)
        outflow = sum(m[p, t] for p in 1:E if h["pipes"][p]["from"] == j; init = 0.0)
        add(
            "3-21",
            @constraint(
                model,
                inflow + (role == "source" ? port[j, t] : 0) ==
                outflow + (role == "load" ? port[j, t] : 0)
            )
        )
    end
    for side in ("S", "R")
        lo, hi = h[side*"_bounds_K"]
        var("tau_"*side*"_in", @variable(model, [1:E, 1:T], lower_bound = lo, upper_bound = hi))
        var("tau_"*side*"_out", @variable(model, [1:E, 1:T], lower_bound = lo, upper_bound = hi))
        var("tau_"*side*"_mix", @variable(model, [1:K, 1:T], lower_bound = lo, upper_bound = hi))
        var("tau_"*side*"_port", @variable(model, [1:K, 1:T], lower_bound = lo, upper_bound = hi))
        pressure = var(
            "Phi_"*side,
            @variable(model, [1:K, 1:T], lower_bound = 0, upper_bound = h["pressure_max_kPa"])
        )
        κ = var(
            "kappa_"*side,
            @variable(model, [1:E, 1:T], lower_bound = 0, upper_bound = h["pressure_max_kPa"])
        )
        for p in 1:E, t in 1:T
            pipe = h["pipes"][p]
            i = pipe["from"]
            j = pipe["to"]
            side == "R" && ((i, j) = (j, i))
            add("3-22", @constraint(model, pressure[i, t] - pressure[j, t] >= κ[p, t]))
            add(
                "3-26",
                @constraint(
                    model,
                    [κ[p, t]+1, 2sqrt(pipe["mu_kPa_s2_kg2"])*m[p, t], κ[p, t]-1] in
                    SecondOrderCone()
                )
            )
            add(
                side == "S" ? "3-39" : "3-40",
                @constraint(model, vars["tau_"*side*"_in"][p, t] == vars["tau_"*side*"_mix"][i, t])
            )
        end
    end
    for j in 1:K, t in 1:T
        add("3-24", @constraint(model, vars["Phi_S"][j, t] >= vars["Phi_R"][j, t]))
        role = h["nodes"][j]["role"]
        if role == "load"
            fix(vars["tau_R_port"][j, t], h["nodes"][j]["return_K"]; force = true)
            add("3-38", @constraint(model, vars["tau_S_port"][j, t] == vars["tau_S_mix"][j, t]))
        elseif role == "source"
            add("3-37", @constraint(model, vars["tau_R_port"][j, t] == vars["tau_R_mix"][j, t]))
        end
    end
    choices_index = 0
    zvars = VariableRef[]
    for side in ("S", "R"), j in 1:K, t in 1:T
        edges, local_in = r2_inflows(d, side, j)
        streams = Any[]
        for p in edges
            pipe = h["pipes"][p]
            push!(
                streams,
                (m[p, t], vars["tau_"*side*"_out"][p, t], (pipe["flow_min"], pipe["flow_max"])),
            )
        end
        local_in && push!(
            streams,
            (
                port[j, t],
                vars["tau_"*side*"_port"][j, t],
                (h["nodes"][j]["flow_min"], h["nodes"][j]["flow_max"]),
            ),
        )
        isempty(streams) && throw(ArgumentError("每个供回水节点必须有显式入流边界"))
        mix = vars["tau_"*side*"_mix"][j, t]
        if length(streams) == 1
            add(side == "S" ? "3-35" : "3-36", @constraint(model, mix == streams[1][2]))
        elseif spec.mixing == :exact
            # 固定流量时由树的质量守恒唯一确定本地端口幅值，避免伪非线性。
            ms = fixed_flows ? r2_fixed_port_flows(d, mf) : nothing
            fs =
                fixed_flows ? vcat([mf[p, t] for p in edges], local_in ? [ms[j, t]] : Float64[]) :
                [s[1] for s in streams]
            add(
                side == "S" ? "3-35" : "3-36",
                @constraint(
                    model,
                    sum(fs)*mix == sum(fs[i]*streams[i][2] for i in eachindex(streams))
                )
            )
        else
            choices_index += 1
            Mflow = maximum(s[3][2] for s in streams) - minimum(s[3][1] for s in streams)
            Mtemp = h[side*"_bounds_K"][2] - h[side*"_bounds_K"][1]
            maximum_flow =
                @variable(model, lower_bound = 0, upper_bound = maximum(s[3][2] for s in streams))
            zs = @variable(model, [1:length(streams)], binary = true)
            if !isnothing(choices)
                for i in eachindex(streams)
                    unset_binary(zs[i])
                    fix(zs[i], Int(i == choices[choices_index]); force = true)
                end
            end
            append!(zvars, zs)
            add("3-55", @constraint(model, sum(zs) == 1))
            for (i, s) in enumerate(streams)
                add("3-53", @constraint(model, maximum_flow >= s[1]))
                add("3-54", @constraint(model, maximum_flow <= s[1] + (1-zs[i])*Mflow))
                add("3-56", @constraint(model, mix-s[2] <= (1-zs[i])*Mtemp))
                add("3-57", @constraint(model, mix-s[2] >= -(1-zs[i])*Mtemp))
            end
        end
    end
    vars["z_mix"] = zvars
    Hport = var("H_port", @variable(model, [1:K, 1:T], lower_bound = 0))
    fixed_ports = fixed_flows ? r2_fixed_port_flows(d, mf) : nothing
    for j in 1:K, t in 1:T
        node = h["nodes"][j]
        role = node["role"]
        if role == "transit"
            fix(Hport[j, t], 0; force = true)
            continue
        end
        difference = vars["tau_S_port"][j, t] - vars["tau_R_port"][j, t]
        bounds = (h["S_bounds_K"][1]-h["R_bounds_K"][2], h["S_bounds_K"][2]-h["R_bounds_K"][1])
        f = fixed_flows ? fixed_ports[j, t] : port[j, t]
        w = r2_product!(
            model,
            cs,
            f,
            difference,
            (node["flow_min"], node["flow_max"]),
            bounds,
            spec.heat_balance,
            spec.heat_balance == :exact ? "3-17" : "3-42",
        )
        add("3-17", @constraint(model, Hport[j, t] == cp/1e6*w))
        if role == "source"
            add(
                "3-19",
                @constraint(
                    model,
                    Hport[j, t] ==
                    sum(HG[g, t] for g in 1:G if d["devices"][g]["heat_node"] == j; init = 0.0)
                )
            )
        else
            fix(Hport[j, t], node["H_MW"][t]; force = true)
        end
    end
    # 每根管的 α/β 共用于供回水；回水采用相反的入口历史。
    if spec.dynamics == :wmm
        for p in 1:E
            pipe = h["pipes"][p]
            M = h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]
            Td = ceil(Int, M/(dt*pipe["flow_min"]))+1
            α = @variable(model, [1:T, 0:Td], lower_bound = 0, upper_bound = 1)
            β = @variable(model, [1:T, 0:Td], lower_bound = 0, upper_bound = 1)
            vars["alpha_"*string(p)] = α
            vars["beta_"*string(p)] = β
            for t in 1:T
                historical_flow(s) =
                    t-s > 0 ? (fixed_flows ? mf[p, t-s] : m[p, t-s]) : pipe["flow_history"][end+t-s]
                fs = [historical_flow(s) for s in 0:Td]
                if fixed_flows
                    weights = water_mass_weights(fs, M, dt)
                    for s in 0:Td
                        fix(α[t, s], weights.α[s+1]; force = true)
                        fix(β[t, s], weights.β[s+1]; force = true)
                    end
                    aa, bb = weights.α, weights.β
                else
                    aa, bb = [α[t, s] for s in 0:Td], [β[t, s] for s in 0:Td]
                    fix(β[t, 0], 1; force = true)
                    for s in 0:(Td-1)
                        add("3-28", @constraint(model, (1-α[t, s])*α[t, s+1] == 0))
                        add("3-31", @constraint(model, (1-β[t, s])*β[t, s+1] == 0))
                    end
                    add("3-27", @constraint(model, sum(aa[i]*fs[i] for i in 1:(Td+1)) == M/dt))
                    add("3-30", @constraint(model, sum(bb[i]*fs[i] for i in 2:(Td+1)) == M/dt))
                end
                for side in ("S", "R")
                    lo, hi = h[side*"_bounds_K"]
                    inlet, outlet = vars["tau_"*side*"_in"], vars["tau_"*side*"_out"]
                    temps =
                        [t-s > 0 ? inlet[p, t-s] : pipe[side*"_history_K"][end+t-s] for s in 0:Td]
                    star = @variable(model, lower_bound = lo, upper_bound = hi)
                    # 分解三因子乘积为有界二因子，保持原等式而非额外松弛。
                    mass_w =
                        fixed_flows ? [(bb[i]-aa[i])*fs[i] for i in 1:(Td+1)] :
                        [
                            r2_product!(
                                model,
                                cs,
                                bb[i]-aa[i],
                                fs[i],
                                (-1.0, 1.0),
                                (pipe["flow_min"], pipe["flow_max"]),
                                :exact,
                                "3-33",
                            ) for i in 1:(Td+1)
                        ]
                    add(
                        "3-33",
                        @constraint(model, fs[1]*star == sum(mass_w[i]*temps[i] for i in 1:(Td+1)))
                    )
                    if spec.loss == :wmm
                        exponent =
                            -pipe["epsilon_W_mK"]*dt/(2cp*h["rho_kg_m3"]*pipe["area_m2"])*(
                                sum(aa)+sum(bb[2:end])
                            )
                        attenuation =
                            fixed_flows ? exp(exponent) : @expression(model, exp(exponent))
                        add(
                            "3-34",
                            @constraint(
                                model,
                                outlet[p, t] ==
                                d["ambient_K"][t] + (star-d["ambient_K"][t])*attenuation
                            )
                        )
                    else
                        loss =
                            pipe["epsilon_W_mK"]*pipe["length_m"]*(
                                h[side*"_reference_K"]-d["ambient_K"][t]
                            )
                        add("3-50", @constraint(model, cp*fs[1]*(star-outlet[p, t]) == loss))
                    end
                end
            end
        end
    else
        for p in 1:E, side in ("S", "R"), t in 1:T
            pipe = h["pipes"][p]
            lo, hi = h[side*"_bounds_K"]
            inlet, outlet = vars["tau_"*side*"_in"], vars["tau_"*side*"_out"]
            avg = (inlet[p, t]+outlet[p, t])/2
            previous = t > 1 ? (inlet[p, t-1]+outlet[p, t-1])/2 : r2_initial_average(d, pipe, side)
            f = fixed_flows ? mf[p, t] : m[p, t]
            product = r2_product!(
                model,
                cs,
                f,
                outlet[p, t]-inlet[p, t],
                (pipe["flow_min"], pipe["flow_max"]),
                (lo-hi, hi-lo),
                spec.dynamics_product,
                "3-52",
            )
            # 项目 R2-C05：有限体积能量方程，三项都为 W；秒与比热显式出现。
            loss =
                pipe["epsilon_W_mK"]*pipe["length_m"]*(
                    (spec.loss == :reference ? h[side*"_reference_K"] : avg)-d["ambient_K"][t]
                )
            add(
                "3-52",
                @constraint(
                    model,
                    h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]*cp/dt*(avg-previous) +
                    cp*product +
                    loss == 0
                )
            )
        end
        E0, Emax = r2_energy_limits(d)
        state = var("E_DHN", @variable(model, [0:T], lower_bound = 0, upper_bound = Emax))
        fix(state[0], E0; force = true)
        for t in 1:T
            losses = sum(
                pipe["epsilon_W_mK"] *
                pipe["length_m"] *
                (h["S_reference_K"]+h["R_reference_K"]-2d["ambient_K"][t])/1e6 for
                pipe in h["pipes"]
            )
            if spec.loss == :dynamic
                losses = sum(
                    h["pipes"][p]["epsilon_W_mK"] *
                    h["pipes"][p]["length_m"] *
                    (
                        (vars["tau_"*side*"_in"][p, t]+vars["tau_"*side*"_out"][p, t])/2-d["ambient_K"][t]
                    )/1e6 for p in 1:E, side in ("S", "R")
                )
            end
            net = sum((h["nodes"][j]["role"] == "source" ? 1 : -1)*Hport[j, t] for j in 1:K)
            add("3-44", @constraint(model, state[t] == state[t-1] + d["dt_h"]*(net-losses)))
        end
    end
    @objective(
        model,
        Min,
        d["dt_h"]*(
            sum(d["grid_price"][t]*grid[t] for t in 1:T) +
            sum(d["devices"][g]["cost_per_MWh"]*PG[g, t] for g in 1:G, t in 1:T)
        )
    )
    return (;
        status = "built",
        model,
        variables = vars,
        constraints = cs,
        class = r2_model_class(model),
        case = c,
        spec,
        fixed_flows,
    )
end
# endregion r2-model

function r2_fixed_port_flows(d, schedule = nothing)
    h = d["heat"]
    out = zeros(length(h["nodes"]), d["T"])
    for j in eachindex(h["nodes"]), t in 1:d["T"]
        balance =
            sum(
                isnothing(schedule) ? p["fixed_flow"][t] : schedule[i, t] for
                (i, p) in enumerate(h["pipes"]) if p["from"] == j;
                init = 0.0,
            ) - sum(
                isnothing(schedule) ? p["fixed_flow"][t] : schedule[i, t] for
                (i, p) in enumerate(h["pipes"]) if p["to"] == j;
                init = 0.0,
            )
        out[j, t] = h["nodes"][j]["role"] == "load" ? -balance : balance
    end
    return out
end

function r2_energy_limits(d)
    h = d["heat"]
    E0 = 0.0
    Emax = 0.0
    for p in h["pipes"], side in ("S", "R")
        coefficient = h["rho_kg_m3"]*p["area_m2"]*p["length_m"]*h["cp_J_kgK"]/3.6e9
        E0 += coefficient*(r2_initial_average(d, p, side)-h[side*"_bounds_K"][1])
        Emax += coefficient*(h[side*"_bounds_K"][2]-h[side*"_bounds_K"][1])
    end
    return E0, Emax
end

function r2_initial_average(d, p, side)
    h = d["heat"]
    fs = reverse(p["flow_history"])
    weights = water_mass_weights(fs, h["rho_kg_m3"]*p["area_m2"]*p["length_m"], 3600d["dt_h"])
    star = sum(weights.w .* reverse(p[side*"_history_K"]))
    residence = 3600d["dt_h"]*(sum(weights.α)+sum(weights.β[2:end]))/2
    ambient = first(d["ambient_K"])
    outlet =
        ambient+(star-ambient)*exp(
            -p["epsilon_W_mK"]*residence/(h["rho_kg_m3"]*h["cp_J_kgK"]*p["area_m2"]),
        )
    return (p[side*"_history_K"][end]+outlet)/2
end
