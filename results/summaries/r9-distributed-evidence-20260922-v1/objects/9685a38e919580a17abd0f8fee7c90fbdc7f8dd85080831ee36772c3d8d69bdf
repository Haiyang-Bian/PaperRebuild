const R5_DISPATCH_DUAL_MODEL_FILE=@__FILE__

"""
    build_r5_dispatch_dual(case; optimizer=nothing)

由独立物理系数表构造完整补救LP对偶，不读取/复制原JuMP模型，不求解、不写文件。
MOI方向为>=行乘子非负、<=行非正、等式自由；所有变量上下界显式列入对偶。
最大化固定日前费用与b'y，约束A'y=c；用于与原问题交叉检查，非策略报价或Benders实现。
"""
function build_r5_dispatch_dual(c::R5DispatchCase; optimizer = nothing)
    sys=r5_dispatch_dual_system(c)
    m=optimizer===nothing ? Model() : Model(optimizer)
    ids=sort!(collect(keys(sys.rows)))
    @variable(m, y[ids])
    for k in ids
        sense=sys.rows[k].sense
        sense==:ge&&set_lower_bound(y[k], 0.0)
        sense==:le&&set_upper_bound(y[k], 0.0)
    end
    for k in sort!(collect(keys(sys.cost)))
        @constraint(m, sum(get(sys.rows[i].coefficients, k, 0.0)*y[i] for i in ids)==sys.cost[k])
    end
    @objective(m, Max, sys.constant+sum(sys.rows[k].rhs*y[k] for k in ids))
    (; model = m, multipliers = y, system = sys, model_types = r5_market_lp_types(m))
end
