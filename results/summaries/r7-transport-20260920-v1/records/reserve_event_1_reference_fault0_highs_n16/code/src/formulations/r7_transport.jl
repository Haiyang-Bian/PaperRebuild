"""
    build_r7_transport_recovery(case, fault, spec; optimizer=nothing, fixed_z=nothing)

R7-D1给定流量的联合恢复MILP（固定电拓扑为LP）：保留原设备、线性电网、质量与端口边界，
显式删除双水箱/Taylor块，换入逐管温度与真实输运。设备和失供重新优化，初态不变。
不求解、不写文件；界只属于所声明给定流量域，不能当作全变流量恢复的下界。
"""
function build_r7_transport_recovery(
    c,
    gamma,
    spec;
    optimizer = nothing,
    fixed_z = nothing,
    deadline = Inf,
)
    x=r7_transport_inputs(c, spec)
    b=build_r7_recovery(c, gamma; optimizer, fixed_z)
    m=b.model
    # 双水箱近似与逐管热状态是不同模型；只保留二者共同的非热状态约束。
    for id in R7_TRANSPORT_PROXY_ROWS
        foreach(ref->delete(m, ref), b.constraints[id])
        delete!(b.constraints, id)
    end
    for key in R7_TRANSPORT_PROXY_VARIABLES
        foreach(v->delete(m, v), b.variables[key])
        delete!(b.variables, key)
        unregister(m, Symbol(key))
    end
    for key in ("m_pipe", "m_source", "m_load")
        b.constraints["R7-D1-"*key]=[
            @constraint(m, b.variables[key][i]==x.v[key][i]) for i in eachindex(x.v[key])
        ]
    end
    d=x.d
    h=x.h
    generated=[
        sum(
            (
                b.variables["H"][g, t, w] for
                (g, z) in enumerate(d["devices"]) if z["kind"] in ("CHP", "EB") && z["heat_node"]==j
            );
            init = AffExpr(0.0),
        ) for j in 1:x.J, t in 1:x.T, w in 1:x.W
    ]
    served=[
        h["load_MW"][j][t]-b.variables["H_shed"][j, t, w] for j in 1:x.J, t in 1:x.T, w in 1:x.W
    ]
    thermal=r7_add_thermal_network!(m, (; x..., generated, served), spec; deadline)
    (;
        model = m,
        variables = b.variables,
        thermal_variables = thermal.variables,
        constraints = merge(b.constraints, thermal.constraints),
        model_class = b.model_class,
        replaced_formulas = collect(R7_TRANSPORT_PROXY_ROWS),
    )
end
