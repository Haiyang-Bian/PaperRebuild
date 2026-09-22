"""
    r9_risk_start_values(case, built, witness)

把已经独立核查的共同控制映射为原风险模型全部JuMP变量的完整初值。
包含共同承诺、每情景调度、舒适开关与两套运输对偶；不改变任何约束或目标。
返回按JuMP变量索引排列的数值，不调用求解器、不宣称初值改善或最优。
"""
function r9_risk_start_values(c::R5RiskCase, b, w)
    get(w, "has_candidate", false) && r9_common_identity(c)==w["common_identity"] ||
        error("初值来源不符")
    vars=all_variables(b.model)
    all(index(v).value==i for (i, v) in enumerate(vars)) ||
        error("当前映射要求连续未删除的JuMP索引")
    start=fill(NaN, length(vars))
    put(v, x) = (start[index(v).value]=Float64(x))
    for (key, vs) in b.base.first_stage, t in eachindex(vs)
        put(vs[t], w["first_stage"][key][t])
    end
    for entries in values(b.base.variables), (key, v) in entries
        name, j, t=split(key, '/')
        put(v, w["values"][name][parse(Int, j)][parse(Int, t)])
    end
    if b.pattern===nothing
        foreach(v->put(v, 0.0), b.z)
    else
        all(==(0), b.pattern) || error("共同硬舒适见证只用于全零固定分支或未固定分支")
    end
    q=[value(v->start[index(v).value], expr) for expr in b.q]
    all(==(first(q)), q) || error("当前初值的情景费用不恒定")
    for (label, dual) in b.duals
        put(dual.lambda, 0.0)
        foreach(v->put(v, label=="cost" ? first(q) : 0.0), dual.nu)
    end
    all(isfinite, start) || error("初值未覆盖全部变量")
    start
end

"""
    audit_r9_risk_start(built, values)

只读逐行计算原JuMP线性/整数模型初值残差、目标和变量覆盖；此检查不代替物理A1。
归一化按每行常数与项绝对值和，门槛1e-8；原数值、最大原始/归一化违反和约束类型保留。
"""
function audit_r9_risk_start(b, start)
    vars=all_variables(b.model)
    length(vars)==length(start) && all(isfinite, start) || error("初值维度/非有限数错误")
    val(v) = start[index(v).value]
    groups=Dict{String,Any}()
    for (F, S) in list_of_constraint_types(b.model)
        g=Dict{String,Any}("count"=>0, "max_raw"=>0.0, "max_normalized"=>0.0)
        for ref in all_constraints(b.model, F, S)
            obj=constraint_object(ref)
            a=value(val, obj.func)
            set=obj.set
            scale=obj.func isa VariableRef ? max(1.0, abs(a)) :
                  1.0+abs(obj.func.constant)+sum(
                abs(coef*val(v)) for (v, coef) in obj.func.terms;
                init = 0.0,
            )
            residual=if set isa MOI.EqualTo
                scale+=abs(set.value)
                abs(a-set.value)
            elseif set isa MOI.LessThan
                scale+=abs(set.upper)
                max(0.0, a-set.upper)
            elseif set isa MOI.GreaterThan
                scale+=abs(set.lower)
                max(0.0, set.lower-a)
            elseif set isa MOI.ZeroOne
                max(abs(a-round(a)), max(0.0, -a, a-1))
            else
                error("未支持的初值约束类型")
            end
            g["count"]+=1
            g["max_raw"]=max(g["max_raw"], residual)
            g["max_normalized"]=max(g["max_normalized"], residual/scale)
        end
        groups[string(F, " in ", S)]=g
    end
    Dict(
        "pass"=>all(g["max_normalized"]<=1e-8 for g in values(groups)),
        "groups"=>groups,
        "variables"=>length(start),
        "tolerance"=>1e-8,
        "objective"=>value(val, objective_function(b.model)),
        "physical_A1_substitute"=>false,
    )
end
