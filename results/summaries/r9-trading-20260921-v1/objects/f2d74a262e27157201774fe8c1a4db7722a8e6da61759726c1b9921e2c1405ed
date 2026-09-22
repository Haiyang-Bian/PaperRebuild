# 约束在固定调度状态下对流量的偏导；历史保持常数。与对偶乘子无关。
function r3_thermal_partials(c, b, values, m)
    d, h, cs = c.data, c.data["heat"], b.constraints
    E, T = size(m)
    V(key, i, t) = values[key][i][t]
    portJ = zeros(length(h["nodes"]), E)
    for (j, n) in enumerate(h["nodes"]), (p, e) in enumerate(h["pipes"])
        s = n["role"]=="source" ? 1 : n["role"]=="load" ? -1 : 0
        portJ[j, p] = s*(Int(e["from"]==j)-Int(e["to"]==j))
    end
    rows = NamedTuple[]
    add(id, index, D) = push!(rows, (; id, index, constraint = cs[id][index], derivative = D))
    active=findall(n->n["role"]!="transit", h["nodes"])
    for (k, j) in enumerate(active), t in 1:T
        D=zeros(E, T)
        D[:, t] .= -portJ[j, :]*(V("tau_S_port", j, t)-V("tau_R_port", j, t))
        add("3-17", 2((k-1)*T+t)-1, D)
    end
    function slack(id, entity, t)
        i=findfirst(r->r.equation==id && r.entity==entity && r.t==t, b.elastic_rows)
        isnothing(i) && return 0.0
        return b.elastic_rows[i].scale*(values["elastic_positive"][i]-values["elastic_negative"][i])
    end
    for side in ("S", "R"), j in eachindex(h["nodes"]), t in 1:T
        edges, local_in=r2_inflows(d, side, j)
        length(edges)+Int(local_in)>1 || continue
        id=side=="S" ? "3-35" : "3-36"
        D=zeros(E, T)
        mix=V("tau_"*side*"_mix", j, t)
        s=slack(id, side*string(j), t)
        for p in edges
            D[p, t]+=mix-V("tau_"*side*"_out", p, t)-s
        end
        local_in && (D[:, t] .+= portJ[j, :]*(mix-V("tau_"*side*"_port", j, t)-s))
        add(id, (j-1)*T+t, D)
    end
    switches=String[]
    for (p, e) in enumerate(h["pipes"]), t in 1:T
        dt=3600d["dt_h"]
        mass=h["rho_kg_m3"]*e["area_m2"]*e["length_m"]
        Td=ceil(Int, mass/(dt*e["flow_min"]))+1
        fs=[t-s>0 ? m[p, t-s] : e["flow_history"][end+t-s] for s in 0:Td]
        J=r3_transport_jacobian(
            fs,
            mass,
            dt;
            loss_rate = e["epsilon_W_mK"]/(h["cp_J_kgK"]*h["rho_kg_m3"]*e["area_m2"]),
        )
        any(start<=t for start in J.switch_starts) && push!(switches, "$p:$t")
        for (k, side) in enumerate(("S", "R"))
            temps=[
                t-s>0 ? V("tau_"*side*"_in", p, t-s) : e[side*"_history_K"][end+t-s] for s in 0:Td
            ]
            star=V("tau_"*side*"_star", p, t)
            D, L=zeros(E, T), zeros(E, T)
            for lag in 0:min(Td, t-1)
                D[p, t-lag]=-sum(J.Jq[:, lag+1] .* temps)
                lag==0 && (D[p, t]+=star-slack("3-33", side*string(p), t))
                L[p, t-lag]=-(star-d["ambient_K"][t])*J.Jdecay[lag+1]
            end
            index=2((p-1)*T+t-1)+k
            add("3-33", index, D)
            add("3-34", index, L)
        end
    end
    return (; rows, switches)
end

"""
    build_r3_local_step(case, center; mode=:dispatch, radius=0.1, operation=nothing, optimizer=nothing)

项目局部凸方向问题（R3-L01）。center为已求解的固定流量阶段记录，包含数值而非对偶。
热功率、混合、WMM输运和损耗在当前状态作一阶展开，同时调整流量与调度变量。
保留设备、电网及水力锥；流量和温度用输入跨度归一化，信赖域限制无穷范数。
目标为归一化费用或热松弛，加二次步长惩罚的锥上图。此方向不是最优值梯度，
预测下降必须由真实子问题复核；不求解、不写文件，不调用直接修正。
"""
function build_r3_local_step(
    c::R2Case,
    center;
    mode = :dispatch,
    radius = 0.1,
    operation = nothing,
    optimizer = nothing,
)
    1e-6<=radius<=0.2 || throw(ArgumentError("局部信赖域半径超出范围"))
    haskey(center, "values") || throw(ArgumentError("局部展开需要原始变量候选"))
    m=r2_flow_matrix(c, center["values"]["m_pipe"])
    b=build_r3_subproblem(c, m; mode, operation, optimizer)
    partials=r3_thermal_partials(c, b, center["values"], m)
    model=b.model
    for row in partials.rows
        cr, D=row.constraint, row.derivative
        # f(x,m0)+f_m(x0,m0)(m-m0)=0，常数移到右侧。
        for i in eachindex(m)
            D[i]==0 && continue
            variable=b.variables["m_pipe"][i]
            set_normalized_coefficient(cr, variable, normalized_coefficient(cr, variable)+D[i])
        end
        set_normalized_rhs(cr, normalized_rhs(cr)+sum(D .* m))
    end
    lo, hi, width=r3_flow_box(c, operation)
    steps=AffExpr[]
    for i in eachindex(m)
        variable=b.variables["m_pipe"][i]
        unfix(variable)
        set_lower_bound(variable, lo[i])
        set_upper_bound(variable, hi[i])
        width[i]==0 && continue
        push!(steps, (variable-m[i])/width[i])
    end
    for (key, variables) in b.variables
        startswith(key, "tau_") || continue
        side=split(key, "_")[2]
        span=diff(c.data["heat"][side*"_bounds_K"])[1]
        span>0 || continue
        old=r3_matrix(center["values"][key])
        for i in eachindex(variables)
            is_fixed(variables[i]) && continue
            push!(steps, (variables[i]-old[i])/span)
        end
    end
    for z in steps
        @constraint(model, z<=radius)
        @constraint(model, z>=-radius)
    end
    penalty=@variable(model, lower_bound=0)
    @constraint(model, [penalty+1; 2 .* steps; penalty-1] in SecondOrderCone())
    merit=objective_function(model)/(mode==:dispatch ? r3_cost_scale(c) : 1)
    @objective(model, Min, merit+0.01penalty)
    r2_model_class(model)=="SOCP" || error("局部方向问题未成为连续SOCP")
    return merge(
        b,
        (;
            class = "SOCP",
            merit_expression = merit,
            steps,
            radius,
            partials,
            variant = "r3_primal_local_v1",
            objective_kind = "local_model_merit",
        ),
    )
end
