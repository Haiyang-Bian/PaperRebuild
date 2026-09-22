const R5_EXECUTION_MODEL_FILE = @__FILE__

"""
    build_r5_execution_selector(case, clearing_objective; kind, optimizer=nothing,
                                spec=R5MarketExecutionSpec())

构建原始或对偶最优面内的严格凸二次选择问题，不求解、不写文件。
kind=:primal保留原LP全部行及原目标等式；kind=:dual保留独立对偶及强对偶等式。
全部显式变量都有正二次权重，所以非空闭最优面上有唯一最小范数解。
没有给原目标加epsilon项，也没有截断任何价格；原市场残差仍独立验算。
"""
function build_r5_execution_selector(
    c::R5MarketCase,
    clearing_objective;
    kind,
    optimizer = nothing,
    spec = R5MarketExecutionSpec(),
)
    kind in (:primal, :dual) || error("选择类型须为primal/dual")
    isfinite(clearing_objective) || error("原市场最优值必须有限")
    b = kind == :primal ? build_r5_market(c; optimizer) : build_r5_market_dual(c; optimizer)
    m = b.model
    original = objective_function(m)
    # R5-EX1/2：只在原最优面选择；norm不是额外资源成本，不进入市场支付。
    @constraint(m, original == clearing_objective)
    vars = all_variables(m)
    scale = kind == :primal ? spec.quantity_scale_MW : c.data["dt_h"]*spec.price_scale_USD_MWh
    h = fill(1.0/scale^2, length(vars))
    all(x->isfinite(x)&&x>0, h) || error("参考尺度导致二次权重上溢/下溢")
    @objective(m, Min, 0.5*sum(h[j]*vars[j]^2 for j in eachindex(vars)))
    (; model = m, base = b, variables = vars, h, original, kind, scale)
end

# 将选择QP的标量仿射行保存为h_j(x)=a_j'x+b_j<=0或=0。
# 数值验算只使用这些系数、原始MOI乘子与原值；不读取求解器残差。
function r5_execution_qp_system(b)
    ix = Dict(v => j for (j, v) in enumerate(b.variables))
    rows = Dict{String,Any}[]
    refs = all_constraints(b.model; include_variable_in_set_constraints = true)
    for (i, ref) in enumerate(refs)
        row = constraint_object(ref)
        s, f = row.set, row.func
        s isa Union{MOI.EqualTo,MOI.GreaterThan,MOI.LessThan} || error("选择QP只允许标量线性约束")
        f isa Union{VariableRef,AffExpr} || error("选择QP存在非仿射约束")
        sign = s isa MOI.GreaterThan ? -1.0 : 1.0
        rhs = s isa MOI.EqualTo ? s.value : s isa MOI.LessThan ? s.upper : s.lower
        a = zeros(length(ix))
        c0 = f isa VariableRef ? 0.0 : constant(f)
        if f isa VariableRef
            a[ix[f]] = sign
        else
            for (coefficient, v) in linear_terms(f)
                a[ix[v]] += sign*coefficient
            end
        end
        push!(
            rows,
            Dict(
                "id"=>"row/$i",
                "a"=>a,
                "constant"=>sign*(c0-rhs),
                "equality"=>s isa MOI.EqualTo,
                "moi_to_multiplier"=>-sign,
            ),
        )
    end
    Dict{String,Any}("names"=>name.(b.variables), "h"=>b.h, "rows"=>rows)
end

function r5_execution_qp_witness(b)
    dual_status(b.model) == MOI.FEASIBLE_POINT || return Dict{String,Any}()
    refs = all_constraints(b.model; include_variable_in_set_constraints = true)
    Dict{String,Any}(
        "system"=>r5_execution_qp_system(b),
        "x"=>value.(b.variables),
        "raw_duals"=>dual.(refs),
        "solver_objective"=>objective_value(b.model),
        "multiplier_source"=>"MOI_raw_selector_QP_duals_not_market_prices",
    )
end
