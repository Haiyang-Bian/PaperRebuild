const R7_ADVERSARY_CORE_FILE = @__FILE__

"""
    R7RecourseLP

固定灾前状态和恢复拓扑的连续LP行台账：`A*r ≤ b + D*γ`，`min c'r + c0`。
`r`作为自由变量；原变量上下界、固定值和等式均逐行保留。故障参数单列，单位沿用恢复模型。
用于原(6-105)—(6-111)的采用版对偶，不能把原文非负乘子符号直接套入本规范形。
"""
struct R7RecourseLP
    data::Dict{String,Any}
    sha256::String
end

function r7_affine_terms(f)
    f isa VariableRef && return (0.0, [(1.0, f)])
    f isa AffExpr && return (constant(f), collect(linear_terms(f)))
    f isa Real && return (Float64(f), Tuple{Float64,VariableRef}[])
    error("对偶抽取仅支持标量仿射表达式")
end

function r7_linear_recourse(model, parameters; labels = Dict{Any,String}(), metadata = Dict())
    objective_sense(model)==MOI.MIN_SENSE || error("恢复LP须为最小化")
    length(unique(parameters))==length(parameters) || error("故障参数重复")
    pmap=Dict(v=>i for (i, v) in enumerate(parameters))
    vars=filter(v->!haskey(pmap, v), all_variables(model))
    vmap=Dict(v=>i for (i, v) in enumerate(vars))
    all(v->owner_model(v)===model, parameters) || error("参数不属于本模型")
    rows=Dict{String,Any}[]
    function appendrow(f, sign, rhs, label)
        f0, terms=r7_affine_terms(f)
        a=Dict{Int,Float64}()
        d=Dict{Int,Float64}()
        for (coef, v) in terms
            if haskey(pmap, v)
                j=pmap[v]
                d[j]=get(d, j, 0.0)-sign*coef
            else
                j=vmap[v]
                a[j]=get(a, j, 0.0)+sign*coef
            end
        end
        ai=sort([j for (j, x) in a if x!=0])
        di=sort([j for (j, x) in d if x!=0])
        b=sign*(rhs-f0)
        all(isfinite, vcat(b, collect(values(a)), collect(values(d)))) || error("非有限LP系数")
        push!(
            rows,
            Dict(
                "columns"=>ai,
                "coefficients"=>[a[j] for j in ai],
                "fault_columns"=>di,
                "fault_coefficients"=>[d[j] for j in di],
                "rhs"=>b,
                "source"=>label,
            ),
        )
    end
    # 类型的show会受Main是否using JuMP影响；身份标签必须独立于调用者的导入环境。
    type_key(F, S) = (F==AffExpr ? "AffExpr" : "VariableRef", String(nameof(S)))
    for (F, S) in sort(list_of_constraint_types(model); by = x->type_key(x...))
        F in (VariableRef, AffExpr) || error("恢复LP含非仿射行")
        for con in all_constraints(model, F, S)
            o=constraint_object(con)
            s=o.set
            label=get(
                labels,
                con,
                string(
                    type_key(F, S)[1],
                    "/MathOptInterface.",
                    nameof(S),
                    "{Float64}/",
                    index(con).value,
                ),
            )
            if s isa MOI.LessThan
                appendrow(o.func, 1.0, s.upper, label*":upper")
            elseif s isa MOI.GreaterThan
                appendrow(o.func, -1.0, s.lower, label*":lower")
            elseif s isa MOI.EqualTo
                appendrow(o.func, 1.0, s.value, label*":equal_positive")
                appendrow(o.func, -1.0, s.value, label*":equal_negative")
            elseif s isa MOI.Interval
                appendrow(o.func, 1.0, s.upper, label*":upper")
                appendrow(o.func, -1.0, s.lower, label*":lower")
            else
                error("恢复LP含整数、锥或未支持约束：$S")
            end
        end
    end
    c0, terms=r7_affine_terms(objective_function(model))
    c=zeros(length(vars))
    for (coef, v) in terms
        haskey(pmap, v) && coef!=0 && error("故障不得直接进入本批失供目标")
        haskey(vmap, v) && (c[vmap[v]]+=coef)
    end
    # R7-I2：失供目标非负，每个有费用分量都具有显式零下界，因此存在共同可行对偶。
    c0==0 && all(>=(0), c) || error("本批共同对偶证书仅支持非负失供目标")
    seed=zeros(length(rows))
    for j in findall(>(0), c)
        i=findfirst(
            row->row["columns"]==[j] &&
                 row["coefficients"]==[-1.0] &&
                 isempty(row["fault_columns"]) &&
                 row["rhs"]==0,
            rows,
        )
        i===nothing && error("费用变量缺少显式零下界，不能保证共同可行对偶")
        seed[i]=-c[j]
    end
    d=Dict{String,Any}(
        "schema"=>"r7-recourse-lp-v1",
        "rows"=>rows,
        "variable_names"=>name.(vars),
        "fault_names"=>name.(parameters),
        "cost"=>c,
        "constant"=>c0,
        "dual_seed"=>seed,
        "metadata"=>Dict{String,Any}(metadata),
    )
    R7RecourseLP(d, r7_digest(d))
end

"""
    r7_recovery_lp(case, topology)

从当前恢复模型抽取固定森林的全部LP行与故障系数，不求解。拓扑是否适用于某个故障
由故障参数行决定，不能用零故障的动作预算提前排除它；保留不适用模式的不可行证据。
返回可哈希的规范行、中文公式标签及共同可行对偶，采用式R7-I1/I2。
"""
function r7_recovery_lp(c::R7RecoveryCase, z)
    r7_recovery_assert(c)
    r7_exclusive_battery(c.data) && error("互斥电池未固定，不能抽取为连续LP对偶")
    b=build_r7_recovery(c, zeros(Int, length(z)); fixed_z = z, fault_variables = true)
    labels=Dict{Any,String}(con=>id for (id, cs) in b.constraints for con in cs)
    r7_linear_recourse(
        b.model,
        b.fault_parameters;
        labels,
        metadata = Dict("case_sha256"=>c.sha256, "topology"=>Int.(z)),
    )
end

function r7_lp_assert(lp)
    r7_digest(lp.data)==lp.sha256 || error("恢复LP在抽取后改变")
end

"""
    r7_recovery_loss_cap(case)

由全部电热负荷、削减比例、时间步和场景概率推导任一可行恢复的失供上界B（MWh）。
对手搜索的认证截断值C=B+1 MWh；C不限制对偶乘子，也不是不可行故障的有限损失。
只有对手上界严格低于C时，才可把它当作原最坏失供的有限上界。
"""
function r7_recovery_loss_cap(c::R7RecoveryCase)
    r7_recovery_assert(c)
    d=c.data
    B=d["dt_h"]*sum(d["probabilities"])*sum(
        net["load_MW"][n][t]*net["shed_fraction_max"][n] for net in (d["electric"], d["heat"]) for
        n in 1:net["nodes"] for t in 1:d["periods"]
    )
    if r7_critical_service(d)
        e=d["electric"]
        B=d["dt_h"]*sum(d["probabilities"])*sum(
            min(
                d["load_service"]["critical_load_MW"][n][t],
                e["load_MW"][n][t]*e["shed_fraction_max"][n],
            ) for n in 1:e["nodes"], t in 1:d["periods"]
        )
    end
    isfinite(B) && B>=0 && B+1.0>B || error("失供界非有限或截断间隔无法表示")
    (; feasible_upper_MWh = Float64(B), cap_MWh = Float64(B+1.0), margin_MWh = 1.0)
end
