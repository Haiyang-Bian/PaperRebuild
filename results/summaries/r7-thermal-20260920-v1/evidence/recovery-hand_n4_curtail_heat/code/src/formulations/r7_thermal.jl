"""
    build_r7_thermal_reconstruction(case, recovery, spec; optimizer=nothing)

构造R7-T1至T4固定控制的逐管温度重构LP，不求解、不写文件。
输运使用既有连续塞流参考，节点/端口按子步平均守恒，供回水均检查完整空间段端点边界。
same_dispatch保留原热交付；curtail_heat只增加热失供。没有水力或连续节点混合的等价性保证。
"""
function build_r7_thermal_reconstruction(
    c::R7RecoveryCase,
    r,
    spec;
    optimizer = nothing,
    deadline = Inf,
)
    x=r7_thermal_inputs(c, r, spec)
    h=x.h
    J, K, W, A=x.J, x.K, x.W, x.A
    model=optimizer===nothing ? Model() : Model(optimizer)
    rows=Dict{String,Vector{ConstraintRef}}()
    add(id, c) = push!(get!(rows, id, ConstraintRef[]), c)
    function bounds(id, y, lo, hi)
        add(id, @constraint(model, y>=lo))
        add(id, @constraint(model, y<=hi))
    end
    @variable(model, S[1:J, 1:K, 1:W])
    @variable(model, R[1:J, 1:K, 1:W])
    @variable(model, T_source[1:J, 1:K, 1:W])
    @variable(model, T_load[1:J, 1:K, 1:W])
    @variable(model, H_delivered[1:J, 1:K, 1:W])
    @variable(model, out_S[1:A, 1:K, 1:W])
    @variable(model, out_R[1:A, 1:K, 1:W])
    @variable(model, E_S[1:A, 1:(K+1), 1:W])
    @variable(model, E_R[1:A, 1:(K+1), 1:W])
    cw=h["c_J_kgK"]/1e6
    for j in 1:J, k in 1:K, w in 1:W
        t=cld(k, x.n)
        ms=x.v["m_source"][j, t]
        ml=x.v["m_load"][j, t]
        for (y, side) in ((S, "S"), (R, "R"), (T_source, "S"), (T_load, "R"))
            bounds("R7-T-bound", y[j, k, w], h["$(side)_min_K"], h["$(side)_max_K"])
        end
        add(
            "R7-T2-source",
            @constraint(model, cw*ms*(T_source[j, k, w]-R[j, k, w])==x.generated[j, t, w])
        )
        add(
            "R7-T2-load",
            @constraint(model, cw*ml*(S[j, k, w]-T_load[j, k, w])==H_delivered[j, k, w])
        )
        lo=spec["mode"]=="same_dispatch" ? x.served[j, t, w] :
           h["load_MW"][j][t]*(1-h["shed_fraction_max"][j])
        bounds("R7-T-control", H_delivered[j, k, w], lo, x.served[j, t, w])
        ms>0 ?
        bounds(
            "R7-T-port",
            T_source[j, k, w]-R[j, k, w],
            h["source_delta_min"][j],
            h["source_delta_max"][j],
        ) : add("R7-T-idle", @constraint(model, T_source[j, k, w]==S[j, k, w]))
        ml>0 ?
        bounds(
            "R7-T-port",
            S[j, k, w]-T_load[j, k, w],
            h["load_delta_min"][j],
            h["load_delta_max"][j],
        ) : add("R7-T-idle", @constraint(model, T_load[j, k, w]==R[j, k, w]))
        for (side, node, port, rate, out) in
            (("S", S, T_source, ms, out_S), ("R", R, T_load, ml, out_R))
            incoming=AffExpr(0.0)
            mass=rate
            for (a, p) in enumerate(h["pipes"])
                f=x.v["m_pipe"][a, t]
                _, v=r7_thermal_ends(p, side, f)
                if v==j && f!=0
                    mass+=abs(f)
                    add_to_expression!(incoming, abs(f), out[a, k, w])
                end
            end
            if mass>0
                add(
                    "R7-T3-mix",
                    @constraint(model, node[j, k, w]==(incoming+rate*port[j, k, w])/mass)
                )
            else
                add("R7-T-idle", @constraint(model, node[j, k, w]==h["$(side)_reference_K"]))
            end
        end
    end
    for a in 1:A, side in ("S", "R"), w in 1:W
        time()<deadline || error("thermal_build_deadline")
        p=h["pipes"][a]
        map=r7_thermal_pipe_map(x, a, side, w; deadline)
        node=side=="S" ? S : R
        out=side=="S" ? out_S : out_R
        energy=side=="S" ? E_S : E_R
        inlet=[node[r7_thermal_ends(p, side, x.v["m_pipe"][a, cld(k, x.n)])[1], k, w] for k in 1:K]
        for i in eachindex(map.b)
            expr=map.b[i]+sum(map.A[i, k]*inlet[k] for k in 1:K)
            if i<=K
                add("R7-T1-transport", @constraint(model, out[a, i, w]==expr))
                x.v["m_pipe"][a, cld(i, x.n)]!=0 &&
                    bounds("R7-T-bound", out[a, i, w], h["$(side)_min_K"], h["$(side)_max_K"])
            elseif i<=2K+1
                add("R7-T4-inventory", @constraint(model, energy[a, i-K, w]==expr))
            else
                # 段内指数单调，逐段两端同时合格才能认证子步边界整管温度范围。
                bounds("R7-T4-spatial", expr, h["$(side)_min_K"], h["$(side)_max_K"])
            end
        end
    end
    @objective(
        model,
        Min,
        x.dt*sum(
            x.d["probabilities"][w]*(h["load_MW"][j][cld(k, x.n)]-H_delivered[j, k, w]) for
            j in 1:J, k in 1:K, w in 1:W
        )
    )
    variables=Dict(
        string(k)=>v for
        (k, v) in pairs((; S, R, T_source, T_load, H_delivered, out_S, out_R, E_S, E_R))
    )
    types=list_of_constraint_types(model)
    all(
        F in (AffExpr, VariableRef) &&
            SetType in (MOI.EqualTo{Float64}, MOI.LessThan{Float64}, MOI.GreaterThan{Float64}) for
        (F, SetType) in types
    ) || error("热重构不是所声明LP")
    (; model, variables, constraints = rows, model_class = "LP")
end
