const R5_BENDERS_MODEL_FILE=@__FILE__

"""
    build_r5_benders_subproblem(case, scenario, first_stage; branch=0, elastic=false, optimizer=nothing)

构造固定日前承诺和舒适分支的连续补救LP，不求解、不写文件。scenario为输入顺序的情景索引。
branch=0保持全部舒适，branch=1仅使用已声明室温物理域；设备、交付及末期关系不变。
elastic=true改为有界归一化关系诊断，原物理盒保持硬约束；其解不是可实施调度。
目标不含日前常数，成本单位USD；诊断为无量纲。参数依赖见R5-BD1，有限盒见R5-BD2。
"""
function build_r5_benders_subproblem(
    c::R5RiskCase,
    scenario::Integer,
    x;
    branch = 0,
    elastic = false,
    optimizer = nothing,
)
    sys=r5_benders_system(c, scenario, x, branch; elastic)
    m=optimizer===nothing ? Model() : Model(optimizer)
    y=Dict(k=>@variable(m, base_name=k) for k in sort!(collect(keys(sys.cost))))
    rows=Dict{String,Any}()
    xf=r5_benders_flat(x)
    for id in sort!(collect(keys(sys.rows)))
        row=sys.rows[id]
        lhs=sum(a*y[k] for (k, a) in row.coefficients; init = AffExpr(0.0))
        rhs=r5_benders_rhs_value(row, xf)
        rows[id]=row.sense==:eq ? @constraint(m, lhs==rhs) :
                 row.sense==:ge ? @constraint(m, lhs>=rhs) : @constraint(m, lhs<=rhs)
    end
    # 将所有物理界保留为可读取的约束；固定变量的上下界乘子均进入独立驻点检查。
    @objective(m, Min, sum(sys.cost[k]*y[k] for k in keys(sys.cost)))
    (;
        model = m,
        variables = y,
        rows,
        system = sys,
        model_type = "continuous_LP",
        model_types = r5_market_lp_types(m),
    )
end
