const R7_RECOVERY_MODEL_FILE = @__FILE__

function r7_topology_roots(c, gamma, z)
    e = c.data["electric"]
    ls = e["lines"]
    length(z)==length(ls) && all(x->x in (0, 1), z) || error("固定拓扑不是二值向量")
    all(i->z[i]<=1-gamma[i], eachindex(z)) || return nothing
    sum((abs(z[i]-ls[i]["base_closed"]) for i in eachindex(z) if gamma[i]==0); init = 0) <=
    e["switch_budget"] || return nothing
    r7_forest_roots(c, z)
end

# 只检查森林与根资格；符号故障模板的动作限制留在LP行中，不能用零故障预先排除拓扑。
function r7_forest_roots(c, z)
    e=c.data["electric"]
    ls=e["lines"]
    length(z)==length(ls) && all(x->x in (0, 1), z) || error("固定拓扑不是二值向量")
    ends = [(l["from"], l["to"]) for l in ls]
    groups = r7_connected_components(e["nodes"], ends, z)
    sum(z)==e["nodes"]-length(groups) || return nothing
    roots = zeros(Int, e["nodes"])
    for group in groups
        candidates = filter(n->e["root_eligible"][n]==1, group)
        isempty(candidates) && return nothing
        roots[first(candidates)] = 1
    end
    roots
end

