const R5_STRATEGIC_VERIFY_FILE = @__FILE__

function r5_strategic_pair_values(c, r, cv)
    d=c.data
    s=r5_market_values(c, r["values"])
    a=r5_market_multipliers(c, r["multipliers"])
    G, I, _, L, T=r5_market_sizes(c)
    pairs=Dict{String,Tuple{Float64,Float64}}()
    function put(key, i, t, slack)
        pairs["$key/$i/$t"]=(a[Symbol(key)][i, t], slack)
    end
    for g in 1:G, t in 1:T
        x=d["generators"][g]
        p, u, v=s[:P_G][g, t], s[:R_G_up][g, t], s[:R_G_down][g, t]
        prev=t==1 ? x["p_initial"] : s[:P_G][g, t-1]
        put("g_cap_up", g, t, x["p_max"]-p-u)
        put("g_cap_down", g, t, p-v-x["p_min"])
        put("pg_bid", g, t, x["p_bid_max"]-p)
        put("gu_bid", g, t, x["up_max"]-u)
        put("gd_bid", g, t, x["down_max"]-v)
        put("ramp_up", g, t, d["dt_h"]*x["ramp_up_MW_h"]-p+prev)
        put("ramp_down", g, t, d["dt_h"]*x["ramp_down_MW_h"]+p-prev)
    end
    for i in 1:I, t in 1:T
        x=d["ies"][i]
        p, u, v=s[:P_IES][i, t], s[:R_IES_up][i, t], s[:R_IES_down][i, t]
        put("i_cap_up", i, t, p-u-x["q_min"])
        put("i_cap_down", i, t, x["q_max"]-p-v)
        put("q_bid", i, t, x["purchase_bid_max"]-p)
        put("iu_bid", i, t, x["up_max"]-u)
        put("id_bid", i, t, x["down_max"]-v)
    end
    for l in 1:L, t in 1:T
        put("line_up", l, t, d["network"]["limit_MW"][l]-cv["flow_MW"][l][t])
        put("line_down", l, t, d["network"]["limit_MW"][l]+cv["flow_MW"][l][t])
    end
    for (k, x) in s, i in axes(x, 1), t in 1:T
        pairs["lower/$k/$i/$t"]=(r["lower_bound_duals"][string(k)][i][t], x[i, t])
    end
    pairs
end

