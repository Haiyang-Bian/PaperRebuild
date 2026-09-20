"""
    build_r7_flow_planning(case, spec; optimizer=nothing, deadline=Inf)

R7-J2全量故障参考：正常与各恢复分支共同选择流量，全部分支继承同一正常空间热状态。
正常流量严格正向，恢复非负且可停流；时段/子步平均节点混合。恢复初态不能自由重设。
旧规格使用零UA精确质量交集与二次乘积；显式有损规格使用带截断界的指数积分，通常成为MINLP。
全部流量固定时退化为LP/MILP。实际类型按MOI约束报告，采用积分模型的界不冒充精确热方程的界。
仅构建，不求解或写文件；不套用旧聚合热模型的LP对偶或作者嵌套算法保证。
"""
function build_r7_flow_planning(c::R7PlanningCase, s; optimizer = nothing, deadline = Inf)
    r7_flow_planning_check(c, s)
    time()<deadline || error("flow_planning_build_deadline")
    normal=build_r7_normal_flow(
        c.normal,
        s["normal_flow"];
        optimizer,
        deadline,
        energy_balance = true,
    )
    m, nv, nf=normal.model, normal.variables, normal.flow
    nc=Dict(id=>b.variables for (id, b) in normal.chp)
    normal_objective=objective_function(m)
    d=c.normal.data
    h=d["heat"]
    W=length(d["probabilities"])
    recovery=Any[]
    for (index, pair) in enumerate(r7_planning_pairs(c))
        time()<deadline || error("flow_planning_build_deadline")
        e=c.specification["events"][pair.event]
        at, T=e["event_start"], e["periods"]
        template=r7_event_template(c, pair.event)
        b=build_r7_recovery(template, pair.fault; boundary_variables = true)
        # 只删除已被详细逐管模型替代的双水箱/Taylor块；共用设备与电网约束保留。
        for id in R7_TRANSPORT_PROXY_ROWS
            foreach(ref->delete(b.model, ref), b.constraints[id])
            delete!(b.constraints, id)
        end
        for key in R7_TRANSPORT_PROXY_VARIABLES
            foreach(v->delete(b.model, v), b.variables[key])
            delete!(b.variables, key)
            unregister(b.model, Symbol(key))
        end
        rm=r7_append_linear_block!(m, b.model, "joint_$(index)")
        rv=Dict(k=>map(v->rm.variables[v], a) for (k, a) in b.variables)
        rp=Dict(k=>map(v->rm.variables[v], a) for (k, a) in b.boundary_parameters)
        bounds=r7_joint_bounds(s, pair)
        flow=Dict{String,Any}()
        for kind in ("pipe", "source", "load")
            lo, hi=bounds[kind*"_min"], bounds[kind*"_max"]
            raw=rv["m_"*kind]
            for I in CartesianIndices(raw)
                set_lower_bound(raw[I], lo[I])
                set_upper_bound(raw[I], hi[I])
            end
            # 固定系数用输入数值代入，保留原始流量变量供独立等式核验。
            flow[kind]=[lo[I]==hi[I] ? lo[I] : raw[I] for I in CartesianIndices(raw)]
        end
        tv=r7_add_joint_thermal!(m, d, template.data, s, nv, nf, rv, flow, at, index; deadline)
        for (g, dev) in enumerate(d["devices"])
            if dev["kind"]=="CHP"
                u=nc[dev["id"]]["u_CHP"]
                for t in 1:T
                    @constraint(m, rp["u"][g, t]==u[at+t-1])
                end
                @constraint(m, rp["u_before"][g]==(at==1 ? dev["previous_commitment"] : u[at-1]))
                for w in 1:W
                    @constraint(
                        m,
                        rp["P_before"][g, w]==(
                            at==1 ? dev["previous_P_MW"][w] : nv["P"][g, at-1, w]
                        )
                    )
                end
            elseif dev["kind"]=="BES"
                for w in 1:W
                    @constraint(m, rp["E_before"][g, w]==nv["E_BES"][g, at, w])
                end
            end
        end
        for side in ("S", "R"), w in 1:W
            @constraint(m, rp["E_$(side)_before"][w]==sum(nv["E_pipe_$side"][:, at, w]))
        end
        # (6-72)相对于本轮共同正常决策；不能继续用输入的旧参考流量。
        for a in eachindex(h["pipes"]), t in 1:T
            @constraint(m, rp["m_normal"][a, t]==nf["pipe"][a, at+t-1])
        end
        @constraint(m, rm.objective<=e["loss_limit_MWh"])
        push!(
            recovery,
            (;
                pair,
                variables = rv,
                thermal_variables = tv,
                boundary_parameters = rp,
                loss = rm.objective,
            ),
        )
    end
    time()<deadline || error("flow_planning_build_deadline")
    @objective(m, Min, normal_objective)
    types=list_of_constraint_types(m)
    all(
        F in (VariableRef, AffExpr, QuadExpr, NonlinearExpr) && S in
        (MOI.LessThan{Float64}, MOI.GreaterThan{Float64}, MOI.EqualTo{Float64}, MOI.ZeroOne) for
        (F, S) in types
    ) || error("联合流量出现未声明约束类型")
    nonlinear=any(F==QuadExpr for (F, _) in types)
    (;
        model = m,
        normal_variables = nv,
        chp_variables = nc,
        normal_flow = nf,
        recovery,
        model_class = any(F==NonlinearExpr for (F, _) in types) ? "nonconvex_MINLP" :
                      nonlinear ? "nonconvex_MIQCP" :
                      any(is_binary, all_variables(m)) ? "MILP" : "LP",
        model_types = [string(F)*" in "*string(S) for (F, S) in types],
    )
