const R5_BENDERS_MODEL_FILE=@__FILE__

"""
    build_r5_benders_subproblem(case, scenario, first_stage; branch=0, elastic=false,
                               optimizer=nothing, numerical_scale=1.0)

构造固定日前承诺和舒适分支的连续补救LP，不求解、不写文件。scenario为输入顺序的情景索引。
branch=0保持全部舒适，branch=1仅使用已声明室温物理域；设备、交付及末期关系不变。
elastic=true改为有界归一化关系诊断，原物理盒保持硬约束；其解不是可实施调度。
目标不含日前常数，成本使用输入币种；诊断为无量纲。参数依赖见R5-BD1，有限盒见R5-BD2。
numerical_scale仅改变u=scale*y的数值表示；variables返回原单位表达式，solver_variables为原始u。
"""
function build_r5_benders_subproblem(
    c::R5RiskCase,
    scenario::Integer,
    x;
    branch = 0,
    elastic = false,
    optimizer = nothing,
    numerical_scale = 1.0,
)
    sys=r5_benders_system(c, scenario, x, branch; elastic)
    scale=r5_benders_check_scale(numerical_scale)
    m=optimizer===nothing ? Model() : Model(optimizer)
    u=Dict(k=>@variable(m, base_name=k) for k in sort!(collect(keys(sys.cost))))
    y=Dict(k=>v/scale for (k, v) in u)
    rows=Dict{String,Any}()
    xf=r5_benders_flat(x)
    for id in sort!(collect(keys(sys.rows)))
        row=sys.rows[id]
        # u=scale*y，二次幂乘除保留二进制有效位；不改变原问题的物理量、边界或验收门槛。
        lhs=sum(a*u[k] for (k, a) in row.coefficients; init = AffExpr(0.0))
        rhs=scale*r5_benders_rhs_value(row, xf)
        rows[id]=row.sense==:eq ? @constraint(m, lhs==rhs) :
                 row.sense==:ge ? @constraint(m, lhs>=rhs) : @constraint(m, lhs<=rhs)
    end
    # 将所有物理界保留为可读取的约束；固定变量的上下界乘子均进入独立驻点检查。
    @objective(m, Min, sum(sys.cost[k]*y[k] for k in keys(sys.cost)))
    (;
        model = m,
        variables = y,
        solver_variables = u,
        numerical_scale = scale,
        rows,
        system = sys,
        model_type = "continuous_LP",
        model_types = r5_market_lp_types(m),
    )
end

