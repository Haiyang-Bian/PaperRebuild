"""
    validate_r9_reduced_solution(case, result; check_representation=true)

沿用旧的独立物理回代，另检查参考锚定的完整自由空间、源温重构和整日能量。
公开重读默认从输入重新构造终端系数核对证据身份，不调用优化器；物理残差仍由独立验证器计算。
求解入口刚构建过矩阵时可跳过重复构造，但不跳过保存数值、源温或能量检查。
字面版本和旧开发记录保留原身份；近可行候选须通过独立的诊断入口检查，不更改正式状态。
"""
function validate_r9_reduced_solution(c::R2Case, r; check_representation = true)
    base = validate_r9_pv_solution(c, r)
    rows = copy(base.rows)
    haskey(r["stage"], "values") ||
        return merge(base, (; adopted_terminal_pass = false, daily_energy_pass = false))
    v = r["stage"]["values"]
    adopted = true
    method = get(r, "terminal_interpretation", "literal")
    method in ("literal", "reference_anchored") || throw(ArgumentError("未知终端解释"))
    if method == "reference_anchored"
        cert = r["terminal_certificate"]
        cert["method"] == method && cert["anchor_shift_limit_K"] == 1e-10 ||
            throw(ArgumentError("锚定定义改变"))
        expected =
            r["mode"] == "CF_VT" ?
            [
                [j, t] for (j, n) in enumerate(c.data["heat"]["nodes"]) if n["role"] == "source" for
                t in 1:c.data["T"]
            ] : Vector{Int}[]
        cert["source_coordinates"] == expected || throw(ArgumentError("源温坐标改变"))
        U = isempty(expected) ? zeros(0, 0) : permutedims(hcat(cert["basis"]...))
        A =
            isempty(cert["terminal_matrix"]) ? zeros(0, length(expected)) :
            permutedims(hcat(cert["terminal_matrix"]...))
        size(U) == (length(expected), cert["free_source_count"]) ||
            throw(ArgumentError("自由空间维度错误"))
        cert["rank_exact_binary"] + size(U, 2) == length(expected) ||
            throw(ArgumentError("遗漏自由方向"))
        all(isfinite, U) && all(isfinite, A) || throw(ArgumentError("非法基底系数"))
        if check_representation
            b = build_r9_reduced_model(c; mode = Symbol(r["mode"]), terminal = :literal)
            x = [
                only(x for (_, x) in linear_terms(b.variables["tau_S_port"][j, t])) for
                (j, t) in expected
            ]
            actual = [
                coefficient(constraint_object(cr).func, xj) for
                cr in get(b.constraints, "R9-P6", Any[]), xj in x
            ]
            A == actual || throw(ArgumentError("终端矩阵与输入不符"))
            r9_exact_nullspace(A).rank == cert["rank_exact_binary"] ||
                throw(ArgumentError("精确秩不符"))
        end
        y = v["r9_terminal_coordinates"]
        length(y) == size(U, 2) && all(isfinite, y) || throw(ArgumentError("自由坐标无效"))
        function record(entity, residual, unit, tolerance)
            push!(
                rows,
                (
                    equation = "R9-N6-adopted-state",
                    scope = "model",
                    entity = string(entity),
                    t = 0,
                    residual = Float64(abs(residual)),
                    unit,
                    tolerance,
                    pass = isfinite(residual)&&abs(residual)<=tolerance,
                ),
            )
        end
        for (i, (j, t)) in enumerate(expected)
            predicted = c.data["heat"]["S_reference_K"] + sum(U[i, k]*y[k] for k in eachindex(y))
            record("source_$(j)_$(t)", v["tau_S_port"][j][t]-predicted, "K", 1e-10)
        end
        record("anchor", maximum(abs, cert["anchor_shifts_K"]; init = 0.0), "K", 1e-10)
        delta = U*Float64.(y)
        record("homogeneous_terminal", maximum(abs, A*delta; init = 0.0), "K", 1e-10)
        record("basis_bound", cert["basis_error_bound_K"], "K", 1e-10)
        record(
            "basis_coordinate_bound",
            max(0.0, maximum(abs, y; init = 0.0)-cert["basis_coordinate_bound_K"]),
            "K",
            1e-10,
        )
        adopted = all(row.pass for row in rows if row.equation == "R9-N6-adopted-state")
    end
    energy = r9_daily_heat_balance(c, v)
    push!(
        rows,
        (
            equation = "R9-A1-day-energy",
            scope = "physics",
            entity = "network",
            t = 0,
            residual = energy.residual_MWh,
            unit = "MWh",
            tolerance = energy.tolerance_MWh,
            pass = energy.pass,
        ),
    )
    return merge(
        base,
        (;
            model_pass = base.model_pass&&adopted,
            physical_pass = base.physical_pass&&adopted&&energy.pass,
            terminal_pass = base.terminal_pass&&adopted,
            rows,
            adopted_terminal_pass = adopted,
            daily_energy_pass = energy.pass,
        ),
    )
end
