"""
    build_r7_normal_flow(case, spec; optimizer=nothing, deadline=Inf)

构建连续正向流量正常调度。复用旧设备、电网、启停、电池与终端约束，显式替换固定流量的
热功率、混合、输运和压降等式；保留非凸二次乘积。全固定流量特例退化到原LP/MILP。
流量仅有管道/节点×时段维度，不能按可再生场景分别择流。构建不求解、不写文件。
"""
function build_r7_normal_flow(c::R7NormalCase, s; optimizer = nothing, deadline = Inf)
    bd=r7_normal_flow_check(c, s)
    time()<deadline || error("normal_flow_build_deadline")
    fixed=all(bd[k*"_min"]==bd[k*"_max"] for k in ("pipe", "source", "load"))
    if fixed
        f=Dict(k=>bd[k*"_min"] for k in ("pipe", "source", "load"))
        nc=r7_normal_at_flow(c, f)
        b=build_r7_normal(nc; optimizer)
        return (; b..., flow = f, transport = Dict{String,Any}(), fixed_flow = true)
    end
    b=build_r7_normal(c; optimizer)
    m=b.model
    v=b.variables
    d=c.data
    h=d["heat"]
    ps=h["pipes"]
    T, W, J=d["periods"], length(d["probabilities"]), h["nodes"]
    for id in (
        "6-26",
        "6-28",
        "R7-D-mix-S",
        "R7-D-mix-R",
        "R7-D-transport",
        "R7-D-inventory",
        "R7-D-pressure-S",
        "R7-D-pressure-R",
    )
        for con in b.constraints[id]
            delete(m, con)
        end
        b.constraints[id]=Any[]
    end
    add(id, con) = (push!(get!(b.constraints, id, Any[]), con); con)
    f=Dict{String,Any}()
    for k in ("pipe", "source", "load")
        lo, hi=bd[k*"_min"], bd[k*"_max"]
        f[k]=[
            @variable(m, lower_bound=lo[i, t], upper_bound=hi[i, t], base_name="m_$(k)[$i,$t]") for
            i in axes(lo, 1), t in 1:T
        ]
    end
    cp=h["c_J_kgK"]/1e6
    for j in 1:J, t in 1:T
        fi=sum(f["pipe"][a, t] for (a, p) in enumerate(ps) if p["to"]==j; init = 0.0)
        fo=sum(f["pipe"][a, t] for (a, p) in enumerate(ps) if p["from"]==j; init = 0.0)
        ms, md=f["source"][j, t], f["load"][j, t]
        add("6-30", @constraint(m, fi+ms==fo+md))
        for w in 1:W
            generated=sum(
                v["H"][g, t, w] for
                (g, z) in enumerate(d["devices"]) if z["kind"] in ("CHP", "EB")&&z["heat_node"]==j;
                init = 0.0,
            )
            add("6-26", @constraint(m, generated==cp*ms*(v["τ_source"][j, t, w]-v["τ_R"][j, t, w])))
            add(
                "6-28",
                @constraint(m, h["load_MW"][j][t]==cp*md*(v["τ_S"][j, t, w]-v["τ_load"][j, t, w]))
            )
            # 减去同侧温区下限以降低乘积尺度；质量守恒保证是等价改写。
            for (side, port, porttemp, incoming, total) in (
                ("S", ms, "τ_source", [(a, p) for (a, p) in enumerate(ps) if p["to"]==j], fi+ms),
                ("R", md, "τ_load", [(a, p) for (a, p) in enumerate(ps) if p["from"]==j], fo+md),
            )
                ref=h["$(side)_min_K"]
                rhs=sum(
                    f["pipe"][a, t]*(v["τ_pipe_$side"][a, t, w]-ref) for (a, p) in incoming;
                    init = 0.0,
                )+port*(v[porttemp][j, t, w]-ref)
                add("R7-D-mix-$side", @constraint(m, total*(v["τ_$side"][j, t, w]-ref)==rhs))
            end
        end
    end
    transport=Dict{String,Any}()
    for (a, p) in enumerate(ps), side in ("S", "R")
        time()<deadline || error("normal_flow_build_deadline")
        M=h["rho_kg_m3"]*p["volume_$(side)_m3"]
        cap=h["c_J_kgK"]*M/3.6e9*(h["$(side)_max_K"]-h["$(side)_min_K"])
        q=[f["pipe"][a, t]*(3600d["dt_h"]/M) for t in 1:T]
        node=p[side=="S" ? "from" : "to"]
        lo, hi=h["$(side)_min_K"], h["$(side)_max_K"]
        for w in 1:W
            θin=[
                @variable(m, lower_bound=0, upper_bound=1, base_name="theta_in[$a,$side,$w,$t]") for
                t in 1:T
            ]
            θout=[
                @variable(m, lower_bound=0, upper_bound=1, base_name="theta_out[$a,$side,$w,$t]")
                for t in 1:T
            ]
            inv=[
                @variable(m, lower_bound=0, upper_bound=1, base_name="inventory[$a,$side,$w,$t]")
                for t in 1:(T+1)
            ]
            for t in 1:T
                @constraint(m, v["τ_$side"][node, t, w]==lo+(hi-lo)*θin[t])
                @constraint(m, v["τ_pipe_$side"][a, t, w]==lo+(hi-lo)*θout[t])
            end
            for t in 1:(T+1)
                @constraint(m, v["E_pipe_$side"][a, t, w]==cap*inv[t])
            end
            profile=p["initial_$(side)_profiles"][w]
            transport["$a:$side:$w"]=add_r7_mass_transport!(
                m,
                q,
                θin,
                θout,
                inv,
                profile["mass_kg"] ./ M,
                (profile["temperature_K"] .- lo) ./ (hi-lo);
                prefix = "pipe_$a$side$w",
                deadline,
            )
        end
        i, j=side=="S" ? (p["from"], p["to"]) : (p["to"], p["from"])
        for t in 1:T
            add(
                "R7-D-pressure-$side",
                @constraint(
                    m,
                    (v["Φ_$side"][i, t]-v["Φ_$side"][j, t]-v["Φ_val_$side"][a, t])/h["pressure_max_Pa"] ==
                    p["mu_$(side)_Pa_s2_kg2"]*f["pipe"][a, t]^2/h["pressure_max_Pa"]
                )
            )
        end
    end
    time()<deadline || error("normal_flow_build_deadline")
    types=list_of_constraint_types(m)
    all(
        F in (VariableRef, AffExpr, QuadExpr) && S in
        (MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.EqualTo{Float64}, MOI.ZeroOne) for
        (F, S) in types
    ) || error("连续流量出现未声明模型类型")
    (;
        model = m,
        variables = v,
        chp = b.chp,
        constraints = b.constraints,
        flow = f,
        transport,
        fixed_flow = false,
        model_class = "nonconvex_MIQCP",
        model_types = [string(F)*" in "*string(S) for (F, S) in types],
    )
end