"""
    build_r5_benders_master(case; optimizer=nothing, spec=R5BendersSpec(), subproblems=[], critical=[])

构造有限支持条件Benders主问题，不求解、不写文件。仅从通过独立KKT的子问题记录重建割。
日前承诺、舒适二元开关与两套运输对偶共同优化；每情景补救上图以输入推导的负费用下界初始化。
critical加入所选情景的完整物理可行性关系；paper_critical还固定外集z=0并标注受限策略域。
该主问题保留完整费用运输对偶，区别于原(5-85)仅使用一次最坏权重的写法；公式R5-BD7。
"""
function build_r5_benders_master(
    c::R5RiskCase;
    optimizer = nothing,
    spec = R5BendersSpec(),
    subproblems = Dict{String,Any}[],
    critical = Int[],
)
    r5_risk_assert_case(c)
    active=r5_benders_critical(c, spec, critical)
    cuts=[r5_benders_cut(c, r; arithmetic = spec.cut_arithmetic) for r in subproblems]
    ids=[r["run_id"] for r in subproblems]
    length(unique(ids))==length(ids)||error("主问题重复割来源")
    base=R5CommitmentCase(c.data["commitment"])
    sc=base.data["scenarios"]
    n=length(sc)
    T=first(sc)["case"]["T"]
    m=optimizer===nothing ? Model() : Model(optimizer)
    x=Dict(k=>[@variable(m, base_name="$k[$t]") for t in 1:T] for k in R5_COMMITMENT_KEYS)
    xf=Dict("$k/$t"=>x[k][t] for k in R5_COMMITMENT_KEYS for t in 1:T)
    for row in values(r5_commitment_first_rows(base))
        lhs=sum(a*xf[k] for (k, a) in row.coefficients; init = AffExpr(0.0))
        row.sense==:ge ? @constraint(m, lhs>=row.rhs) : @constraint(m, lhs<=row.rhs)
    end
    z=[@variable(m, binary=true, base_name="z[$s]") for s in 1:n]
    θ=[
        @variable(m, lower_bound=r5_benders_bounds(c, s).lower_cost, base_name="theta[$s]") for
        s in 1:n
    ]
    if spec.feasibility==:paper_critical
        for s in setdiff(1:n, active)
            @constraint(m, z[s]==0)
        end
    end
    for cut in cuts
        s=cut["scenario"]
        match=cut["branch"]==0 ? 1-z[s] : z[s]
        rhs=cut["constant"]+sum(a*xf[k] for (k, a) in cut["gradient"]; init = AffExpr(0.0))
        if cut["kind"]=="cost"
            @constraint(m, θ[s]>=rhs-cut["deactivation_M"]*(1-match))
        else
            @constraint(m, rhs<=cut["deactivation_M"]*(1-match))
        end
    end
    critical_variables=Dict{String,Any}()
    x0=Dict(k=>base.data["bounds"][k]["lower"] for k in R5_COMMITMENT_KEYS)
    for s in active
        sys=r5_benders_system(c, s, x0, 1)
        y=Dict(k=>@variable(m, base_name="critical/$s/$k") for k in sort!(collect(keys(sys.cost))))
        critical_variables[sc[s]["id"]]=y
        for row in values(sys.rows)
            lhs=sum(a*y[k] for (k, a) in row.coefficients; init = AffExpr(0.0))
            rhs=row.rhs+sum(a*xf[k] for (k, a) in row.parameters; init = AffExpr(0.0))
            row.sense==:eq ? @constraint(m, lhs==rhs) :
            row.sense==:ge ? @constraint(m, lhs>=rhs) : @constraint(m, lhs<=rhs)
        end
        # 插入的是完整可行性关系。费用仍由条件割界定，不能偷用直接模型目标。
        for (j, b) in enumerate(sc[s]["case"]["buildings"]), t in 1:T
            domain=c.data["temperature_domain"][b["id"]]
            τ=y["τ_IN/$j/$t"]
            @constraint(m, τ>=b["T_min_K"]-(b["T_min_K"]-domain["lower_K"])*z[s])
            @constraint(m, τ<=b["T_max_K"]+(domain["upper_K"]-b["T_max_K"])*z[s])
        end
    end
    D=r5_market_array(c.data["ambiguity"]["distance"])
    rho=c.data["ambiguity"]["radius"]
    p=[s["probability"] for s in sc]
    duals=Dict{String,Any}()
    for (label, score) in (("cost", θ), ("risk", z))
        λ=@variable(m, lower_bound=0, base_name="lambda_$label")
        ν=[@variable(m, base_name="nu_$label[$j]") for j in 1:n]
        @constraint(m, [i=1:n, j=1:n], λ*D[i, j]+ν[j]>=score[i])
        duals[label]=(lambda = λ, nu = ν, objective = rho*λ+sum(p .* ν))
    end
    @constraint(m, duals["risk"].objective<=c.data["epsilon"])
    @objective(m, Min, r5_commitment_day_cost(base, x)+duals["cost"].objective)
    types=String[]
    for (F, S) in list_of_constraint_types(m)
        F in (VariableRef, AffExpr)&&S in (
            MOI.GreaterThan{Float64},
            MOI.LessThan{Float64},
            MOI.EqualTo{Float64},
            MOI.ZeroOne,
        )||error("Benders主问题不是声明的MILP")
        push!(types, string(F, " in ", S))
    end
    (;
        model = m,
        first_stage = x,
        z,
        theta = θ,
        duals,
        critical_variables,
        critical = active,
        cuts,
        cut_source_ids = ids,
        scope = r5_benders_scope(c, spec, active),
        model_type = "MILP",
        model_types = sort(types),
    )
end
