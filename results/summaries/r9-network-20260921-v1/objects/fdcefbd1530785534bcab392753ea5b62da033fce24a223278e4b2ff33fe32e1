const R5_MARKET_PAYMENT_FILE=@__FILE__

# R5-SP3：只有全时域求和后才能用爬坡互补消去相邻出力；初始出力项不能省略。
function r5_market_payment_terms(c, s, a)
    d=c.data
    G, I, B, L, T=r5_market_sizes(c)
    dt=d["dt_h"]
    gen=d["generators"]
    terms=Dict{String,Any}()
    terms["generator_energy"]=dt*sum(gen[g]["energy_bid"][t]*s[:P_G][g, t] for g in 1:G, t in 1:T)
    terms["generator_up"]=dt*sum(gen[g]["up_bid"][t]*s[:R_G_up][g, t] for g in 1:G, t in 1:T)
    terms["generator_down"]=dt*sum(gen[g]["down_bid"][t]*s[:R_G_down][g, t] for g in 1:G, t in 1:T)
    terms["generator_capacity"]=sum(
        a[:g_cap_up][g, t]*gen[g]["p_max"] - a[:g_cap_down][g, t]*gen[g]["p_min"] for
        g in 1:G, t in 1:T
    )
    terms["generator_bid_capacity"]=sum(
        a[:pg_bid][g, t]*gen[g]["p_bid_max"]+a[:gu_bid][g, t]*gen[g]["up_max"]+a[:gd_bid][g, t]*gen[g]["down_max"]
        for g in 1:G, t in 1:T
    )
    terms["ramp_capacity"]=dt*sum(
        a[:ramp_up][g, t]*gen[g]["ramp_up_MW_h"] + a[:ramp_down][g, t]*gen[g]["ramp_down_MW_h"] for
        g in 1:G, t in 1:T
    )
    terms["ramp_initial"]=sum(
        (a[:ramp_up][g, 1]-a[:ramp_down][g, 1])*gen[g]["p_initial"] for g in 1:G
    )
    terms["line_capacity"]=sum(
        (a[:line_up][l, t]+a[:line_down][l, t])*d["network"]["limit_MW"][l] for l in 1:L, t in 1:T;
        init = 0.0,
    )
    congestion(b, t) = sum(
        d["network"]["ptdf"][l][b]*(a[:line_up][l, t]-a[:line_down][l, t]) for l in 1:L;
        init = 0.0,
    )
    terms["ordinary_load_payment"] =
        -sum((a[:energy][t]-congestion(b, t))*d["load_MW"][b][t] for b in 1:B, t in 1:T)
    terms["system_reserve_payment"] =
        -sum(a[:up][t]*d["reserve_up_MW"][t] + a[:down][t]*d["reserve_down_MW"][t] for t in 1:T)
    terms
end

"""
    r5_market_payment_identity(case, result)

独立核查全部IES的日前净支付：节点电价乘购电量，减去上/下备用价格乘成交容量。
输入为已保存的市场出清原值及原始/转换乘子；MW、h和USD单位沿用R5MarketCase。
返回直接支付、逐IES支付、由生成侧KKT消去乘积的线性表达、分项及验收状态，不求解、不改写结果。

对应原(5-6)、(5-59)至(5-61)及项目R5-SP1至SP3。线性式含报价上界租金、初始出力及PTDF负荷项；
它是全时域、全部IES合计恒等式，不能逐时替换或误作一个IES的支付。其他发电报价及容量须保持外生。
只有原市场模型、原始对偶KKT和支付恒等式均通过，valid_for_reformulation才为true。
恒等式不消除市场退化：价格不唯一时，上层选择其中有利价格属于额外的乐观双层假设，尚未在此实现。
"""
function r5_market_payment_identity(c::R5MarketCase, r)
    check=validate_r5_market(c, r)
    out=Dict{String,Any}(
        "schema"=>"r5-market-payment-check-v1",
        "case_sha256"=>c.sha256,
        "run_id"=>r["run_id"],
        "unit"=>"USD",
        "scope"=>"all_IES_whole_horizon",
        "market_model_pass"=>check["model_pass"],
        "market_kkt_pass"=>check["kkt_pass"],
        "identity_pass"=>false,
        "valid_for_reformulation"=>false,
        "status"=>"missing_candidate_or_multipliers",
    )
    haskey(r, "values")&&haskey(r, "multipliers")||return out
    d=c.data
    G, I, B, L, T=r5_market_sizes(c)
    s=r5_market_values(c, r["values"])
    a=r5_market_multipliers(c, r["multipliers"])
    payments=zeros(I, T)
    for i in 1:I, t in 1:T
        b=d["ies"][i]["node"]
        congestion=sum(
            d["network"]["ptdf"][l][b]*(a[:line_up][l, t]-a[:line_down][l, t]) for l in 1:L;
            init = 0.0,
        )
        # 乘子已含Δt；此处不再次乘时长，避免MW/MWh换算重复。
        payments[i, t]=(a[:energy][t]-congestion)*s[:P_IES][i, t] - a[:up][t]*s[:R_IES_up][i, t]-a[:down][t]*s[:R_IES_down][
            i,
            t,
        ]
    end
    direct=sum(payments)
    terms=r5_market_payment_terms(c, s, a)
    affine=sum(values(terms))
    tolerance=1e-6*max(1.0, abs(direct), abs(affine))
    residual=abs(direct-affine)
    pass=isfinite(residual)&&residual<=tolerance
    trusted=check["model_pass"]&&check["kkt_pass"]&&pass
    merge!(
        out,
        Dict(
            "payment_by_IES_USD"=>r5_market_rows(payments),
            "direct_payment_USD"=>direct,
            "affine_payment_USD"=>affine,
            "linear_terms_USD"=>terms,
            "identity_residual_USD"=>residual,
            "identity_tolerance_USD"=>tolerance,
            "identity_pass"=>pass,
            "valid_for_reformulation"=>trusted,
            "status"=>trusted ? "payment_identity_verified" : "untrusted_market_or_identity",
        ),
    )
    out
end
