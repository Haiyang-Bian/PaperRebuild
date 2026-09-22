const R5_RISK_MODEL_FILE=@__FILE__

"""
    build_r5_risk(case; optimizer=nothing, pattern=nothing)

构造有限支持DRO/DRJCC直接MILP，不求解、不写文件；pattern固定全部情景舒适开关时为LP。
原(5-66)/(5-68)的运输对偶分别约束最坏费用和最坏联合事件，两套乘子互不共享。
每情景一个z覆盖全部室温行；大M由显式物理域与舒适界的差推导，原硬设备/终端约束保留。
共同日前变量只有一份；不混入市场价格反应或Benders割。
"""
function build_r5_risk(c::R5RiskCase; optimizer = nothing, pattern = nothing)
    r5_risk_assert_case(c)
    fixed=r5_risk_pattern(c, pattern)
    physical=r5_risk_physical_case(c)
    base=build_r5_commitment(physical; optimizer)
    m=base.model
    sc=c.data["commitment"]["scenarios"]
    n=length(sc)
    D=r5_market_array(c.data["ambiguity"]["distance"])
    p=[s["probability"] for s in sc]
    rho=c.data["ambiguity"]["radius"]
    z=fixed===nothing ? [@variable(m, binary=true, base_name="z[$s]") for s in 1:n] : fixed
    comfort_rows=Dict{String,Any}()
    for (s, item) in enumerate(sc),
        (j, b) in enumerate(item["case"]["buildings"]),
        t in 1:item["case"]["T"]

        domain=c.data["temperature_domain"][b["id"]]
        τ=base.variables[item["id"]]["τ_IN/$j/$t"]
        # z=0施加全部舒适界；z=1只退到明确的物理域，M不根据求解结果调大。
        comfort_rows["$(item["id"])/$j/$t/lower"]=@constraint(
            m,
            τ>=b["T_min_K"]-(b["T_min_K"]-domain["lower_K"])*z[s]
        )
        comfort_rows["$(item["id"])/$j/$t/upper"]=@constraint(
            m,
            τ<=b["T_max_K"]+(domain["upper_K"]-b["T_max_K"])*z[s]
        )
    end
    q=[
        sum(
            base.systems[s["id"]].cost[k]*base.variables[s["id"]][k] for
            k in keys(base.systems[s["id"]].cost)
        ) for s in sc
    ]
    duals=Dict{String,Any}()
    for (label, score) in (("cost", q), ("risk", z))
        λ=@variable(m, lower_bound=0, base_name="lambda_$label")
        ν=[@variable(m, base_name="nu_$label[$j]") for j in 1:n]
        @constraint(m, [i=1:n, j=1:n], λ*D[i, j]+ν[j]>=score[i])
        obj=rho*λ+sum(p .* ν)
        duals[label]=(lambda = λ, nu = ν, objective = obj)
    end
    @constraint(m, duals["risk"].objective<=c.data["epsilon"])
    @objective(m, Min, r5_commitment_day_cost(physical, base.first_stage)+duals["cost"].objective)
    types=String[]
    for (F, S) in list_of_constraint_types(m)
        F in (VariableRef, AffExpr)&&S in (
            MOI.GreaterThan{Float64},
            MOI.LessThan{Float64},
            MOI.EqualTo{Float64},
            MOI.ZeroOne,
        )||error("风险模型存在未声明约束类型：$F/$S")
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
        pattern = fixed,
        model_type = fixed===nothing ? "MILP" : "continuous_LP",
        model_types = sort(types),
    )
end

function r5_transport_build(p, D, q, rho; optimizer, primal)
    m=Model(optimizer)
    n=length(p)
    if primal
        @variable(m, Π[1:n, 1:n]>=0)
        @constraint(m, [j=1:n], sum(Π[i, j] for i in 1:n)==p[j])
        @constraint(m, sum(D[i, j]*Π[i, j] for i in 1:n, j in 1:n)<=rho)
        @objective(m, Max, sum(q[i]*Π[i, j] for i in 1:n, j in 1:n))
        return (; model = m, Π)
    end
    @variable(m, λ>=0)
    @variable(m, ν[1:n])
    @constraint(m, [i=1:n, j=1:n], λ*D[i, j]+ν[j]>=q[i])
    @objective(m, Min, rho*λ+sum(p .* ν))
    (; model = m, λ, ν)
end
