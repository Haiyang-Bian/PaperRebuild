const R5_MARKET_MODEL_FILE = @__FILE__

function r5_market_lp_types(model)
    rows=Dict{String,Any}[]
    for (F, S) in list_of_constraint_types(model)
        F in (VariableRef, AffExpr) &&
        S in (MOI.GreaterThan{Float64}, MOI.LessThan{Float64}, MOI.EqualTo{Float64}) ||
            error("市场构建含有非连续LP约束：$F in $S")
        push!(
            rows,
            Dict("function"=>string(F), "set"=>string(S), "count"=>num_constraints(model, F, S)),
        )
    end
    objective_function_type(model) in (VariableRef, AffExpr) || error("市场目标非线性")
    sort!(rows; by = x->(x["function"], x["set"]))
end

"""
    build_r5_market(case; optimizer=nothing)

构建原(5-34)至(5-42)采用版连续LP，不求解或写文件。
普通负荷与IES购电均消耗电能；上备用对应发电增加或IES减少购电。
按输入时间步转换费用及爬坡；原(5-49)/(5-50)的负荷符号冲突不复制到采用模型。
"""
function build_r5_market(c::R5MarketCase; optimizer = nothing)
    r5_market_assert_case(c)
    d=c.data
    G, I, B, L, T=r5_market_sizes(c)
    gen, ies=d["generators"], d["ies"]
    dt=d["dt_h"]
    m=optimizer===nothing ? Model() : Model(optimizer)
    @variable(m, P_G[1:G, 1:T]>=0)
    @variable(m, R_G_up[1:G, 1:T]>=0)
    @variable(m, R_G_down[1:G, 1:T]>=0)
    @variable(m, P_IES[1:I, 1:T]>=0)
    @variable(m, R_IES_up[1:I, 1:T]>=0)
    @variable(m, R_IES_down[1:I, 1:T]>=0)
    v=(; P_G, R_G_up, R_G_down, P_IES, R_IES_up, R_IES_down)
    rows=Dict{Symbol,Any}()
    # ch05-037：正负号由能量守恒决定；购电量不会在供给侧重复出现。
    rows[:energy]=@constraint(
        m,
        [t=1:T],
        sum(d["load_MW"][b][t] for b in 1:B)+sum(P_IES[:, t])-sum(P_G[:, t])==0
    )
    rows[:up]=@constraint(
        m,
        [t=1:T],
        d["reserve_up_MW"][t]-sum(R_G_up[:, t])-sum(R_IES_up[:, t])==0
    )
    rows[:down]=@constraint(
        m,
        [t=1:T],
        d["reserve_down_MW"][t]-sum(R_G_down[:, t])-sum(R_IES_down[:, t])==0
    )
    rows[:g_cap_up]=@constraint(m, [g=1:G, t=1:T], P_G[g, t]+R_G_up[g, t]<=gen[g]["p_max"])
    rows[:g_cap_down]=@constraint(m, [g=1:G, t=1:T], P_G[g, t]-R_G_down[g, t]>=gen[g]["p_min"])
    # ch05-039：负荷提供上备用需能减少购电，下备用需能增加购电。
    rows[:i_cap_up]=@constraint(m, [i=1:I, t=1:T], P_IES[i, t]-R_IES_up[i, t]>=ies[i]["q_min"])
    rows[:i_cap_down]=@constraint(m, [i=1:I, t=1:T], P_IES[i, t]+R_IES_down[i, t]<=ies[i]["q_max"])
    rows[:q_bid]=@constraint(m, [i=1:I, t=1:T], P_IES[i, t]<=ies[i]["purchase_bid_max"])
    rows[:pg_bid]=@constraint(m, [g=1:G, t=1:T], P_G[g, t]<=gen[g]["p_bid_max"])
    rows[:gu_bid]=@constraint(m, [g=1:G, t=1:T], R_G_up[g, t]<=gen[g]["up_max"])
    rows[:gd_bid]=@constraint(m, [g=1:G, t=1:T], R_G_down[g, t]<=gen[g]["down_max"])
    rows[:iu_bid]=@constraint(m, [i=1:I, t=1:T], R_IES_up[i, t]<=ies[i]["up_max"])
    rows[:id_bid]=@constraint(m, [i=1:I, t=1:T], R_IES_down[i, t]<=ies[i]["down_max"])
    prev(g, t) = t==1 ? gen[g]["p_initial"] : P_G[g, t-1]
    rows[:ramp_up]=@constraint(m, [g=1:G, t=1:T], P_G[g, t]-prev(g, t)<=dt*gen[g]["ramp_up_MW_h"])
    rows[:ramp_down]=@constraint(
        m,
        [g=1:G, t=1:T],
        prev(g, t)-P_G[g, t]<=dt*gen[g]["ramp_down_MW_h"]
    )
    @expression(
        m,
        injection[b=1:B, t=1:T],
        sum(P_G[g, t] for g in 1:G if gen[g]["node"]==b) -
        sum(P_IES[i, t] for i in 1:I if ies[i]["node"]==b)-d["load_MW"][b][t]
    )
    @expression(m, flow[l=1:L, t=1:T], sum(d["network"]["ptdf"][l][b]*injection[b, t] for b in 1:B))
    rows[:line_up]=@constraint(m, [l=1:L, t=1:T], flow[l, t]<=d["network"]["limit_MW"][l])
    rows[:line_down]=@constraint(m, [l=1:L, t=1:T], -flow[l, t]<=d["network"]["limit_MW"][l])
    @objective(
        m,
        Min,
        dt*(
            sum(
                gen[g]["energy_bid"][t]*P_G[g, t]+gen[g]["up_bid"][t]*R_G_up[g, t]+gen[g]["down_bid"][t]*R_G_down[
                    g,
                    t,
                ] for g in 1:G, t in 1:T
            ) + sum(
                -ies[i]["energy_bid"][t]*P_IES[i, t] +
                ies[i]["up_bid"][t]*R_IES_up[i, t] +
                ies[i]["down_bid"][t]*R_IES_down[i, t] for i in 1:I, t in 1:T
            )
        )
    )
    # 固定报价的出清是LP；策略报价及KKT二进制化不是这个构建接口的职责。
    (;
        model = m,
        variables = v,
        rows,
        flow,
        formulation = "r5_market_clearing_checked_v1",
        model_type = "continuous_LP",
        model_types = r5_market_lp_types(m),
    )
