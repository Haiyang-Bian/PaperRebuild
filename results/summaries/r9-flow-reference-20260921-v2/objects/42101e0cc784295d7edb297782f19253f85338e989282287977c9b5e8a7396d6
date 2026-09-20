"""
    set_gurobi_native_primal_start!(model, point)

给已连接Gurobi的JuMP模型写入完整局部非线性初值（PStart），不运行优化。
point必须覆盖全部JuMP变量；仅由固定界和单未知线性等式补齐底层新增辅助量。
原始控制量保持不变，未能确定的辅助量明确拒绝；返回数量、回读及原始残差审计。
当前锁定Gurobi.jl 1.9.3/Gurobi 13.0.3，使用其列索引映射和官方C API。
返回通过只证明初值传递，不保证可行、局部收敛或全局最优。
"""
function set_gurobi_native_primal_start!(model, point)
    Set(keys(point)) == Set(all_variables(model)) ||
        error("Every JuMP variable needs an explicit initial value")
    all(isfinite, values(point)) || error("Nonfinite original initial point")
    native = unsafe_backend(model)
    native isa Gurobi.Optimizer || error("This probe requires Gurobi")
    check(code) = code == 0 || error("Gurobi API error $code")
    check(Gurobi.GRBupdatemodel(native))
    n = MOI.get(native, Gurobi.ModelAttribute("NumVars"))
    nr = MOI.get(native, Gurobi.ModelAttribute("NumConstrs"))
    initial = fill(NaN, n)
    for (x, val) in point
        col = Int(Gurobi.c_column(native, optimizer_index(x))) + 1
        initial[col] = val
    end
    original = copy(initial)
    lb, ub = zeros(n), zeros(n)
    check(Gurobi.GRBgetdblattrarray(native, "LB", 0, n, lb))
    check(Gurobi.GRBgetdblattrarray(native, "UB", 0, n, ub))
    fixed_added = 0
    for i in eachindex(initial)
        if isnan(initial[i]) && lb[i] == ub[i] && abs(lb[i]) < 1e99
            initial[i] = lb[i]
            fixed_added += 1
        end
    end
    nnz = Ref{Cint}()
    check(Gurobi.GRBgetconstrs(native, nnz, C_NULL, C_NULL, C_NULL, 0, nr))
    begincol, columns, coeffs = zeros(Cint, nr+1), zeros(Cint, nnz[]), zeros(nnz[])
    check(Gurobi.GRBgetconstrs(native, nnz, begincol, columns, coeffs, 0, nr))
    begincol[end] = nnz[]
    rhs, sense = zeros(nr), zeros(UInt8, nr)
    check(Gurobi.GRBgetdblattrarray(native, "RHS", 0, nr, rhs))
    check(Gurobi.GRBgetcharattrarray(native, "Sense", 0, nr, sense))
    linear_added = 0
    for _ in 1:10
        added = 0
        for row in 1:nr
            sense[row] == UInt8('=') || continue
            unknown_col, unknown_coef, unknown_count = 0, 0.0, 0
            known = 0.0
            for k in (begincol[row]+1):begincol[row+1]
                col, a = Int(columns[k])+1, coeffs[k]
                a == 0 && continue
                if isnan(initial[col])
                    unknown_col, unknown_coef = col, a
                    unknown_count += 1
                else
                    known += a*initial[col]
                end
            end
            if unknown_count == 1
                initial[unknown_col] = (rhs[row]-known)/unknown_coef
                added += 1
            end
        end
        linear_added += added
        added == 0 && break
    end
    missing = findall(isnan, initial)
    isempty(missing) ||
        error("Unresolved native initial variables: $(length(missing)); first=$(first(missing))")
    all(isfinite, initial) || error("Nonfinite native initial point")
    all(isnan(original[i]) || original[i] == initial[i] for i in eachindex(initial)) ||
        error("Original scientific point changed")
    max_linear = 0.0
    for row in 1:nr
        lhs = sum(
            coeffs[k]*initial[Int(columns[k])+1] for k in (begincol[row]+1):begincol[row+1];
            init = 0.0,
        )
        residual =
            sense[row] == UInt8('=') ? abs(lhs-rhs[row]) :
            sense[row] == UInt8('<') ? max(0.0, lhs-rhs[row]) : max(0.0, rhs[row]-lhs)
        max_linear = max(max_linear, residual)
    end
    check(Gurobi.GRBsetdblattrarray(native, "PStart", 0, n, initial))
    check(Gurobi.GRBupdatemodel(native))
    confirmed = zeros(n)
    check(Gurobi.GRBgetdblattrarray(native, "PStart", 0, n, confirmed))
    confirmed == initial || error("Native PStart differs after assignment")
    return Dict(
        "native_count"=>n,
        "original_count"=>length(point),
        "fixed_auxiliary_count"=>fixed_added,
        "linear_auxiliary_count"=>linear_added,
        "all_finite"=>all(isfinite, confirmed),
        "original_point_unchanged"=>true,
        "maximum_linear_violation"=>max_linear,
        "maximum_bound_violation"=>maximum(max.(lb-initial, initial-ub, 0.0)),
    )
end

"""
    gurobi_nl_iteration_trace!(model)

安装只读原生NLBAR回调，返回随求解追加的目标、原始/对偶及互补指标数组。
这些是求解器内部指标，不是调度解或独立A1证据；不改变参数、不注入候选。
只用于可选Gurobi环境，须在最终原生初值设置之前调用，以免结构更新使初值失效。
"""
function gurobi_nl_iteration_trace!(model)
    rows = NamedTuple[]
    function callback(data, where)
        where == Gurobi.GRB_CB_NLBAR || return
        count = Ref{Cint}()
        Gurobi.GRBcbget(data, where, Gurobi.GRB_CB_NLBAR_ITRCNT, count) == 0 ||
            error("Iteration callback failed")
        values = map((
            Gurobi.GRB_CB_NLBAR_PRIMOBJ,
            Gurobi.GRB_CB_NLBAR_PRIMINF,
            Gurobi.GRB_CB_NLBAR_DUALINF,
            Gurobi.GRB_CB_NLBAR_COMPL,
        )) do key
            x = Ref{Cdouble}()
            Gurobi.GRBcbget(data, where, key, x) == 0 || error("Value callback failed")
            x[]
        end
        push!(
            rows,
            (;
                iteration = Int(count[]),
                objective = values[1],
                primal = values[2],
                dual = values[3],
                complementarity = values[4],
            ),
        )
    end
    MOI.set(model, Gurobi.CallbackFunction(), callback)
    return rows
end
