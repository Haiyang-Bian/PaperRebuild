"""
    build_r4_distributed_block(case; actor, modes, optimizer=nothing, purpose=:swm)

构建单个主体的凸块，不求解、不写文件。actor=1为仅含DSO设备及网络副本的运营商，
actor=2/3为只含自身设备的聚合商。modes必须显式给定逐时0/1电池状态。
通信顺序P_net(MW)、Q_D(Mvar)、H_src(MW)、H_D(MW)；合同出售为正。
purpose=:agnb保留聚合商零售与卖方一次服务费，忽略网络；:swm只计资源与不满意度。
式4-60至4-70的采用推导见R4-D1至D5；严格限制SOCP，拒绝自动切换非凸或整数模型。
"""
function build_r4_distributed_block(c::R4Case; actor, modes, optimizer = nothing, purpose = :swm)
    actor in 1:3 || error("主体错误")
    purpose in (:swm, :agnb) || error("分布目标错误")
    actor==1 && purpose!=:swm && error("AGNB没有运营商块")
    modes!==nothing && length(modes)==c.data["T"] && all(x->x in (0, 1), modes) ||
        error("必须冻结离散模式")
    b=build_r4_model(c; optimizer, stage = actor==1 ? :operator : :agent, actor, modes)
    m=b.model
    v=b.variables
    T=c.data["T"]
    e=b.boundary
    indices=actor==1 ? [2, 3] : [actor]
    message=Matrix{AffExpr}(undef, 4length(indices), T)
    for (j, i) in enumerate(indices), t in 1:T
        for (k, val) in
            enumerate((e.P_net[i, t], e.Q_load[i, t], e.H_source[i, t], e.H_demand[i, t]))
            message[4(j-1)+k, t]=AffExpr(0.0)+val
        end
    end
    cost=b.resource+b.dissatisfaction+b.external
    peer=Matrix{VariableRef}(undef, 0, T)
    if actor>1
        a=c.data["actors"][actor]
        price=c.data["settlement"]
        qmax=c.data["p2p_enabled"] ? minimum(x["retail_limit"] for x in c.data["actors"][2:3]) : 0.0
        peer=@variable(m, [1:2, 1:T], lower_bound=-qmax, upper_bound=qmax, base_name="peer")
        v["peer"]=peer
        for (k, carrier) in enumerate(("P", "H"))
            buy=@variable(
                m,
                [1:T],
                lower_bound=0,
                upper_bound=a["retail_limit"],
                base_name=carrier*"_buy"
            )
            sell=@variable(
                m,
                [1:T],
                lower_bound=0,
                upper_bound=a["retail_limit"],
                base_name=carrier*"_sell"
            )
            fee=@variable(
                m,
                [1:T],
                lower_bound=0,
                upper_bound=qmax,
                base_name=carrier*"_fee_quantity"
            )
            v[carrier*"_buy"]=buy
            v[carrier*"_sell"]=sell
            v[carrier*"_fee_quantity"]=fee
            for t in 1:T
                net=k==1 ? message[1, t] : message[3, t]-message[4, t]
                @constraint(m, net==sell[t]-buy[t]+peer[k, t])
                @constraint(m, fee[t]>=peer[k, t])
                if purpose==:agnb
                    # 正出售侧支付一次服务费；反对称合同收敛后两方正部之和为|q|。
                    add_to_expression!(cost, c.data["dt_h"]*price[carrier*"_buy"], buy[t])
                    add_to_expression!(cost, -c.data["dt_h"]*price[carrier*"_sell"], sell[t])
                    add_to_expression!(cost, c.data["dt_h"]*price["fee"], fee[t])
                end
            end
        end
    end
    return (; base = b, model = m, variables = v, message, peer, cost, actor, purpose)
end

function r4_set_distributed_objective!(
    b,
    scales,
    spec;
    target = nothing,
    dual = nothing,
    peer_target = nothing,
    peer_dual = nothing,
)
    objective=b.cost/scales["cost"]
    if target!==nothing
        for k in axes(b.message, 1), t in axes(b.message, 2)
            # x-z+u：AG块为+x，运营商块为-z；平方内等价翻号，但线性乘子必须反向。
            s=scales["boundary"][mod1(k, 4)]
            sign=b.actor==1 ? -1.0 : 1.0
            objective+=spec.rho/2*(b.message[k, t]/s-target[k, t]+sign*dual[k, t])^2
        end
    end
    if peer_target!==nothing
        for k in 1:2, t in axes(b.peer, 2)
            objective+=spec.peer_rho/2*(
                b.peer[k, t]/scales["peer"][k]-peer_target[k, t]+peer_dual[k, t]
            )^2
        end
    end
    @objective(b.model, Min, objective)
    return nothing
end
