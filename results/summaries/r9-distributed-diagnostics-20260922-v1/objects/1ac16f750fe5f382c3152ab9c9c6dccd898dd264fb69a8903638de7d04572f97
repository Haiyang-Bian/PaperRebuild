const R5_STRATEGIC_MODEL_FILE = @__FILE__

# 仅把已经核查的市场LP行嵌入已有风险模型；旧市场/风险构建接口和默认行为不变。
function r5_strategic_market!(m, c; complementarity_pattern = nothing)
    original = build_r5_market(R5MarketCase(c.data["market"]))
    T = c.data["market"]["T"]
    bids = Dict{String,Any}()
    for k in R5_STRATEGIC_BIDS
        b = c.data["bid_bounds"][k]
        bids[k] = [
            @variable(
                m,
                lower_bound=b["lower"][t],
                upper_bound=b["upper"][t],
                base_name="bid/$k/$t"
            ) for t in 1:T
        ]
    end
    vm = Dict{VariableRef,VariableRef}()
    vars = Dict{Symbol,Any}()
    for (key, matrix) in Base.pairs(original.variables)
        vars[key] = map(matrix) do old
            v = @variable(m, lower_bound=0, base_name="market/$(name(old))")
            vm[old] = v
        end
    end
    obj = objective_function(original.model)
    gradient = Dict(v=>AffExpr(coefficient(obj, old)) for (old, v) in vm)
    dt = c.data["market"]["dt_h"]
    for (key, bid, sign) in
        ((:P_IES, "energy_bid", -1), (:R_IES_up, "up_bid", 1), (:R_IES_down, "down_bid", 1))
        for t in 1:T
            gradient[vars[key][1, t]] = sign*dt*bids[bid][t] + 0.0
        end
    end
    pairs = Dict{String,Any}()
    function complementary(id, multiplier, slack)
        pairs[id] = (multiplier = multiplier, slack = slack)
        if complementarity_pattern === nothing
            # R5-ST2：SOS1等价于两个非负量至多一个非零，不假定任意乘子大M。
            @constraint(m, [multiplier, slack] in MOI.SOS1([1.0, 2.0]))
        else
            haskey(complementarity_pattern, id) || error("互补分支缺少$id")
            bit = complementarity_pattern[id]
            bit in (0, 1) || error("互补分支须为0/1")
            @constraint(m, (bit == 0 ? multiplier : slack) == 0)
        end
    end
    multipliers = Dict{Symbol,Any}()
    for key in sort!(collect(keys(original.rows)); by = string)
        oldrows = original.rows[key]
        arr = Array{VariableRef}(undef, size(oldrows))
        for ix in CartesianIndices(oldrows)
            id = string(key)*"/"*join(Tuple(ix), "/")
            row = constraint_object(oldrows[ix])
            f, set = row.func, row.set
            sign = set isa MOI.GreaterThan ? -1.0 : 1.0
            rhs = set isa MOI.GreaterThan ? set.lower : set isa MOI.LessThan ? set.upper : set.value
            h = AffExpr(sign*(constant(f)-rhs))
            for (a, old) in linear_terms(f)
                add_to_expression!(h, sign*a, vm[old])
            end
            μ = @variable(m, base_name="market_multiplier/$id")
            arr[ix] = μ
            if set isa MOI.EqualTo
                @constraint(m, h == 0)
            else
                set_lower_bound(μ, 0.0)
                slack = @variable(m, lower_bound=0, base_name="market_slack/$id")
                @constraint(m, slack == -h)
                complementary(id, μ, slack)
            end
            for (a, old) in linear_terms(f)
                add_to_expression!(gradient[vm[old]], sign*a, μ)
            end
        end
        multipliers[key] = arr
    end
    lower = Dict{Symbol,Any}()
    for key in sort!(collect(keys(vars)); by = string)
        matrix = vars[key]
        arr = Array{VariableRef}(undef, size(matrix))
        for ix in CartesianIndices(matrix)
            id = "lower/"*string(key)*"/"*join(Tuple(ix), "/")
            δ = @variable(m, lower_bound=0, base_name="market_multiplier/$id")
            arr[ix] = δ
            # R5-ST1：非负原变量对应约化费用，完整驻点包括其下界乘子。
            @constraint(m, gradient[matrix[ix]] - δ == 0)
            complementary(id, δ, matrix[ix])
        end
        lower[key] = arr
    end
    if complementarity_pattern !== nothing
        Set(keys(complementarity_pattern)) == Set(keys(pairs)) || error("互补分支含多余条目")
    end
    (; bids, variables = vars, multipliers, lower, pairs)
end

"""
    build_r5_strategic(case; optimizer=nothing, risk_pattern=nothing,
                       complementarity_pattern=nothing)

构建单IES乐观连续报价MPEC与有限支持风险补救，不求解、不写文件。
原(5-32)/(5-33)对应报价界与成交桥接；下层LP的原始可行、驻点、互补共同保证市场最优。
互补采用SOS1；可显式固定全部互补分支供开放LP交叉验算，固定分支的界不代表全域界。
目标是R5-SP3净支付加独立最坏补救费用；市场对偶为上层选择的变量，不冒充求解器原始乘子。
"""
function build_r5_strategic(
    c::R5StrategicCase;
    optimizer = nothing,
    risk_pattern = nothing,
    complementarity_pattern = nothing,
)
    r5_strategic_assert_case(c)
    risk = build_r5_risk(R5RiskCase(c.data["risk"]); optimizer, pattern = risk_pattern)
    m = risk.model
    if optimizer !== nothing &&
       complementarity_pattern === nothing &&
       !MOI.supports_constraint(unsafe_backend(m), MOI.VectorOfVariables, MOI.SOS1{Float64})
        throw(
            MOI.UnsupportedConstraint{MOI.VectorOfVariables,MOI.SOS1{Float64}}(
                "策略模型要求原生SOS1；不允许依靠缺少界的自动大M桥接",
            ),
        )
    end
    market = r5_strategic_market!(m, c; complementarity_pattern)
    for (key, v) in (("P_DA_MW", :P_IES), ("R_up_MW", :R_IES_up), ("R_down_MW", :R_IES_down))
        @constraint(
            m,
            [t=1:c.data["market"]["T"]],
            risk.base.first_stage[key][t] == market.variables[v][1, t]
        )
    end
    terms = r5_market_payment_terms(
        R5MarketCase(c.data["market"]),
        market.variables,
        market.multipliers,
    )
    payment = sum(values(terms))
    @objective(m, Min, payment+risk.duals["cost"].objective)
    types = String[]
    for (F, S) in list_of_constraint_types(m)
        scalar =
            F in (VariableRef, AffExpr) && S in
            (MOI.GreaterThan{Float64}, MOI.LessThan{Float64}, MOI.EqualTo{Float64}, MOI.ZeroOne)
        sos = F == Vector{VariableRef} && S == MOI.SOS1{Float64}
        scalar || sos || error("策略模型出现未声明类型：$F/$S")
        push!(types, string(F, " in ", S))
    end
    objective_function_type(m) == AffExpr || error("策略上层目标必须为仿射")
    (;
        model = m,
        risk,
        market,
        payment,
        payment_terms = terms,
        risk_pattern = r5_risk_pattern(R5RiskCase(c.data["risk"]), risk_pattern),
        complementarity_pattern,
        model_type = complementarity_pattern === nothing ? "linear_MPEC_SOS1_with_risk_branches" :
                     risk_pattern === nothing ? "fixed_complementarity_MILP" : "fixed_branch_LP",
        model_types = sort(types),
    )
end