end

"""
    build_r5_market_dual(case; optimizer=nothing)

从出清LP逐项推导的独立对偶，不调用JuMP的自动对偶变换。
π、σ为等式乘子；容量/线路/爬坡乘子非负。含初始出力和相邻时段爬坡贡献。
该对偶仅适用于固定报价连续LP，不能直接认证含策略决策的双层问题。
"""
function build_r5_market_dual(c::R5MarketCase; optimizer = nothing)
    r5_market_assert_case(c)
    d=c.data
    G, I, B, L, T=r5_market_sizes(c)
    gen, ies=d["generators"], d["ies"]
    dt=d["dt_h"]
    m=optimizer===nothing ? Model() : Model(optimizer)
    @variable(m, π[1:T])
    @variable(m, σ_up[1:T])
    @variable(m, σ_down[1:T])
    vars=Dict{Symbol,Any}(:energy=>π, :up=>σ_up, :down=>σ_down)
    for (key, n) in (
        (:g_cap_up, G),
        (:g_cap_down, G),
        (:i_cap_up, I),
        (:i_cap_down, I),
        (:q_bid, I),
        (:pg_bid, G),
        (:gu_bid, G),
        (:gd_bid, G),
        (:iu_bid, I),
        (:id_bid, I),
        (:ramp_up, G),
        (:ramp_down, G),
        (:line_up, L),
        (:line_down, L),
    )
        vars[key]=@variable(m, [1:n, 1:T], lower_bound=0, base_name=string(key))
    end
    a=vars
    δ(l, t) = a[:line_up][l, t]-a[:line_down][l, t]
    congestion(b, t) = sum(d["network"]["ptdf"][l][b]*δ(l, t) for l in 1:L; init = 0.0)
    ramp(g, t) = a[:ramp_up][g, t]-a[:ramp_down][g, t]
    # R5-MK1：非负原变量对应约化费用>=0，不能省略下一时段爬坡乘子。
    @constraint(
        m,
        [g=1:G, t=1:T],
        dt*gen[g]["energy_bid"][t]-π[t] + congestion(gen[g]["node"], t) + a[:g_cap_up][g, t]-a[:g_cap_down][
            g,
            t,
        ]+a[:pg_bid][g, t]+ramp(g, t) - (t<T ? ramp(g, t+1) : 0)>=0
    )
    @constraint(
        m,
        [g=1:G, t=1:T],
        dt*gen[g]["up_bid"][t]-σ_up[t]+a[:g_cap_up][g, t]+a[:gu_bid][g, t]>=0
    )
    @constraint(
        m,
        [g=1:G, t=1:T],
        dt*gen[g]["down_bid"][t]-σ_down[t]+a[:g_cap_down][g, t]+a[:gd_bid][g, t]>=0
    )
    @constraint(
        m,
        [i=1:I, t=1:T],
        -dt*ies[i]["energy_bid"][t]+π[t] - congestion(ies[i]["node"], t)+a[:i_cap_down][i, t]-a[:i_cap_up][
            i,
            t,
        ]+a[:q_bid][i, t]>=0
    )
    @constraint(
        m,
        [i=1:I, t=1:T],
        dt*ies[i]["up_bid"][t]-σ_up[t]+a[:i_cap_up][i, t]+a[:iu_bid][i, t]>=0
    )
    @constraint(
        m,
        [i=1:I, t=1:T],
        dt*ies[i]["down_bid"][t]-σ_down[t]+a[:i_cap_down][i, t]+a[:id_bid][i, t]>=0
    )
    @objective(
        m,
        Max,
        sum(
            π[t]*sum(d["load_MW"][b][t] for b in 1:B)+σ_up[t]*d["reserve_up_MW"][t]+σ_down[t]*d["reserve_down_MW"][t]
            for t in 1:T
        ) + sum(
            -a[:g_cap_up][g, t]*gen[g]["p_max"]+a[:g_cap_down][g, t]*gen[g]["p_min"] -
            a[:pg_bid][g, t]*gen[g]["p_bid_max"] - a[:gu_bid][g, t]*gen[g]["up_max"]-a[:gd_bid][
                g,
                t,
            ]*gen[g]["down_max"] -
            dt*(
                a[:ramp_up][g, t]*gen[g]["ramp_up_MW_h"] +
                a[:ramp_down][g, t]*gen[g]["ramp_down_MW_h"]
            ) for g in 1:G, t in 1:T
        ) - sum((a[:ramp_up][g, 1]-a[:ramp_down][g, 1])*gen[g]["p_initial"] for g in 1:G) + sum(
            a[:i_cap_up][i, t]*ies[i]["q_min"]-a[:i_cap_down][i, t]*ies[i]["q_max"] -
            a[:q_bid][i, t]*ies[i]["purchase_bid_max"] - a[:iu_bid][i, t]*ies[i]["up_max"]-a[:id_bid][
                i,
                t,
            ]*ies[i]["down_max"] for i in 1:I, t in 1:T
        ) - sum(
            δ(l, t)*sum(d["network"]["ptdf"][l][b]*d["load_MW"][b][t] for b in 1:B) +
            (a[:line_up][l, t]+a[:line_down][l, t])*d["network"]["limit_MW"][l] for
            l in 1:L, t in 1:T
        )
    )
    (;
        model = m,
        variables = vars,
        formulation = "r5_market_dual_checked_v1",
        model_type = "continuous_LP",
        model_types = r5_market_lp_types(m),
    )
end
