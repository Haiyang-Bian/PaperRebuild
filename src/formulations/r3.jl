# 诊断只改变这些明确登记的耦合行；容量、负荷、边界均保持为硬约束。
function r3_thermal_rows(c, b, m)
    d, cs = c.data, b.constraints
    h, T = d["heat"], d["T"]
    rows = NamedTuple[]
    active = findall(n -> n["role"] != "transit", h["nodes"])
    length(cs["3-17"]) == 2length(active)*T || error("3-17映射结构改变，须重审诊断行")
    for (k, j) in enumerate(active), t in 1:T
        # 每个端口先定义w=mΔT，再H=cp*w；只松弛后一个有MW单位的物理关系。
        push!(
            rows,
            (
                equation = "3-17",
                entity = string(j),
                t,
                unit = "MW",
                conversion = 1.0,
                constraint = cs["3-17"][2((k-1)*T+t)],
            ),
        )
    end
    ports = r2_fixed_port_flows(d, m)
    for side in ("S", "R"), j in eachindex(h["nodes"]), t in 1:T
        edges, local_in = r2_inflows(d, side, j)
        total = sum(m[p, t] for p in edges; init = 0.0) + (local_in ? ports[j, t] : 0.0)
        total > 0 || throw(ArgumentError("混合总入流必须为正"))
        factor = length(edges)+Int(local_in) == 1 ? 1.0 : 1/total
        id = side == "S" ? "3-35" : "3-36"
        length(cs[id]) == length(h["nodes"])*T || error("混合行映射改变")
        push!(
            rows,
            (
                equation = id,
                entity = side*string(j),
                t,
                unit = "K",
                conversion = factor,
                constraint = cs[id][(j-1)*T+t],
            ),
        )
    end
    for p in eachindex(h["pipes"]), t in 1:T, (k, side) in enumerate(("S", "R"))
        index = 2((p-1)*T+t-1)+k
        for id in ("3-33", "3-34")
            length(cs[id]) == 2length(h["pipes"])*T || error("WMM行映射改变")
            push!(
                rows,
                (
                    equation = id,
                    entity = side*string(p),
                    t,
                    unit = "K",
                    conversion = id=="3-33" ? 1/m[p, t] : 1.0,
                    constraint = cs[id][index],
                ),
            )
        end
    end
    return rows
end

function r3_add_physics!(c, b)
    d, v, model = c.data, b.variables, b.model
    for (p, e) in enumerate(d["electric"]["edges"]), t in 1:d["T"]
        r2_add!(
            b.constraints,
            "R3-electric-equality",
            @constraint(
                model,
                v["v"][e["from"], t]*v["ell"][p, t] == v["P_branch"][p, t]^2+v["Q_branch"][p, t]^2
            )
        )
    end
    for side in ("S", "R"), (p, e) in enumerate(d["heat"]["pipes"]), t in 1:d["T"]
        r2_add!(
            b.constraints,
            "R3-kappa-equality",
            @constraint(model, v["kappa_"*side][p, t] == e["mu_kPa_s2_kg2"]*v["m_pipe"][p, t]^2)
        )
    end
end

"""
    build_r3_subproblem(case, flow; mode=:dispatch, physical=false, optimizer=nothing)

构建式3-60的固定流量WMM特例。flow为管道×时段kg/s，历史来自原案例。
dispatch最小化运行成本；diagnostic仅对热功率、混合、输运/损耗行加入双向松弛，
以输入冻结的MW/K尺度归一化。physical额外恢复电网支路等式和κ=μm²，此时非凸。
返回变量、公式映射、成本表达式与诊断元数据；不求解、不写文件，不实现3-61至3-66。
"""
function build_r3_subproblem(
    c::R2Case,
    flow;
    mode = :dispatch,
    physical = false,
    optimizer = nothing,
)
    mode in (:dispatch, :diagnostic) || throw(ArgumentError("未知R3子问题模式"))
    mode == :diagnostic && physical && throw(ArgumentError("诊断保持作者锥松弛，不能标为物理调度"))
    m = r2_flow_matrix(c, flow)
    b = build_r2_model(c; fixed_flows = true, flow_schedule = m, optimizer)
    cost = objective_function(b.model)
    rows = NamedTuple[]
    if mode == :diagnostic
        d, h = c.data, c.data["heat"]
        heat_scale = max(
            1.0,
            sum(
                g["P_max"]*g["heat_ratio"] for g in d["devices"] if g["kind"] in ("CHP", "EB");
                init = 0.0,
            ),
            maximum(sum(n["H_MW"][t] for n in h["nodes"]) for t in 1:d["T"]),
        )
        temp_scale =
            max(1.0, h["S_bounds_K"][2]-h["S_bounds_K"][1], h["R_bounds_K"][2]-h["R_bounds_K"][1])
        thermal = r3_thermal_rows(c, b, m)
        model = b.model
        pos = @variable(model, [1:length(thermal)], lower_bound=0)
        neg = @variable(model, [1:length(thermal)], lower_bound=0)
        b.variables["elastic_positive"], b.variables["elastic_negative"] = pos, neg
        for (i, row) in enumerate(thermal)
            scale = row.unit == "MW" ? heat_scale : temp_scale
            constraint_object(row.constraint).func isa AffExpr || error("诊断预期线性约束")
            set_normalized_coefficient(row.constraint, pos[i], -scale/row.conversion)
            set_normalized_coefficient(row.constraint, neg[i], scale/row.conversion)
            push!(
                rows,
                (equation = row.equation, entity = row.entity, t = row.t, unit = row.unit, scale),
            )
        end
        @objective(model, Min, sum(pos)+sum(neg))
    elseif physical
        r3_add_physics!(c, b)
    end
    return merge(
        b,
        (
            class = r2_model_class(b.model),
            cost_expression = cost,
            elastic_rows = rows,
            flow_schedule = m,
            objective_kind = mode==:diagnostic ? "normalized_slack" : "operating_cost",
            variant = mode==:diagnostic ? "r3_sp_elastic_v1" :
                      physical ? "r3_fixed_physical_v1" : "r3_sp_checked_v1",
        ),
    )
end

function r3_build_repair(c, m0)
    b = build_r2_model(c)
    cost = objective_function(b.model)
    r3_add_physics!(c, b)
    model = b.model
    deviations = VariableRef[]
    for (p, pipe) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"]
        m = b.variables["m_pipe"][p, t]
        width = pipe["flow_max"]-pipe["flow_min"]
        if width == 0
            fix(m, pipe["flow_min"]; force = true)
        else
            q = @variable(model, lower_bound=0)
            @constraint(model, q >= (m-m0[p, t])/width)
            @constraint(model, q >= (m0[p, t]-m)/width)
            push!(deviations, q)
        end
        set_start_value(m, m0[p, t])
    end
    b.variables["flow_deviation"] = deviations
    @objective(model, Min, sum(deviations))
    return merge(
        b,
        (
            class = r2_model_class(model),
            cost_expression = cost,
            elastic_rows = NamedTuple[],
            flow_schedule = m0,
            objective_kind = "flow_distance",
            variant = "r3_direct_repair_v1",
        ),
    )
end
