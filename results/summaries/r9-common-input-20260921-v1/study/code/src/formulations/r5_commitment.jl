const R5_COMMITMENT_MODEL_FILE=@__FILE__

function r5_commitment_rhs(id, row, c, x)
    a=split(id, '/')
    rt=c.data["realtime"]
    T=c.data["T"]
    if a[1]=="R5-D-delivery"
        return x["P_DA_MW"][parse(Int, a[3])]
    elseif a[1] in ("5-3-plus", "5-3-minus")
        t=parse(Int, a[3])
        request=rt["alpha_up"][t]*x["R_up_MW"][t]-rt["alpha_down"][t]*x["R_down_MW"][t]
        return a[1]=="5-3-plus" ? request : -request
    elseif a[1]=="5-4"
        return rt["delta"]*c.data["dt_h"]*sum(x["R_up_MW"][t]+x["R_down_MW"][t] for t in 1:T)
    end
    row.rhs
end

"""
    build_r5_commitment(case; optimizer=nothing)

构造r5_shared_commitment_checked_v1的全情景连续LP，不求解、不写文件。
三个日前变量族跨情景共享；设备、线性电网、固定流量热网和硬舒适逐情景保留。
复用已与原JuMP模型逐系数交叉验证的补救系数表；独立物理验证仍走原数值回放器。
按(5-5)至(5-8)累计日前净支出一次及概率加权补救费用，不包含价格反应或风险约束。
"""
function build_r5_commitment(c::R5CommitmentCase; optimizer = nothing)
    r5_commitment_assert_case(c)
    m=optimizer===nothing ? Model() : Model(optimizer)
    T=first(c.data["scenarios"])["case"]["T"]
    x=Dict(k=>[@variable(m, base_name="$k[$t]") for t in 1:T] for k in R5_COMMITMENT_KEYS)
    first_rows=Dict{String,Any}()
    first_system=r5_commitment_first_rows(c)
    for id in sort!(collect(keys(first_system)))
        row=first_system[id]
        expr=AffExpr(0.0)
        for (k, a) in row.coefficients
            name, t=split(k, '/')
            add_to_expression!(expr, a, x[name][parse(Int, t)])
        end
        first_rows[id]=row.sense==:ge ? @constraint(m, expr>=row.rhs) :
                       @constraint(m, expr<=row.rhs)
    end
    rows, vars, systems=Dict{String,Any}(), Dict{String,Any}(), Dict{String,Any}()
    total=r5_commitment_day_cost(c, x)
    for s in c.data["scenarios"]
        id=s["id"]
        template=R5DispatchCase(s["case"])
        sys=r5_dispatch_dual_system(template)
        systems[id]=sys
        vars[id]=Dict(k=>@variable(m, base_name="$id/$k") for k in sort!(collect(keys(sys.cost))))
        rows[id]=Dict{String,Any}()
        for k in sort!(collect(keys(sys.rows)))
            row=sys.rows[k]
            lhs=sum(a*vars[id][j] for (j, a) in row.coefficients; init = AffExpr(0.0))
            rhs=r5_commitment_rhs(k, row, template, x)
            rows[id][k]=row.sense==:eq ? @constraint(m, lhs==rhs) :
                        row.sense==:ge ? @constraint(m, lhs>=rhs) : @constraint(m, lhs<=rhs)
        end
        total+=s["probability"]*sum(sys.cost[k]*vars[id][k] for k in keys(sys.cost))
    end
    @objective(m, Min, total)
    types=r5_market_lp_types(m)
    (;
        model = m,
        first_stage = x,
        first_rows,
        rows,
        variables = vars,
        systems,
        model_type = "continuous_LP",
        model_types = types,
    )
end
