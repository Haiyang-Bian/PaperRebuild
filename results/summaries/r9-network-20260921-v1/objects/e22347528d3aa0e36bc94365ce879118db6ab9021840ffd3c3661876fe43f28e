# 原模块仍保持默认完整模型。对照入口只删除显式热变量及包含它们的旧耦合行，
# 保留设备、电池、失供上限、电网与启动费用；不把删除后的占位量保存为温度。
function r8_energy_drop!(model, dictionaries, fields)
    removed=Set{VariableRef}()
    for (dict, keys) in zip(dictionaries, fields), key in keys
        haskey(dict, key) || error("待替换热字段缺失：$key")
        union!(removed, dict[key])
    end
    for con in all_constraints(model; include_variable_in_set_constraints = true)
        f=constraint_object(con).func
        f isa Union{VariableRef,AffExpr} || error("能流替换只接受原线性共用块")
        touches=f isa VariableRef ? f in removed : any(v in removed for (_, v) in linear_terms(f))
        touches && delete(model, con)
    end
    for v in removed
        delete(model, v)
    end
    for (dict, keys) in zip(dictionaries, fields), key in keys
        delete!(dict, key)
        haskey(object_dictionary(model), Symbol(key)) && unregister(model, Symbol(key))
    end
    nothing
end

function r8_energy_balance!(m, d, s, v, prefix; recovery = false)
    h=d["heat"]
    T=d["periods"]
    W=length(d["probabilities"])
    cap=s["pipe_capacity_MW"]
    flow=[
        @variable(m, lower_bound=0, upper_bound=cap[a], base_name="$(prefix)_H_pipe[$a,$t,$w]") for
        a in eachindex(h["pipes"]), t in 1:T, w in 1:W
    ]
    loss=r8_energy_losses(d, s)
    rows=Any[]
    for j in 1:h["nodes"], t in 1:T, w in 1:W
        generated=sum(
            v["H"][g, t, w] for
            (g, z) in enumerate(d["devices"]) if z["kind"] in ("CHP", "EB")&&z["heat_node"]==j;
            init = 0.0,
        )
        incoming=sum(
            flow[a, t, w]-loss[a, t] for (a, p) in enumerate(h["pipes"]) if p["to"]==j;
            init = 0.0,
        )
        outgoing=sum(flow[a, t, w] for (a, p) in enumerate(h["pipes"]) if p["from"]==j; init = 0.0)
        delivered=h["load_MW"][j][t]-(recovery ? v["H_shed"][j, t, w] : 0.0)
        # R8-E1：每根供回水管对合并为有向净热流，流入端扣除该管对冻结散热。
        push!(rows, @constraint(m, generated+incoming==delivered+outgoing))
    end
    for a in eachindex(h["pipes"]), t in 1:T, w in 1:W
        push!(rows, @constraint(m, flow[a, t, w]>=loss[a, t]))
    end
    (; flow, rows, loss)
end

