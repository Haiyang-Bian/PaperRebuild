function r8_preparation_rows!(m, v, s)
    rows=Any[]
    if s["heat_preparation"]=="no_net_charge"
        for side in ("S", "R")
            E=v["E_pipe_$side"]
            for a in axes(E, 1), t in axes(E, 2), w in axes(E, 3)
                push!(rows, @constraint(m, E[a, t, w]<=E[a, 1, w]))
            end
        end
    end
    rows
end

"""
    build_r8_model(case, flow, spec; optimizer=nothing, deadline=Inf, normal_result=nothing)

构建R8-T1至T4三种目标，或固定normal_result后的独立恢复评估。经济基线只建立正常模型，
不将灾后存在性约束偷偷加入经济基线；其他模式使用R7详细共同状态及全部允许故障。
罚项采用每事件epigraph，内部是最坏故障而不是故障求和。固定计划评估最小化各事件epigraph之和，
其界以MWh计，不能作为正常成本界。无求解/写文件副作用。
"""
function build_r8_model(
    c::R7PlanningCase,
    flow,
    s;
    optimizer = nothing,
    deadline = Inf,
    normal_result = nothing,
)
    r8_check(c, flow, s)
    evaluation=normal_result!==nothing
    if !evaluation && s["mode"]=="economic"
        b=build_r7_normal_flow(
            c.normal,
            flow["normal_flow"];
            optimizer,
            deadline,
            energy_balance = true,
        )
        r8_preparation_rows!(b.model, b.variables, s)
        return (;
            model = b.model,
            normal_variables = b.variables,
            chp_variables = Dict(id=>block.variables for (id, block) in b.chp),
            normal_flow = b.flow,
            recovery = Any[],
            eta = Any[],
            normal_cost = objective_function(b.model),
            objective_kind = r8_objective_kind(s),
            model_class = b.model_class,
            model_types = b.model_types,
            carrier = nothing,
        )
    end
    rc, f=r8_carrier(c, flow)
    b=build_r7_flow_planning(rc, f; optimizer, deadline)
    m=b.model
    cost=objective_function(m)
    r8_preparation_rows!(m, b.normal_variables, s)
    caps=r8_loss_caps(c)
    eta=[
        @variable(m, lower_bound=0, upper_bound=cap, base_name="r8_loss_$e") for
        (e, cap) in enumerate(caps)
    ]
    for w in b.recovery
        e=w.pair.event
        @constraint(m, w.loss<=eta[e])
        if !evaluation && s["mode"]=="threshold"
            @constraint(m, w.loss<=s["limits_MWh"][e])
        end
        if s["recovery_topology"]=="retain_surviving"
            for (l, line) in enumerate(c.normal.data["electric"]["lines"])
                @constraint(m, w.variables["z"][l]==line["base_closed"]*(1-w.pair.fault[l]))
            end
        end
    end
    if evaluation
        q=validate_r7_normal_flow(c.normal, flow["normal_flow"], normal_result)
        q["model_pass"] || error("不能评估未通过正常模型的计划")
        for (key, a) in b.normal_variables
            vals=r7_unpack(normal_result["values"], key)
            size(a)==size(vals) || error("固定正常计划形状错误")
            for I in CartesianIndices(a)
                @constraint(m, a[I]==vals[I])
            end
        end
        for (id, block) in b.chp_variables, (key, a) in block
            vals=r7_unpack(normal_result["chp_values"][id], key)
            for I in CartesianIndices(a)
                @constraint(m, a[I]==vals[I])
            end
        end
        for (key, a) in b.normal_flow
            vals=r7_unpack(normal_result["flow_values"], key)
            for I in CartesianIndices(a)
                if a[I] isa Real
                    a[I]==vals[I] || error("固定流量记录改变输入常数")
                else
                    @constraint(m, a[I]==vals[I])
                end
            end
        end
        @objective(m, Min, sum(eta))
    elseif s["mode"]=="penalty"
        @objective(m, Min, cost+s[r7_money_key(c.normal.data, "penalty_USD_MWh")]*sum(eta))
    else
        @objective(m, Min, cost)
    end
    (;
        b...,
        eta,
        normal_cost = cost,
        objective_kind = r8_objective_kind(s; evaluation),
        carrier = (; case = rc, flow = f),
    )
end
