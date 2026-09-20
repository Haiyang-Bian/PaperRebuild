const R7_ADVERSARY_MODEL_FILE = @__FILE__

function r7_add_recourse_dual!(model, lp; prefix = "dual")
    r7_lp_assert(lp)
    d=lp.data
    lambda=[
        @variable(model, upper_bound=0, base_name="$(prefix)_lambda_$i") for
        i in eachindex(d["rows"])
    ]
    cols=[AffExpr(0.0) for _ in d["cost"]]
    for (i, row) in enumerate(d["rows"]), (j, a) in zip(row["columns"], row["coefficients"])
        add_to_expression!(cols[j], a, lambda[i])
    end
    stationarity=[@constraint(model, cols[j]==d["cost"][j]) for j in eachindex(cols)]
    (; lambda, stationarity)
end

"""
    build_r7_recourse_dual(lp, fault; optimizer=nothing)

构建固定故障与固定恢复拓扑的LP对偶：`λ≤0, A'λ=c`，最大化`(b+Dγ)'λ`。
不求解、不写文件；变量界已在规范行中，不额外假定恢复变量非负。
不可行恢复可能导致该对偶无界，不能将其当作对偶符号错误或零失供。
"""
function build_r7_recourse_dual(lp::R7RecourseLP, gamma; optimizer = nothing)
    r7_lp_assert(lp)
    length(gamma)==length(lp.data["fault_names"]) && all(x->x in (0, 1), gamma) ||
        error("故障形状错误")
    model=optimizer===nothing ? Model() : Model(optimizer)
    block=r7_add_recourse_dual!(model, lp)
    rows=lp.data["rows"]
    rhs=[
        row["rhs"]+sum(
            (a*gamma[j] for (j, a) in zip(row["fault_columns"], row["fault_coefficients"]));
            init = 0.0,
        ) for row in rows
    ]
    @objective(model, Max, lp.data["constant"]+sum(rhs .* block.lambda))
    (; model, lambda = block.lambda, lp, fault = Int.(gamma))
end

"""
    build_r7_adversary(case, topologies; optimizer=nothing)

构建固定灾前状态、有限恢复拓扑池的最大失供对手，采用式R7-I3/I4。
每个模式使用实际LP对偶；故障二值量与乘子乘积由两个原生指示等式精确表达，
禁止自动桥接到项目未知的乘子大M。求解器必须支持这些原生约束。
目标截断C只区分有限失供与缺少恢复模式；饱和于C不代表原问题有限安全上界。
不求解、不写文件；空拓扑池是值为C的初始松弛。
"""
function build_r7_adversary(c::R7RecoveryCase, topologies; optimizer = nothing)
    r7_recovery_assert(c)
    lines=c.data["electric"]["lines"]
    L=length(lines)
    zs=[Int.(z) for z in topologies]
    length(unique(zs))==length(zs) || error("恢复拓扑池重复")
    lps=[r7_recovery_lp(c, z) for z in zs]
    model=optimizer===nothing ? Model() : Model(optimizer; add_bridges = false)
    caps=r7_recovery_loss_cap(c)
    @variable(model, gamma[1:L], Bin)
    for l in 1:L
        lines[l]["vulnerable"] || fix(gamma[l], 0; force = true)
    end
    @constraint(model, sum(gamma)<=c.data["electric"]["fault_budget"])
    @variable(model, 0<=theta<=caps.cap_MWh)
    blocks=Any[]
    for (k, lp) in enumerate(lps)
        block=r7_add_recourse_dual!(model, lp; prefix = "mode_$k")
        lambda=block.lambda
        bound=AffExpr(lp.data["constant"])
        products=Dict{String,Any}[]
        for (i, row) in enumerate(lp.data["rows"])
            add_to_expression!(bound, row["rhs"], lambda[i])
            for (j, d) in zip(row["fault_columns"], row["fault_coefficients"])
                w=@variable(model, base_name="mode_$(k)_product_$(i)_$(j)")
                # R7-I4：γ=0时乘积为0；γ=1时等于λ。λ没有人为有限界。
                @constraint(model, !gamma[j] --> {w==0})
                @constraint(model, gamma[j] --> {w-lambda[i]==0})
                add_to_expression!(bound, d, w)
                push!(products, Dict("row"=>i, "fault_column"=>j, "variable"=>w))
            end
        end
        @constraint(model, theta<=bound)
        push!(blocks, (; lp, lambda, products, bound))
    end
    @objective(model, Max, theta)
    (;
        model,
        gamma,
        theta,
        blocks,
        topologies = zs,
        cap = caps,
        model_class = "MILP_native_indicators",
        automatic_bridges = false,
    )
end