"""
    build_r8_energy_model(case, spec; optimizer=nothing, deadline=Inf, normal_result=nothing)

构建独立稳态能流对照；不求解、不写文件。正常/恢复均去掉热库存、温度、水力和流率，
保留逐时能流容量与节点守恒。所有恢复继承同一正常CHP启停、前一时刻出力和电池初态。
normal_result用于固定原正常物理计划的独立最坏失供评估，不把新恢复反馈给正常计划。
R8-E1至E3；只有实际约束全部为线性/整数时才报告MILP/LP。
"""
function build_r8_energy_model(
    c::R7PlanningCase,
    s;
    optimizer = nothing,
    deadline = Inf,
    normal_result = nothing,
)
    r8_energy_check(c, s)
    time()<deadline || error("energy_build_deadline")
    b=build_r7_normal(c.normal; optimizer)
    m, nv=b.model, b.variables
    r8_energy_drop!(m, (nv,), (R8_ENERGY_NORMAL_REMOVED,))
    nh=r8_energy_balance!(m, c.normal.data, s, nv, "normal")
    nc=Dict(id=>block.variables for (id, block) in b.chp)
    cost=objective_function(m)
    evaluation=normal_result!==nothing
    recovery=Any[]
    eta=VariableRef[]
    if evaluation || s["mode"]!="economic"
        caps=r8_loss_caps(c)
        eta=[
            @variable(m, lower_bound=0, upper_bound=cap, base_name="energy_eta_$e") for
            (e, cap) in enumerate(caps)
        ]
        for (k, pair) in enumerate(r7_planning_pairs(c))
            time()<deadline || error("energy_build_deadline")
            event=c.specification["events"][pair.event]
            at, T=event["event_start"], event["periods"]
            template=r7_event_template(c, pair.event)
            rb=build_r7_recovery(template, pair.fault; boundary_variables = true)
            r8_energy_drop!(
                rb.model,
                (rb.variables, rb.boundary_parameters),
                (R8_ENERGY_RECOVERY_REMOVED, ("E_S_before", "E_R_before", "m_normal")),
            )
            rh=r8_energy_balance!(
                rb.model,
                template.data,
                s,
                rb.variables,
                "recovery_$k";
                recovery = true,
            )
            block=r7_append_linear_block!(m, rb.model, "energy_$k")
            rv=Dict(key=>map(v->block.variables[v], a) for (key, a) in rb.variables)
            rp=Dict(key=>map(v->block.variables[v], a) for (key, a) in rb.boundary_parameters)
            hf=map(v->block.variables[v], rh.flow)
            for (g, z) in enumerate(c.normal.data["devices"])
                if z["kind"]=="CHP"
                    u=nc[z["id"]]["u_CHP"]
                    for t in 1:T
                        @constraint(m, rp["u"][g, t]==u[at+t-1])
                    end
                    @constraint(m, rp["u_before"][g]==(at==1 ? z["previous_commitment"] : u[at-1]))
                    for w in eachindex(c.normal.data["probabilities"])
                        @constraint(
                            m,
                            rp["P_before"][g, w]==(
                                at==1 ? z["previous_P_MW"][w] : nv["P"][g, at-1, w]
                            )
                        )
                    end
                elseif z["kind"]=="BES"
                    for w in eachindex(c.normal.data["probabilities"])
                        @constraint(m, rp["E_before"][g, w]==nv["E_BES"][g, at, w])
                    end
                end
            end
            @constraint(m, block.objective<=eta[pair.event])
            !evaluation &&
                s["mode"]=="threshold" &&
                @constraint(m, block.objective<=s["limits_MWh"][pair.event])
            if s["recovery_topology"]=="retain_surviving"
                for (l, line) in enumerate(c.normal.data["electric"]["lines"])
                    @constraint(m, rv["z"][l]==line["base_closed"]*(1-pair.fault[l]))
                end
            end
            push!(
                recovery,
                (;
                    pair,
                    variables = rv,
                    boundary_parameters = rp,
                    heat_flow = hf,
                    loss = block.objective,
                ),
            )
        end
    end
    if evaluation
        q=r8_energy_normal_check(c, s, normal_result)
        q["model_pass"] || error("不能评估未通过的正常能流计划")
        for (dict, values) in (
            (nv, normal_result["values"]),
            (Dict("H_pipe"=>nh.flow), normal_result["energy_values"]),
        )
            for (key, a) in dict
                vals=r7_unpack(values, key)
                for I in CartesianIndices(a)
                    @constraint(m, a[I]==vals[I])
                end
            end
        end
        for (id, dict) in nc, (key, a) in dict
            vals=r7_unpack(normal_result["chp_values"][id], key)
            for I in CartesianIndices(a)
                @constraint(m, a[I]==vals[I])
            end
        end
        @objective(m, Min, sum(eta))
    else
        @objective(m, Min, cost+(s["mode"]=="penalty" ? s["penalty_USD_MWh"]*sum(eta) : 0.0))
    end
    time()<deadline || error("energy_build_deadline")
    types=list_of_constraint_types(m)
    all(
        F in (VariableRef, AffExpr) && S in (
            MOI.EqualTo{Float64},
            MOI.GreaterThan{Float64},
            MOI.LessThan{Float64},
            MOI.Interval{Float64},
            MOI.ZeroOne,
        ) for (F, S) in types
    ) || error("稳态能流出现未声明非线性")
    (;
        model = m,
        normal_variables = nv,
        chp_variables = nc,
        normal_heat_flow = nh.flow,
        normal_cost = cost,
        recovery,
        eta,
        objective_kind = r8_objective_kind(s; evaluation),
        model_class = any(is_binary, all_variables(m)) ? "MILP" : "LP",
        model_types = [string(F)*" in "*string(S) for (F, S) in types],
    )
end