"""
    build_r7_recovery(case, fault; optimizer=nothing, fixed_z=nothing,
                      boundary_variables=false, fault_variables=false)

构建给定灾前状态/故障的最小加权失供MILP；固定有效森林后为LP。拓扑跨时段与场景共用，
管流跨新能源场景共用，连续调度按场景变化。不求解、不写文件。采用(6-51)至(6-90)
及其继承的设备/线性电网约束；双水箱通过不代表详细热网或交流潮流通过。
固定拓扑仅用于穷举/对照，根取每个分量的最早合格节点；根不改变物理出力能力。
boundary_variables=true仅供灾前主问题嵌入：将继承量暴露为变量，必须另行绑定同一正常轨迹。
未绑定的参数化块不是给定状态恢复问题；默认false保持旧行为。
fault_variables=true仅供固定拓扑LP对偶抽取，故障作为独立参数列；要求fixed_z且不得同时参数化灾前边界。
"""
function build_r7_recovery(
    c::R7RecoveryCase,
    gamma;
    optimizer = nothing,
    fixed_z = nothing,
    boundary_variables = false,
    fault_variables = false,
)
    r7_recovery_assert(c)
    r7_check_fault(c, gamma)
    fault_variables && (fixed_z===nothing || boundary_variables) &&
        error("故障参数模板要求固定拓扑及数值灾前边界")
    d=c.data
    e, h=d["electric"], d["heat"]
    ls, ps, ds=e["lines"], h["pipes"], d["devices"]
    N, J, T, W, G, L, A=e["nodes"],
    h["nodes"],
    d["periods"],
    length(d["probabilities"]),
    length(ds),
    length(ls),
    length(ps)
    dt=d["dt_h"]
    m=optimizer===nothing ? Model() : Model(optimizer)
    cs=Dict{String,Vector{Any}}()
    add(id, con) = (push!(get!(cs, id, Any[]), con); con)
    fault_parameters=fault_variables ?
        [@variable(m, lower_bound=0, upper_bound=1, base_name="fault_$l") for l in 1:L] :
        VariableRef[]
    fault_coefficient=fault_variables ? fault_parameters : gamma
    # R7-M1：仅把灾前继承量参数化，设备、网络、故障与恢复控制边界保持原定义。
    parameters=Dict{String,Any}()
    if boundary_variables
        for (key, shape) in (
            ("u", (G, T)),
            ("u_before", (G,)),
            ("P_before", (G, W)),
            ("E_before", (G, W)),
            ("E_S_before", (W,)),
            ("E_R_before", (W,)),
            ("m_normal", (A, T)),
        )
            parameters[key]=reshape(
                [
                    @variable(m, base_name="boundary_"*key*"_"*string(I)) for
                    I in CartesianIndices(shape)
                ],
                shape,
            )
        end
        for g in 1:G
            if ds[g]["kind"]!="CHP"
                foreach(x->fix(x, 0; force = true), parameters["u"][g, :])
                fix(parameters["u_before"][g], 0; force = true)
                foreach(x->fix(x, 0; force = true), parameters["P_before"][g, :])
            end
            ds[g]["kind"]=="BES" ||
                foreach(x->fix(x, 0; force = true), parameters["E_before"][g, :])
        end
    end
    inherited(key, I, value) = boundary_variables ? parameters[key][I...] : value
    @variable(m, 0<=z[1:L]<=1)
    @variable(m, 0<=beta[1:N]<=1)
    @variable(m, 0<=a_on[1:L]<=1)
    @variable(m, 0<=a_off[1:L]<=1)
    if fixed_z===nothing
        foreach(set_binary, vcat(z, beta, a_on, a_off))
    else
        roots=fault_variables ? r7_forest_roots(c, fixed_z) : r7_topology_roots(c, gamma, fixed_z)
        roots===nothing && error("指定拓扑不满足故障/动作/森林规则")
        foreach(i->fix(z[i], fixed_z[i]; force = true), 1:L)
        foreach(i->fix(beta[i], roots[i]; force = true), 1:N)
    end
    @variable(m, virtual[1:L])
    @variable(m, root_supply[1:N]>=0)
    for l in 1:L
        base=ls[l]["base_closed"]
        # 自动故障断开不计主动动作；健康线路才可合闸/分闸，修复原6-62的字面冲突。
        add("R7-R1", @constraint(m, z[l]==base*(1-fault_coefficient[l])+a_on[l]-a_off[l]))
        add("R7-R1", @constraint(m, a_on[l]<=(1-base)*(1-fault_coefficient[l])))
        add("R7-R1", @constraint(m, a_off[l]<=base*(1-fault_coefficient[l])))
        add("R7-R2", @constraint(m, virtual[l]<=(N-1)*z[l]))
        add("R7-R2", @constraint(m, virtual[l]>=-(N-1)*z[l]))
    end
    add("6-63", @constraint(m, sum(a_on)+sum(a_off)<=e["switch_budget"]))
    add("R7-R2", @constraint(m, sum(z)==N-sum(beta)))
    for n in 1:N
        add("R7-R2", @constraint(m, beta[n]<=e["root_eligible"][n]))
        add("R7-R2", @constraint(m, root_supply[n]<=N*beta[n]))
        add(
            "R7-R2",
            @constraint(
                m,
                sum(virtual[l] for l in 1:L if ls[l]["from"]==n)-sum(
                    virtual[l] for l in 1:L if ls[l]["to"]==n
                )==root_supply[n]-1
            )
        )
    end
    @variable(m, P_line[1:L, 1:T, 1:W])
    @variable(m, Q_line[1:L, 1:T, 1:W])
    @variable(m, e["v_min_pu"]<=v[1:N, 1:T, 1:W]<=e["v_max_pu"])
    @variable(m, P_PCC[1:T, 1:W])
    @variable(m, Q_PCC[1:T, 1:W])
    foreach(x->fix(x, 0; force = true), vcat(vec(P_PCC), vec(Q_PCC)))
    for l in 1:L, t in 1:T, w in 1:W
        line=ls[l]
        sign=e["flow_domain"]=="signed" ? -1.0 : 0.0
        for (power, cap) in ((P_line, line["P_max_MW"]), (Q_line, line["Q_max_Mvar"]))
            add("6-24:25", @constraint(m, power[l, t, w]<=cap*z[l]))
            add("6-24:25", @constraint(m, power[l, t, w]>=sign*cap*z[l]))
        end
        dv=v[line["from"], t, w]-v[line["to"], t, w]-(
            line["r_pu"]*P_line[l, t, w]+line["x_pu"]*Q_line[l, t, w]
        )/(e["S_base_MVA"]*e["v_ref_pu"])
        # 断开支路不强迫两端电压相等；流为零时M由电压范围给出，不选任意大数。
        M=e["v_max_pu"]-e["v_min_pu"]
        add("R7-R3", @constraint(m, dv<=M*(1-z[l])))
        add("R7-R3", @constraint(m, -dv<=M*(1-z[l])))
    end
    # 各孤岛根电压不额外固定：原文只约束电压范围，固定不同根会改变连续可行域。
    @variable(m, P[1:G, 1:T, 1:W]>=0)
    @variable(m, Q[1:G, 1:T, 1:W]>=0)
    @variable(m, H[1:G, 1:T, 1:W]>=0)
    @variable(m, P_ch[1:G, 1:T, 1:W]>=0)
    @variable(m, P_dis[1:G, 1:T, 1:W]>=0)
    @variable(m, E_BES[1:G, 1:(T+1), 1:W]>=0)
    for g in 1:G
        dev=ds[g]
        kind=dev["kind"]
        for t in 1:T, w in 1:W
            upper=kind=="PV" ? d["renewable_factor"]*dev["available_MW"][t][w] : dev["P_max_MW"]
            kind=="BES" && (upper=0.0)
            if kind=="CHP"
                u=inherited("u", (g, t), dev["commitment"][t])
                upper*=u
                add("6-56", @constraint(m, P[g, t, w]>=dev["P_min_MW"]*u))
                add("6-3", @constraint(m, Q[g, t, w]>=dev["Q_min_Mvar"]*u))
                previous=t==1 ? inherited("P_before", (g, w), dev["previous_P_MW"][w]) :
                         P[g, t-1, w]
                u_previous=t==1 ? inherited("u_before", (g,), dev["previous_commitment"]) :
                           inherited("u", (g, t-1), dev["commitment"][t-1])
                add(
                    "6-4:5/57:58",
                    @constraint(
                        m,
                        P[g, t, w]-previous<=u_previous*dev["ramp_MW_h"]*dt+(1-u_previous)*dev["startup_MW"]
                    )
                )
                add(
                    "6-4:5/57:58",
                    @constraint(
                        m,
                        previous-P[g, t, w]<=u*dev["ramp_MW_h"]*dt+(1-u)*dev["shutdown_MW"]
                    )
                )
            end
            add("6-8/56/60", @constraint(m, P[g, t, w]<=upper))
            qmax=kind in ("CHP", "GT") ?
                 dev["Q_max_Mvar"]*(
                kind=="CHP" ? inherited("u", (g, t), dev["commitment"][t]) : 1
            ) : 0.0
            add("6-3/9", @constraint(m, Q[g, t, w]<=qmax))
            if kind in ("CHP", "EB")
                add("6-11", @constraint(m, H[g, t, w]==dev["heat_ratio"]*P[g, t, w]))
            else
                fix(H[g, t, w], 0; force = true)
            end
            if kind=="BES"
                add("6-12", @constraint(m, P_ch[g, t, w]+P_dis[g, t, w]<=dev["P_max_MW"]))
                add(
                    "6-14",
                    @constraint(
                        m,
                        E_BES[g, t+1, w]==E_BES[g, t, w]+dt*(
                            dev["eta_ch"]*P_ch[g, t, w]-P_dis[g, t, w]/dev["eta_dis"]
                        )
                    )
                )
            else
                fix(P_ch[g, t, w], 0; force = true)
                fix(P_dis[g, t, w], 0; force = true)
            end
        end
        for k in 1:(T+1), w in 1:W
            if kind=="BES"
                add("6-13", @constraint(m, E_BES[g, k, w]>=dev["E_min_MWh"]))
                add("6-13", @constraint(m, E_BES[g, k, w]<=dev["E_max_MWh"]))
                k==1 && add(
                    "6-61",
                    @constraint(
                        m,
                        E_BES[g, k, w]==inherited("E_before", (g, w), dev["initial_MWh"][w])
                    )
                )
            else
                fix(E_BES[g, k, w], 0; force = true)
            end
        end
    end
    @variable(m, P_shed[1:N, 1:T, 1:W]>=0)
    @variable(m, H_shed[1:J, 1:T, 1:W]>=0)
    for n in 1:N, t in 1:T, w in 1:W
        served=e["load_MW"][n][t]-P_shed[n, t, w]
        add("6-54", @constraint(m, P_shed[n, t, w]<=e["load_MW"][n][t]*e["shed_fraction_max"][n]))
        gen=sum(
            (
                (ds[g]["kind"]=="EB" ? -P[g, t, w] : P[g, t, w])+P_dis[g, t, w]-P_ch[g, t, w] for
                g in 1:G if ds[g]["electric_node"]==n
            );
            init = 0.0,
        )
        qgen=sum((Q[g, t, w] for g in 1:G if ds[g]["electric_node"]==n); init = 0.0)
        add(
            "6-19",
            @constraint(
                m,
                gen+(n==e["pcc_node"] ? P_PCC[t, w] : 0)-served==sum(
                    P_line[l, t, w] for l in 1:L if ls[l]["from"]==n
                )-sum(P_line[l, t, w] for l in 1:L if ls[l]["to"]==n)
            )
        )
        add(
            "6-20",
            @constraint(
                m,
                qgen+(n==e["pcc_node"] ? Q_PCC[t, w] : 0)-e["tan_phi"][n]*served==sum(
                    Q_line[l, t, w] for l in 1:L if ls[l]["from"]==n
                )-sum(Q_line[l, t, w] for l in 1:L if ls[l]["to"]==n)
            )
        )
    end
    @variable(m, m_pipe[1:A, 1:T])
    @variable(m, m_source[1:J, 1:T]>=0)
    @variable(m, m_load[1:J, 1:T]>=0)
    for a in 1:A, t in 1:T
        pipe=ps[a]
        add("6-74", @constraint(m, m_pipe[a, t]>=-pipe["flow_max_kg_s"]))
        add("6-74", @constraint(m, m_pipe[a, t]<=pipe["flow_max_kg_s"]))
        add(
            "6-72",
            @constraint(
                m,
                m_pipe[a, t]-inherited("m_normal", (a, t), pipe["normal_flow_kg_s"][t])<=pipe["flow_change_max_kg_s"]
            )
        )
        add(
            "6-72",
            @constraint(
                m,
                inherited("m_normal", (a, t), pipe["normal_flow_kg_s"][t])-m_pipe[a, t]<=pipe["flow_change_max_kg_s"]
            )
        )
    end
    cw=h["c_J_kgK"]/1e6
    for j in 1:J, t in 1:T
        add(
            "R7-R4",
            @constraint(
                m,
                m_source[j, t]-m_load[j, t]==sum(m_pipe[a, t] for a in 1:A if ps[a]["from"]==j)-sum(
                    m_pipe[a, t] for a in 1:A if ps[a]["to"]==j
                )
            )
        )
        add("6-75", @constraint(m, m_source[j, t]<=h["source_flow_max"][j]))
        add("6-75", @constraint(m, m_load[j, t]<=h["load_flow_max"][j]))
        for w in 1:W
            heat=sum(
                (
                    H[g, t, w] for
                    g in 1:G if ds[g]["kind"] in ("CHP", "EB") && ds[g]["heat_node"]==j
                );
                init = 0.0,
            )
            served=h["load_MW"][j][t]-H_shed[j, t, w]
            add(
                "6-55",
                @constraint(m, H_shed[j, t, w]<=h["load_MW"][j][t]*h["shed_fraction_max"][j])
            )
            add("6-83", @constraint(m, heat>=cw*m_source[j, t]*h["source_delta_min"][j]))
            add("6-83", @constraint(m, heat<=cw*m_source[j, t]*h["source_delta_max"][j]))
            add("6-84", @constraint(m, served>=cw*m_load[j, t]*h["load_delta_min"][j]))
            add("6-84", @constraint(m, served<=cw*m_load[j, t]*h["load_delta_max"][j]))
        end
    end
    constants=r7_heat_constants(c)
    C, E0=constants.C, constants.E0
    @variable(m, E_S[1:(T+1), 1:W]>=0)
    @variable(m, E_R[1:(T+1), 1:W]>=0)
    @variable(m, H_CF[1:T, 1:W])
    @variable(m, H_loss_S[1:T, 1:W])
    @variable(m, H_loss_R[1:T, 1:W])
    for (side, E) in (("S", E_S), ("R", E_R)), k in 1:(T+1), w in 1:W
        add("6-80:82", @constraint(m, E[k, w]<=C[side]*(h["$(side)_max_K"]-h["$(side)_min_K"])))
        k==1 && add(
            "R7-A3/90",
            @constraint(m, E[k, w]==inherited("E_$(side)_before", (w,), E0[side][w]))
        )
    end
    for t in 1:T, w in 1:W
        Ts=h["S_min_K"]+E_S[t, w]/C["S"]
        Tr=h["R_min_K"]+E_R[t, w]/C["R"]
        ref_delta=h["S_reference_K"]-h["R_reference_K"]
        # 零点校正后仍保留作者一阶交换近似；真实乘积误差由独立验证器单列。
        add(
            "6-89",
            @constraint(
                m,
                H_CF[t, w]==cw*(
                    sum(m_source[:, t])*ref_delta+h["reference_flow_kg_s"][t]*(Ts-Tr-ref_delta)
                )
            )
        )
        add(
            "6-85",
            @constraint(
                m,
                H_loss_S[t, w]==sum(p["UA_S_W_K"] for p in ps)/1e6*(Ts-h["ambient_K"][t])
            )
        )
        add(
            "6-86",
            @constraint(
                m,
                H_loss_R[t, w]==sum(p["UA_R_W_K"] for p in ps)/1e6*(Tr-h["ambient_K"][t])
            )
        )
        add(
            "R7-A4/76:78",
            @constraint(m, E_S[t+1, w]==E_S[t, w]+dt*(sum(H[:, t, w])-H_loss_S[t, w]-H_CF[t, w]))
        )
        add(
            "R7-A4/77:79",
            @constraint(
                m,
                E_R[t+1, w]==E_R[t, w]+dt*(
                    -sum(h["load_MW"][j][t]-H_shed[j, t, w] for j in 1:J)-H_loss_R[t, w]+H_CF[t, w]
                )
            )
        )
    end
    @objective(
        m,
        Min,
        dt*sum(
            d["probabilities"][w]*(sum(P_shed[:, t, w])+sum(H_shed[:, t, w])) for t in 1:T, w in 1:W
        )
    )
    variables=Dict(
        string(k)=>val for (k, val) in pairs((;
            z,
            beta,
            a_on,
            a_off,
            virtual,
            root_supply,
            P_line,
            Q_line,
            v,
            P_PCC,
            Q_PCC,
            P,
            Q,
            H,
            P_ch,
            P_dis,
            E_BES,
            P_shed,
            H_shed,
            m_pipe,
            m_source,
            m_load,
            E_S,
            E_R,
            H_CF,
            H_loss_S,
            H_loss_R,
        ))
    )
    types=list_of_constraint_types(m)
    all(
        F in (VariableRef, AffExpr) && S in (
            MOI.LessThan{Float64},
            MOI.GreaterThan{Float64},
            MOI.EqualTo{Float64},
            MOI.Interval{Float64},
            MOI.ZeroOne,
        ) for (F, S) in types
    ) || error("恢复模型含未声明非线性约束")
    (;
        model = m,
        variables,
        constraints = cs,
        model_class = fixed_z===nothing ? "MILP" : "LP",
        fault = Int.(gamma),
        fixed_z,
        boundary_parameters = parameters,
        fault_parameters,
    )
end