end

# R7-J3：重放灾前累计质量前缀和灾后后缀，所有事件复用同一原始空间初态。
function r7_add_joint_thermal!(m, d, event, s, nv, nf, rv, flow, at, index; deadline)
    h, ps=d["heat"], d["heat"]["pipes"]
    J, A, W=h["nodes"], length(ps), length(d["probabilities"])
    n=s["substeps"]
    K=event["periods"]*n
    dt=d["dt_h"]/n
    tv=Dict{String,Any}()
    for (key, side) in (("S", "S"), ("R", "R"), ("T_source", "S"), ("T_load", "R"))
        tv[key]=[
            @variable(
                m,
                lower_bound=h["$(side)_min_K"],
                upper_bound=h["$(side)_max_K"],
                base_name="joint_$(index)_$key[$j,$k,$w]"
            ) for j in 1:J, k in 1:K, w in 1:W
        ]
    end
    tv["H_delivered"]=[
        @variable(
            m,
            lower_bound=0,
            upper_bound=event["heat"]["load_MW"][j][cld(k, n)],
            base_name="joint_$(index)_H_delivered[$j,$k,$w]"
        ) for j in 1:J, k in 1:K, w in 1:W
    ]
    for side in ("S", "R")
        tv["out_$side"]=[
            @variable(
                m,
                lower_bound=h["$(side)_min_K"],
                upper_bound=h["$(side)_max_K"],
                base_name="joint_$(index)_out_$side[$a,$k,$w]"
            ) for a in 1:A, k in 1:K, w in 1:W
        ]
        tv["E_$side"]=[
            @variable(
                m,
                lower_bound=0,
                upper_bound=h["rho_kg_m3"]*ps[a]["volume_$(side)_m3"]*h["c_J_kgK"]/3.6e9*(
                    h["$(side)_max_K"]-h["$(side)_min_K"]
                ),
                base_name="joint_$(index)_E_$side[$a,$k,$w]"
            ) for a in 1:A, k in 1:(K+1), w in 1:W
        ]
    end
    cw=h["c_J_kgK"]/1e6
    generated=[
        sum(
            rv["H"][g, t, w] for
            (g, z) in enumerate(d["devices"]) if z["kind"] in ("CHP", "EB")&&z["heat_node"]==j;
            init = 0.0,
        ) for j in 1:J, t in 1:event["periods"], w in 1:W
    ]
    for k in 1:K, j in 1:J
        t=cld(k, n)
        fi=sum(flow["pipe"][a, t] for (a, p) in enumerate(ps) if p["to"]==j; init = 0.0)
        fo=sum(flow["pipe"][a, t] for (a, p) in enumerate(ps) if p["from"]==j; init = 0.0)
        ms, ml=flow["source"][j, t], flow["load"][j, t]
        for w in 1:W
            @constraint(m, generated[j, t, w]==cw*ms*(tv["T_source"][j, k, w]-tv["R"][j, k, w]))
            @constraint(
                m,
                tv["H_delivered"][j, k, w]==cw*ml*(tv["S"][j, k, w]-tv["T_load"][j, k, w])
            )
            @constraint(
                m,
                tv["H_delivered"][j, k, w]==event["heat"]["load_MW"][j][t]-rv["H_shed"][j, t, w]
            )
            for (side, port, porttemp, incoming, total) in (
                ("S", ms, "T_source", [a for (a, p) in enumerate(ps) if p["to"]==j], fi+ms),
                ("R", ml, "T_load", [a for (a, p) in enumerate(ps) if p["from"]==j], fo+ml),
            )
                ref=h["$(side)_min_K"]
                rhs=sum(
                    flow["pipe"][a, t]*(tv["out_$side"][a, k, w]-ref) for a in incoming;
                    init = 0.0,
                ) + port*(tv[porttemp][j, k, w]-ref)
                # 总流量为0时温度是无流热端口的占位量；热功率与库存仍必须满足上列关系。
                @constraint(m, total*(tv[side][j, k, w]-ref)==rhs)
            end
        end
    end
    H=at-1
    lossy=r7_is_lossy_flow(s["normal_flow"])
    losses=Matrix{Any}(undef, K, W)
    fill!(losses, 0.0)
    for (a, p) in enumerate(ps), side in ("S", "R"), w in 1:W
        time()<deadline || error("flow_planning_build_deadline")
        M=h["rho_kg_m3"]*p["volume_$(side)_m3"]
        lo, span=h["$(side)_min_K"], h["$(side)_max_K"]-h["$(side)_min_K"]
        cap=h["c_J_kgK"]*M/3.6e9*span
        node=p[side=="S" ? "from" : "to"]
        q=vcat(
            [nf["pipe"][a, t]*(3600d["dt_h"]/M) for t in 1:H],
            [flow["pipe"][a, cld(k, n)]*(3600dt/M) for k in 1:K],
        )
        inlet=vcat(
            [(nv["τ_$side"][node, t, w]-lo)/span for t in 1:H],
            [(tv[side][node, k, w]-lo)/span for k in 1:K],
        )
        outlet=vcat(
            [(nv["τ_pipe_$side"][a, t, w]-lo)/span for t in 1:H],
            [(tv["out_$side"][a, k, w]-lo)/span for k in 1:K],
        )
        inventory=vcat(
            [nv["E_pipe_$side"][a, t, w]/cap for t in 1:(H+1)],
            [tv["E_$side"][a, k, w]/cap for k in 2:(K+1)],
        )
        @constraint(m, tv["E_$side"][a, 1, w]==nv["E_pipe_$side"][a, at, w])
        profile=p["initial_$(side)_profiles"][w]
        if lossy
            bounded=[
                @variable(
                    m,
                    lower_bound=0,
                    upper_bound=1,
                    base_name="joint_in_$(index)_$a$side$(w)_$t"
                ) for t in eachindex(inlet)
            ]
            for t in eachindex(inlet)
                @constraint(m, bounded[t]==inlet[t])
            end
            ambient=vcat(h["ambient_K"][1:H], [event["heat"]["ambient_K"][cld(k, n)] for k in 1:K])
            kernel=add_r7_lossy_mass_transport!(
                m,
                q,
                bounded,
                outlet,
                inventory,
                profile["mass_kg"] ./ M,
                (profile["temperature_K"] .- lo) ./ span;
                dt_h = vcat(fill(d["dt_h"], H), fill(dt, K)),
                decay_per_h = 3600p["UA_$(side)_W_K"]/(M*h["c_J_kgK"]),
                ambient = (ambient .- lo) ./ span,
                order = s["normal_flow"]["quadrature_order"],
                max_truncation_error = s["normal_flow"]["max_truncation_error"],
                prefix = "joint_$(index)_$a$side$w",
                deadline,
            )
            for k in 1:K
                losses[k, w]+=cap*kernel.loss[H+k]
            end
        else
            add_r7_mass_transport!(
                m,
                q,
                inlet,
                outlet,
                inventory,
                profile["mass_kg"] ./ M,
                (profile["temperature_K"] .- lo) ./ span;
                prefix = "joint_$(index)_$a$side$w",
                deadline,
                allow_zero = true,
            )
        end
    end
    # R7-F6在每个恢复子步的等价守恒；失供由设备与负荷决定，不能靠改变总库存凭空补足。
    for k in 1:K, w in 1:W
        @constraint(
            m,
            dt*(sum(generated[:, cld(k, n), w])-sum(tv["H_delivered"][:, k, w])) - losses[k, w] ==
            sum(tv["E_S"][:, k+1, w]-tv["E_S"][:, k, w])+sum(
                tv["E_R"][:, k+1, w]-tv["E_R"][:, k, w],
            )
        )
    end
    tv
end
