"""R9-DC1：主体身份保留到四类通信表达式，再按实际网络节点聚合。"""
function r9_trading_message_expressions(c, v)
    d=c.data
    a, g, T=d["actors"], d["devices"], d["T"]
    m=Matrix{AffExpr}(undef, 4(length(a)-1), T)
    for i in 2:length(a), t in 1:T
        owned=findall(x->x["owner"]==i, g)
        m[4i-7, t]=sum(v["P_gen"][j, t]-v["P_cons"][j, t] for j in owned; init = AffExpr(0.0))-v["P_D"][
            i,
            t,
        ]
        m[4i-6, t]=a[i]["Q_ratio"]*v["P_D"][i, t]+AffExpr(0.0)
        m[4i-5, t]=sum(v["H_gen"][j, t] for j in owned; init = AffExpr(0.0))
        m[4i-4, t]=v["H_D"][i, t]+sum(v["H_cons"][j, t] for j in owned; init = AffExpr(0.0))
    end
    m
end

"""R9-DC4：更新块的增广目标，目标/乘子均为无量纲；运营商乘子符号与主体相反。"""
function r9_distributed_objective!(b, target, dual, cost_scale, rho)
    size(target)==size(dual)==size(b.message) || error("增广消息形状不符")
    all(isfinite, target) && all(isfinite, dual) || error("增广消息非有限")
    sign=b.actor==1 ? -1.0 : 1.0
    scales=b.contract.scale[b.rows]
    @objective(
        b.model,
        Min,
        b.cost/cost_scale +
        rho/2*sum(
            (b.message[k, t]/scales[k]-target[k, t]+sign*dual[k, t])^2 for
            k in axes(target, 1), t in axes(target, 2)
        )
    )
    nothing
end

"""
    build_r9_distributed_block(case; actor, modes=nothing, optimizer=nothing)

R9-DC2/DC3：构造任意聚合商数量的资源协调块，不求解、不写文件。
actor=1为运营商，保留其资源、电热网络和各聚合商四类边界副本；其余actor只保留自身设备、
储能和偏好，不加入独立运营的零售目标。一致边界下，各块资源目标之和等于原集中SWM目标。
模式必须显式一致地传入各块。完整固定离散模式才是连续SOCP；modes=nothing保留整数，
不能继承凸ADMM收敛保证。热网仍为声明的稳态能量/质量包络。
"""
function build_r9_distributed_block(c::R9TradingCase; actor, modes = nothing, optimizer = nothing)
    actor isa Integer && actor in eachindex(c.data["actors"]) || error("分块主体编号错误")
    b=build_r9_trading_model(
        c;
        stage = actor==1 ? :operator : :agent,
        actor,
        modes,
        optimizer,
        electric = :socp,
    )
    rows=actor==1 ? (1:4(length(c.data["actors"])-1)) : ((4(actor-2)+1):(4(actor-1)))
    (;
        base = b,
        model = b.model,
        variables = b.variables,
        constraints = b.constraints,
        message = b.boundary[rows, :],
        cost = b.resource+b.discomfort+b.external+b.switching,
        actor,
        rows,
        contract = r9_boundary_contract(c),
        input_sha256 = c.sha256,
        model_class = b.model_class,
        model_types = b.model_types,
        convex_fixed_mode = b.model_class=="SOCP" &&
                            !any(x->is_binary(x)||is_integer(x), all_variables(b.model)),
        objective_kind = "unaugmented_resource_cost_CNY",
    )
end
