const R5_STRATEGIC_BENDERS_MODEL_FILE = @__FILE__

"""
    build_r5_strategic_benders_master(case; optimizer=nothing, spec=R5BendersSpec(),
                                      subproblems=[], critical=[], complementarity_pattern=nothing)

构造第5章连续报价与条件Benders主问题，不求解、不写文件。复用风险主问题的有效割和运输对偶，
加入完整市场KKT/SOS1，把日前费用替换为全时域净支付恒等式；三个成交量与补救共同承诺精确相等。
原(5-72)/(5-85)/(5-86)及项目R5-SB1。补救上图有输入推导的负下界，不设置任意市场乘子上界。
固定互补分支仅用于已声明分支域；原5-102的受限舒适域另行标注，两种限制均不冒充全域。
"""
function build_r5_strategic_benders_master(
    c::R5StrategicCase;
    optimizer = nothing,
    spec = R5BendersSpec(),
    subproblems = Dict{String,Any}[],
    critical = Int[],
    complementarity_pattern = nothing,
)
    r5_strategic_assert_case(c)
    rc = R5RiskCase(c.data["risk"])
    pattern = r5_strategic_benders_pattern(c, complementarity_pattern)
    b = build_r5_benders_master(rc; optimizer, spec, subproblems, critical)
    m = b.model
    if optimizer !== nothing &&
       pattern === nothing &&
       !MOI.supports_constraint(unsafe_backend(m), MOI.VectorOfVariables, MOI.SOS1{Float64})
        throw(
            MOI.UnsupportedConstraint{MOI.VectorOfVariables,MOI.SOS1{Float64}}(
                "策略分解要求原生SOS1；不得使用缺少有效乘子界的自动大M桥接",
            ),
        )
    end
    market = r5_strategic_market!(m, c; complementarity_pattern = pattern)
    for (key, v) in (("P_DA_MW", :P_IES), ("R_up_MW", :R_IES_up), ("R_down_MW", :R_IES_down))
        @constraint(
            m,
            [t=1:c.data["market"]["T"]],
            b.first_stage[key][t] == market.variables[v][1, t]
        )
    end
    terms = r5_market_payment_terms(
        R5MarketCase(c.data["market"]),
        market.variables,
        market.multipliers,
    )
    payment = sum(values(terms))
    # 风险输入已要求日前价格为零：这里只计一次实际市场净支付。
    @objective(m, Min, payment + b.duals["cost"].objective)
    types = String[]
    for (F, S) in list_of_constraint_types(m)
        scalar =
            F in (VariableRef, AffExpr) && S in
            (MOI.GreaterThan{Float64}, MOI.LessThan{Float64}, MOI.EqualTo{Float64}, MOI.ZeroOne)
        sos = F == Vector{VariableRef} && S == MOI.SOS1{Float64}
        scalar || sos || error("策略分解出现未声明约束类型：$F/$S")
        push!(types, string(F, " in ", S))
    end
    objective_function_type(m) == AffExpr || error("策略分解主目标须为仿射")
    merge(
        b,
        (;
            market,
            payment,
            payment_terms = terms,
            complementarity_pattern = pattern,
            bound_scope = r5_strategic_benders_scope(b.scope, pattern),
            model_type = pattern === nothing ? "linear_MPEC_SOS1_Benders_master" :
                         "fixed_complementarity_MILP_master",
            model_types = sort(types),
        ),
    )
end
