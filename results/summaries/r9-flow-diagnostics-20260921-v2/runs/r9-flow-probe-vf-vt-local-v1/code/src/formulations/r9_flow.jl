# 收集保留关系的依赖，用来删除已消去WMM留下的孤立乘积变量；不改变其余模型块。
function r9_flow_dependencies!(used, x)
    if x isa VariableRef
        push!(used, x)
    elseif x isa AbstractArray
        foreach(y -> r9_flow_dependencies!(used, y), x)
    elseif x isa Union{AffExpr,QuadExpr}
        for (_, v) in linear_terms(x)
            push!(used, v)
        end
        if x isa QuadExpr
            for (_, a, b) in quad_terms(x)
                push!(used, a, b)
            end
        end
    elseif !(x isa Number)
        throw(ArgumentError("未登记的保留约束类型$(typeof(x))"))
    end
end

"""
    build_r9_flow_model(case; mode=:VF_VT, flow_schedule=nothing, physical=false, optimizer=nothing)

构建R9连续变流量的WMM单步分段表示，支持四模式及给定流量子问题（R9-V1—V4）。
仅在整个输入盒通过audit_r9_flow_domain时消去α/β互补及其乘积辅助量；设备、电网、
精确混合、热功率和水压约束复用R2。末端同时固定入口温度及流量记忆。
flow_schedule显式给定时以数值代入热系数，未给定的VF流量为真正的连续决策变量。
返回变量、公式映射、输入域证据和实际约束类型，不求解、不写文件。
本版本保留字面终端等式，未继承固定模式的参考锚定；不保证微小舍入矛盾已解决。
physical=true恢复原电网及κ等式；非凸参考不作为作者PG实现或已获全局最优的证明。
"""
function build_r9_flow_model(
    c::R2Case;
    mode = :VF_VT,
    flow_schedule = nothing,
    physical = false,
    optimizer = nothing,
)
    audit_r9_pv_input(c).pass || throw(ArgumentError("R9输入核查失败"))
    domain = audit_r9_flow_domain(c)
    domain.pass || throw(ArgumentError("完整流量盒跨越WMM分段，不能使用本消元"))
    op = R3OperationSpec(c; mode, core_periods = c.data["T"], bounded_return = true)
    fixed = r3_is_cf(op) || !isnothing(flow_schedule)
    mf = r2_flow_matrix(c, flow_schedule)
    r3_is_cf(op) &&
        maximum(abs, mf - r2_flow_matrix(c)) > 1e-12 &&
        throw(ArgumentError("CF模式不能传入不同参考流量"))
    b = build_r2_model(c; fixed_flows = fixed, flow_schedule = fixed ? mf : nothing, operation = op)
    model, v, cs = b.model, b.variables, b.constraints
    d, h = c.data, c.data["heat"]
    E, T = length(h["pipes"]), d["T"]
    # 删除旧WMM关系后，保留其余块实际依赖及公开变量；孤立辅助量不交给求解器。
    for id in ("3-27", "3-28", "3-30", "3-31", "3-33", "3-34")
        foreach(cr -> delete(model, cr), get(cs, id, Any[]))
        delete!(cs, id)
    end
    for p in 1:E, key in ("alpha_$p", "beta_$p")
        delete!(v, key)
    end
    used = Set{VariableRef}()
    for array in values(v)
        r9_flow_dependencies!(used, array)
    end
    for (F, S) in list_of_constraint_types(model)
        F == VariableRef && continue
        for cr in all_constraints(model, F, S)
            r9_flow_dependencies!(used, constraint_object(cr).func)
        end
    end
    r9_flow_dependencies!(used, objective_function(model))
    delete(model, [x for x in all_variables(model) if x ∉ used])
    inverse = Matrix{Any}(undef, E, T)
    for (p, pipe) in enumerate(h["pipes"])
        m0 = first(pipe["fixed_flow"])
        q = domain.rows[p].mass_kg / domain.rows[p].dt_s
        C = pipe["epsilon_W_mK"] * pipe["length_m"] / (2h["cp_J_kgK"])
        for t in 1:T
            if fixed
                inverse[p, t] = m0 / mf[p, t]
            else
                inverse[p, t] = @variable(
                    model,
                    lower_bound=m0/pipe["flow_max"],
                    upper_bound=m0/pipe["flow_min"],
                    start=1.0
                )
                # 无量纲倒数变量，避免直接给1/m施加很小的绝对残差。
                r2_add!(
                    cs,
                    "R9-V1-reciprocal",
                    @constraint(model, v["m_pipe"][p, t] / m0 * inverse[p, t] == 1)
                )
            end
        end
        lag = ceil(Int, q / pipe["flow_min"]) + 1
        alpha, beta = Matrix{Any}(zeros(T, lag+1)), Matrix{Any}(zeros(T, lag+1))
        for t in 1:T
            current = fixed ? mf[p, t] : v["m_pipe"][p, t]
            previous_inverse = t > 1 ? inverse[p, t-1] : m0 / last(pipe["flow_history"])
            alpha[t, 1] = q / m0 * inverse[p, t]
            beta[t, 1] = 1.0
            beta[t, 2] = q / m0 * previous_inverse
            exponent = -C / m0 * (inverse[p, t] + previous_inverse)
            attenuation = fixed ? exp(exponent) : @expression(model, exp(exponent))
            for side in ("S", "R")
                inlet = v["tau_"*side*"_in"][p, t]
                previous = t > 1 ? v["tau_"*side*"_in"][p, t-1] : last(pipe[side*"_history_K"])
                star, outlet = v["tau_"*side*"_star"][p, t], v["tau_"*side*"_out"][p, t]
                # 先作温差再乘流量；仍为精确乘积，不把变流量时延取整。
                r2_add!(
                    cs,
                    "R9-V2-star",
                    @constraint(
                        model,
                        current / m0 * (star-inlet) + q / m0 * (inlet-previous) == 0
                    )
                )
                r2_add!(
                    cs,
                    "R9-V3-loss",
                    @constraint(
                        model,
                        outlet-d["ambient_K"][t] == (star-d["ambient_K"][t])*attenuation
                    )
                )
            end
        end
        v["alpha_$p"], v["beta_$p"] = alpha, beta
        # 单步域的WMM状态还含上一时段流量；温度相同不能替代这条关系。
        r2_add!(
            cs,
            "R9-V4-flow-memory",
            @constraint(model, v["m_pipe"][p, T] == last(pipe["flow_history"]))
        )
        for side in ("S", "R")
            r2_add!(
                cs,
                "R9-V4-temperature-memory",
                @constraint(model, v["tau_"*side*"_in"][p, T] == last(pipe[side*"_history_K"]))
            )
        end
    end
    v["r9_inverse_relative"] = inverse
    physical && r3_add_physics!(c, b)
    isnothing(optimizer) || set_optimizer(model, optimizer)
    return merge(
        b,
        (;
            class = r2_model_class(model),
            flow_schedule = mf,
            cost_expression = objective_function(model),
            elastic_rows = NamedTuple[],
            objective_kind = "operating_cost",
            variant = "r9_short_pipe_literal_v1",
            flow_domain = domain,
            terminal_interpretation = "literal",
        ),
    )
end