"""
    validate_r5_strategic(case, result)

只读核查连续报价、成交桥接、选择出的下层KKT、独立重解及全部风险补救数值。
优化乘子没有原始MOI对偶身份；selected_kkt_pass与independent_market_kkt_pass分别保存。
使用原A1/A2/KKT门槛，不要求退化出清的成交或价格与独立求解器完全相同。
全域/固定分支的上层界分开；费用和风险检查均限输入有限支持，不是样本外保证。
"""
function validate_r5_strategic(c::R5StrategicCase, r)
    r5_strategic_assert_case(c)
    get(r, "case_sha256", nothing) == c.sha256 || error("策略结果输入不一致")
    out = Dict{String,Any}(
        "model_pass"=>false,
        "selected_kkt_pass"=>false,
        "independent_market_kkt_pass"=>false,
        "risk_pass"=>false,
        "cost_pass"=>false,
        "optimality_pass"=>false,
        "rows"=>Dict{String,Any}[],
        "status"=>"missing_candidate",
    )
    all(haskey(r, k) for k in ("bids", "selected_market", "risk_policy")) || return out
    rec(id, group, v, tol; unit = "1") = r5_risk_record!(out, id, group, v, tol; unit)
    bids = r["bids"]
    T = c.data["market"]["T"]
    market = r5_strategic_market_case(c, bids)
    chosen = r["selected_market"]
    get(chosen, "multiplier_source", "") == "optimized_KKT_variables" ||
        error("选定乘子必须标明优化变量来源")
    haskey(chosen, "raw_duals") && error("不得将优化乘子伪造成MOI原始对偶")
    for k in R5_STRATEGIC_BIDS, t in 1:T
        b = c.data["bid_bounds"][k]
        rec(
            "$k/$t",
            "bid_bounds",
            max(0.0, b["lower"][t]-bids[k][t], bids[k][t]-b["upper"][t]),
            1e-6*max(1.0, b["upper"][t]);
            unit = "USD/MWh",
        )
    end
    cv = validate_r5_market(market, chosen)
    out["selected_market"] = cv
    # 纯数值原始/对偶可行、驻点、互补及原对偶差；不更改旧API的原始乘子认证语义。
    out["selected_kkt_pass"] =
        cv["model_pass"] &&
        haskey(chosen, "lower_bound_duals") &&
        all(x["pass"] for x in cv["rows"] if x["scope"]=="dual") &&
        haskey(cv, "relative_gap")
    if haskey(r, "complementarity_pattern")
        numeric=r5_strategic_pair_values(market, chosen, cv)
        pat=r["complementarity_pattern"]
        Set(keys(numeric))==Set(keys(pat)) && all(v in (0, 1) for v in values(pat)) ||
            error("存档互补分支不完整或非法")
        for (id, bit) in pat
            μ, s=numeric[id]
            scale=bit==0 ? market.data["dt_h"]*cv["price_scale_USD_MWh"] : 1+cv["power_scale_MW"]
            rec(id, "fixed_branch", (bit==0 ? μ : s)/scale, 1e-6)
        end
    end
    payment = r5_market_payment_identity(market, chosen)
    out["payment"] = payment
    rp = r["risk_policy"]
    get(r, "risk_pattern", nothing)==get(rp, "pattern", nothing) || error("舒适分支记录不同")
    out["risk_policy"] = validate_r5_risk(R5RiskCase(c.data["risk"]), rp)
    rv = out["risk_policy"]
    for (key, v) in (("P_DA_MW", "P_IES"), ("R_up_MW", "R_IES_up"), ("R_down_MW", "R_IES_down"))
        a = only(chosen["values"][v])
        for t in 1:T
            rec(
                "$key/$t",
                "bridge",
                a[t]-rp["first_stage"][key][t],
                1e-6*(1+max(1.0, c.data["market"]["ies"][1]["q_max"]));
                unit = "MW",
            )
        end
    end
    modelobj = payment["affine_payment_USD"] + rv["model_objective_recomputed"]
    rec(
        "upper-objective",
        "cost",
        r["solver_objective"]-modelobj,
        1e-6*max(1.0, abs(modelobj));
        unit = "USD",
    )
    out["model_pass"] =
        out["selected_kkt_pass"] &&
        rv["model_pass"] &&
        payment["identity_pass"] &&
        all(x["pass"] for x in out["rows"])
    out["risk_pass"] = rv["risk_pass"]
    out["cost_pass"] = rv["cost_pass"] && all(x["pass"] for x in out["rows"] if x["group"]=="cost")
    out["selected_payment_USD"] = payment["direct_payment_USD"]
    out["model_objective_recomputed"] = modelobj
    if haskey(rv, "worst_net_cost")
        out["worst_recourse_USD"] = rv["worst_net_cost"]
        out["worst_total_cost_USD"] = payment["direct_payment_USD"]+rv["worst_net_cost"]
    end
    if haskey(r, "independent_market")
        iv = validate_r5_market(market, r["independent_market"])
        out["independent_market"] = iv
        if iv["optimality_pass"]
            diff =
                abs(iv["clearing_objective"]-cv["clearing_objective"]) /
                max(1.0, abs(iv["clearing_objective"]), abs(cv["clearing_objective"]))
            rec("independent-lower-optimum", "independent", diff, 1e-4)
            out["independent_market_kkt_pass"] = diff<=1e-4
            out["independent_payment"] = r5_market_payment_identity(market, r["independent_market"])
        end
    end
    out["bound_scope"] =
        haskey(r, "complementarity_pattern") || haskey(r, "risk_pattern") ?
        "declared_fixed_branch" : "full_optimistic_MPEC"
    if haskey(out, "worst_total_cost_USD")
        upper = out["worst_total_cost_USD"]
        bound = get(r, "solver_objective_bound", NaN)
        valid = isfinite(bound) && bound <= upper+1e-6*max(1.0, abs(upper))
        out["valid_bound"] = valid
        out["relative_gap"] = valid ? max(0.0, upper-bound)/max(1.0, abs(upper), abs(bound)) : Inf
        out["optimality_pass"] =
            out["model_pass"] &&
            out["risk_pass"] &&
            out["cost_pass"] &&
            out["independent_market_kkt_pass"] &&
            valid &&
            out["relative_gap"]<=1e-4
    end
    out["status"] = "evaluated"
    out
end
