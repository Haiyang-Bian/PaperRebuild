const R9_COMPACT_MODEL_FILE=@__FILE__

# 只转换系数表显式声明的变量界，拒绝把一般单项物理关系误当作变量界。
function r9_compact_bound!(v, row)
    row.bound &&
    length(row.coefficients)==1 &&
    only(values(row.coefficients))==1.0 &&
    isfinite(row.rhs) || error("原生边界转换要求已声明的单个单位系数与有限右端")
    if row.sense==:ge
        has_lower_bound(v) && error("重复下界")
        set_lower_bound(v, row.rhs)
        return LowerBoundRef(v)
    elseif row.sense==:le
        has_upper_bound(v) && error("重复上界")
        set_upper_bound(v, row.rhs)
        return UpperBoundRef(v)
    end
    error("已声明边界的方向必须为ge或le")
end

function r9_compact_affine(coefficients, variables)
    expr=AffExpr(0.0)
    for (key, a) in coefficients
        # 精确去零，不按容差删除小系数，不改变计算单位或有限边界。
        iszero(a) || add_to_expression!(expr, a, variables[key])
    end
    expr
end

"""
    build_r9_compact_risk(case; optimizer=nothing, pattern=nothing)

构造与原有限支持风险模型严格等价的r9_compact_v1表示，不求解、不写文件。
原系数表声明的上下界改为原生变量界；只删精确零系数；每情景费用用自由辅助变量和精确等式定义。
共同承诺、设备/电热网、舒适开关、两套运输对偶和风险界不变。
返回原行ID到实际约束的映射及费用定义，以便消元后逐系数核对；不据模型更紧凑宣称加速或最优。
"""
function build_r9_compact_risk(c::R5RiskCase; optimizer = nothing, pattern = nothing)
    r5_risk_assert_case(c)
    fixed=r5_risk_pattern(c, pattern)
    physical=r5_risk_physical_case(c)
    m=optimizer===nothing ? Model() : Model(optimizer)
    sc=c.data["commitment"]["scenarios"]
    T=first(sc)["case"]["T"]
    x=Dict(k=>[@variable(m, base_name="$k[$t]") for t in 1:T] for k in R5_COMMITMENT_KEYS)
    first_rows=Dict{String,Any}()
    first_system=r5_commitment_first_rows(physical)
    for id in sort!(collect(keys(first_system)))
        row=first_system[id]
        expr=AffExpr(0.0)
        for (k, a) in row.coefficients
            name, t=split(k, '/')
            iszero(a) || add_to_expression!(expr, a, x[name][parse(Int, t)])
        end
        first_rows[id]=row.sense==:ge ? @constraint(m, expr>=row.rhs) :
                       @constraint(m, expr<=row.rhs)
    end
    rows, vars, systems=Dict{String,Any}(), Dict{String,Any}(), Dict{String,Any}()
    for s in physical.data["scenarios"]
        id=s["id"]
        template=R5DispatchCase(s["case"])
        sys=r5_dispatch_dual_system(template)
        systems[id]=sys
        vars[id]=Dict(k=>@variable(m, base_name="$id/$k") for k in sort!(collect(keys(sys.cost))))
        rows[id]=Dict{String,Any}()
        for k in sort!(collect(keys(sys.rows)))
            row=sys.rows[k]
            if row.bound
                length(row.coefficients)==1 || error("变量界不能含多个变量")
                v=vars[id][only(keys(row.coefficients))]
                rows[id][k]=r9_compact_bound!(v, row)
            else
                lhs=r9_compact_affine(row.coefficients, vars[id])
                rhs=r5_commitment_rhs(k, row, template, x)
                rows[id][k]=row.sense==:eq ? @constraint(m, lhs==rhs) :
                            row.sense==:ge ? @constraint(m, lhs>=rhs) :
                            row.sense==:le ? @constraint(m, lhs<=rhs) : error("未知物理行方向")
            end
        end
    end
    base=(;
        model = m,
        first_stage = x,
        first_rows,
        rows,
        variables = vars,
        systems,
        model_type = "continuous_LP",
        model_types = r5_market_lp_types(m),
    )
    n=length(sc)
    z=fixed===nothing ? [@variable(m, binary=true, base_name="z[$s]") for s in 1:n] : fixed
    comfort_rows=Dict{String,Any}()
    for (s, item) in enumerate(sc),
        (j, b) in enumerate(item["case"]["buildings"]),
        t in 1:item["case"]["T"]

        domain=c.data["temperature_domain"][b["id"]]
        τ=vars[item["id"]]["τ_IN/$j/$t"]
        comfort_rows["$(item["id"])/$j/$t/lower"]=@constraint(
            m,
            τ>=b["T_min_K"]-(b["T_min_K"]-domain["lower_K"])*z[s]
        )
        comfort_rows["$(item["id"])/$j/$t/upper"]=@constraint(
            m,
            τ<=b["T_max_K"]+(domain["upper_K"]-b["T_max_K"])*z[s]
        )
    end
    q_expr=[r9_compact_affine(systems[s["id"]].cost, vars[s["id"]]) for s in sc]
    q=[@variable(m, base_name="q_cost[$s]") for s in 1:n]
    # 等式消去q后恢复原费用表达式；不能只约束一个方向或另外添加人为费用界。
    q_rows=[@constraint(m, q[i]==q_expr[i]) for i in 1:n]
    D=r5_market_array(c.data["ambiguity"]["distance"])
    p=[s["probability"] for s in sc]
    rho=c.data["ambiguity"]["radius"]
    duals=Dict{String,Any}()
    transport_rows=Dict{String,Any}()
    for (label, score) in (("cost", q), ("risk", z))
        λ=@variable(m, lower_bound=0, base_name="lambda_$label")
        ν=[@variable(m, base_name="nu_$label[$j]") for j in 1:n]
        transport_rows[label]=@constraint(m, [i=1:n, j=1:n], λ*D[i, j]+ν[j]>=score[i])
        obj=rho*λ+sum(p .* ν)
        duals[label]=(lambda = λ, nu = ν, objective = obj)
    end
    @constraint(m, duals["risk"].objective<=c.data["epsilon"])
    @objective(m, Min, r5_commitment_day_cost(physical, x)+duals["cost"].objective)
    types=String[]
    for (F, S) in list_of_constraint_types(m)
        F in (VariableRef, AffExpr) &&
        S in (MOI.GreaterThan{Float64}, MOI.LessThan{Float64}, MOI.EqualTo{Float64}, MOI.ZeroOne) ||
            error("紧凑风险模型存在未声明约束类型：$F/$S")
        push!(types, string(F, " in ", S))
    end
    (;
        base,
        model = m,
        physical,
        z,
        q,
        duals,
        comfort_rows,
        transport_rows,
        cost_alias = (variables = q, expressions = q_expr, rows = q_rows),
        pattern = fixed,
        model_type = fixed===nothing ? "MILP" : "continuous_LP",
        model_types = sort(types),
        representation = "r9_compact_v1",
    )
end
