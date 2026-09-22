const R6_EVALUATION_MODEL_FILE=@__FILE__

"""
    build_r6_recourse(day, temperature_domain; stage=:hard, peak_cap=nothing, optimizer=nothing)

构建R6-E1/E4补救LP，不求解、不写文件。hard为原舒适域费用问题，physical为宽物理域费用问题；
诊断的peak仅最小化最大越界K，cost保持peak_cap后最小化费用。容量、交付和终端始终不变。
"""
function build_r6_recourse(
    c::R5DispatchCase,
    domain;
    stage = :hard,
    peak_cap = nothing,
    optimizer = nothing,
)
    stage in (:hard, :physical, :peak, :cost) || error("补救阶段错误")
    wide=r6_physical_day(c, domain)
    stage==:cost ?
    (peak_cap isa Real && isfinite(peak_cap) && peak_cap>=0 || error("费用阶段缺少有限越界上限")) :
    (peak_cap===nothing || error("仅费用阶段使用越界上限"))
    view=stage==:hard ? c : wide
    b=build_r5_dispatch(view; optimizer)
    m=b.model
    variables=Dict(
        "$k/$i/$t"=>vars[i, t] for (k, vars) in pairs(b.variables) for
        i in axes(vars, 1), t in axes(vars, 2)
    )
    rows=copy(b.rows)
    for (k, ref) in variables
        has_lower_bound(ref) && (rows[k*"/lower"]=LowerBoundRef(ref))
        has_upper_bound(ref) && (rows[k*"/upper"]=UpperBoundRef(ref))
    end
    if stage in (:peak, :cost)
        peak=@variable(m, lower_bound=0, base_name="comfort_peak_K")
        variables["peak"]=peak
        rows["peak/lower"]=LowerBoundRef(peak)
        for (j, z) in enumerate(c.data["buildings"]), t in 1:c.data["T"]
            # 一个最大越界量覆盖整日全部楼宇；保持K单位，不用巨大惩罚系数混合费用。
            temp=b.variables.τ_IN[j, t]
            rows["R6-E1/$j/$t/lower"]=@constraint(m, temp+peak>=z["T_min_K"])
            rows["R6-E1/$j/$t/upper"]=@constraint(m, temp-peak<=z["T_max_K"])
        end
        if stage==:peak
            @objective(m, Min, peak)
        else
            rows["peak/cap"]=@constraint(m, peak<=peak_cap)
        end
    end
    (; model = m, variables, rows, view, stage, peak_cap, model_types = r5_market_lp_types(m))
end
