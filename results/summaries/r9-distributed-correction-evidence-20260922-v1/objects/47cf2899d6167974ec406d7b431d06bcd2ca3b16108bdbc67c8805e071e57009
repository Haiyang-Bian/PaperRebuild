const R5_MARKET_VERIFY_FILE = @__FILE__

function r5_market_matrix(x, n, T)
    n==0 && isempty(x) && return zeros(0, T)
    a=r5_market_array(x)
    size(a)==(n, T) && all(isfinite, a) || error("市场数值数组形状或有限性错误")
    a
end

function r5_market_values(c, s)
    G, I, B, L, T=r5_market_sizes(c)
    Dict(
        k=>r5_market_matrix(s[string(k)], n, T) for (k, n) in
        ((:P_G, G), (:R_G_up, G), (:R_G_down, G), (:P_IES, I), (:R_IES_up, I), (:R_IES_down, I))
    )
end

function r5_market_multipliers(c, s)
    G, I, B, L, T=r5_market_sizes(c)
    a=Dict{Symbol,Any}()
    for key in (:energy, :up, :down)
        v=Float64.(s[string(key)])
        length(v)==T && all(isfinite, v) || error("等式乘子错误")
        a[key]=v
    end
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
        a[key]=r5_market_matrix(s[string(key)], n, T)
    end
    a
end

"""
    validate_r5_market(case, result)

不访问JuMP约束表达式，从保存的出清量、原始/转换乘子重算功率、边界、爬坡、
PTDF、费用、KKT及原对偶差。A1功率尺度固定为输入总发电容量；
KKT无量纲门槛1e-6，费用差采用A2的1e-4。缺失对偶时不宣称价格/最优性合格。
"""
function validate_r5_market(c::R5MarketCase, r)
    r5_market_assert_case(c)
    r["case_sha256"]==c.sha256 || error("市场结果与输入不匹配")
    if !haskey(r, "values")
        return Dict{String,Any}(
            "model_pass"=>false,
            "kkt_pass"=>false,
            "optimality_pass"=>false,
            "status"=>"no_candidate",
            "rows"=>Dict{String,Any}[],
        )
    end
    d=c.data
    G, I, B, L, T=r5_market_sizes(c)
    gen, ies=d["generators"], d["ies"]
    dt=d["dt_h"]
    s=r5_market_values(c, r["values"])
    P, U, D, Q, V, W=(s[k] for k in (:P_G, :R_G_up, :R_G_down, :P_IES, :R_IES_up, :R_IES_down))
    power_scale=max(1.0, sum(g["p_max"] for g in gen))
    price_scale=max(
        1.0,
        maximum(
            abs(v) for kind in (gen, ies) for a in kind for
            k in ("energy_bid", "up_bid", "down_bid") for v in a[k]
        ),
    )
    money_scale=max(1.0, dt*price_scale*power_scale)
    p_tol=1e-6*(1+power_scale)
    rows=Dict{String,Any}[]
    function record(id, scope, entity, t, residual, unit, tolerance)
        v=abs(Float64(residual))
        push!(
            rows,
            Dict(
                "id"=>id,
                "scope"=>scope,
                "entity"=>string(entity),
                "t"=>t,
                "residual"=>v,
                "unit"=>unit,
                "tolerance"=>tolerance,
                "pass"=>isfinite(v)&&v<=tolerance,
            ),
        )
    end
    slacks=Dict{Symbol,Any}()
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
        slacks[key]=zeros(n, T)
    end
    injections=zeros(B, T)
    flows=zeros(L, T)
    for b in 1:B, t in 1:T
        injections[b, t]=sum(P[g, t] for g in 1:G if gen[g]["node"]==b; init = 0.0) -
                         sum(Q[i, t] for i in 1:I if ies[i]["node"]==b; init = 0.0)-d["load_MW"][b][t]
    end
    for t in 1:T
        record("5-37", "primal", "energy", t, sum(injections[:, t]), "MW", p_tol)
        record(
            "5-36",
            "primal",
            "up",
            t,
            sum(U[:, t])+sum(V[:, t])-d["reserve_up_MW"][t],
            "MW",
            p_tol,
        )
        record(
            "5-36",
            "primal",
            "down",
            t,
            sum(D[:, t])+sum(W[:, t])-d["reserve_down_MW"][t],
            "MW",
            p_tol,
        )
    end
    for g in 1:G, t in 1:T
        a=gen[g]
        old=t==1 ? a["p_initial"] : P[g, t-1]
        slacks[:g_cap_up][g, t]=a["p_max"]-P[g, t]-U[g, t]
        slacks[:g_cap_down][g, t]=P[g, t]-D[g, t]-a["p_min"]
        slacks[:gu_bid][g, t]=a["up_max"]-U[g, t]
        slacks[:pg_bid][g, t]=a["p_bid_max"]-P[g, t]
        slacks[:gd_bid][g, t]=a["down_max"]-D[g, t]
        slacks[:ramp_up][g, t]=dt*a["ramp_up_MW_h"]-P[g, t]+old
        slacks[:ramp_down][g, t]=dt*a["ramp_down_MW_h"]+P[g, t]-old
    end
    for i in 1:I, t in 1:T
        a=ies[i]
        slacks[:i_cap_up][i, t]=Q[i, t]-V[i, t]-a["q_min"]
        slacks[:i_cap_down][i, t]=a["q_max"]-Q[i, t]-W[i, t]
        slacks[:q_bid][i, t]=a["purchase_bid_max"]-Q[i, t]
        slacks[:iu_bid][i, t]=a["up_max"]-V[i, t]
        slacks[:id_bid][i, t]=a["down_max"]-W[i, t]
    end
    for l in 1:L, t in 1:T
        flows[l, t]=sum(d["network"]["ptdf"][l][b]*injections[b, t] for b in 1:B)
        slacks[:line_up][l, t]=d["network"]["limit_MW"][l]-flows[l, t]
        slacks[:line_down][l, t]=d["network"]["limit_MW"][l]+flows[l, t]
    end
    for (key, a) in slacks, i in axes(a, 1), t in axes(a, 2)
        record("R5-MK_bounds", "primal", string(key)*string(i), t, max(0.0, -a[i, t]), "MW", p_tol)
    end
    for (key, a) in s, i in axes(a, 1), t in axes(a, 2)
        record(
            "R5-MK_nonnegative",
            "primal",
            string(key)*string(i),
            t,
            max(0.0, -a[i, t]),
            "MW",
            p_tol,
        )
    end
    obj=dt*(
        sum(
            gen[g]["energy_bid"][t]*P[g, t] +
            gen[g]["up_bid"][t]*U[g, t] +
            gen[g]["down_bid"][t]*D[g, t] for g in 1:G, t in 1:T
        ) + sum(
            -ies[i]["energy_bid"][t]*Q[i, t] +
            ies[i]["up_bid"][t]*V[i, t] +
            ies[i]["down_bid"][t]*W[i, t] for i in 1:I, t in 1:T;
            init = 0.0,
        )
    )
    record(
        "5-34",
        "cost",
        "objective",
        0,
        obj-r["solver_objective"],
        "USD",
        1e-6*max(1.0, abs(obj)),
    )
    model_pass=all(x["pass"] for x in rows)
    output=Dict{String,Any}(
        "model_pass"=>model_pass,
        "kkt_pass"=>false,
        "optimality_pass"=>false,
        "status"=>"primal_only",
        "clearing_objective"=>obj,
        "flow_MW"=>r5_market_rows(flows),
        "rows"=>rows,
        "power_scale_MW"=>power_scale,
        "price_scale_USD_MWh"=>price_scale,
    )
    haskey(r, "multipliers") || return output
    a=r5_market_multipliers(c, r["multipliers"])
    for (key, mul) in a
        key in (:energy, :up, :down) && continue
        for i in axes(mul, 1), t in axes(mul, 2)
            record(
                "R5-MK_dual_sign",
                "dual",
                string(key)*string(i),
                t,
                max(0.0, -mul[i, t])/(dt*price_scale),
                "1",
                1e-6,
            )
            record(
                "R5-MK_complementarity",
                "dual",
                string(key)*string(i),
                t,
                mul[i, t]*slacks[key][i, t]/money_scale,
                "1",
                1e-6,
            )
        end
    end
    lmps=zeros(B, T)
    for b in 1:B, t in 1:T
        lmps[b, t]=(
            a[:energy][t]-sum(
                d["network"]["ptdf"][l][b] * (a[:line_up][l, t]-a[:line_down][l, t]) for l in 1:L;
                init = 0.0,
            )
        )/dt
    end
    gradient=Dict(k=>zeros(size(v)) for (k, v) in s)
    for g in 1:G, t in 1:T
        ramp=a[:ramp_up][g, t]-a[:ramp_down][g, t] -
             (t<T ? a[:ramp_up][g, t+1]-a[:ramp_down][g, t+1] : 0.0)
        gradient[:P_G][g, t]=dt*(gen[g]["energy_bid"][t]-lmps[gen[g]["node"], t]) +
                             a[:g_cap_up][g, t]-a[:g_cap_down][g, t]+a[:pg_bid][g, t]+ramp
        gradient[:R_G_up][g, t]=dt*gen[g]["up_bid"][t]-a[:up][t]+a[:g_cap_up][g, t]+a[:gu_bid][g, t]
        gradient[:R_G_down][g, t]=dt*gen[g]["down_bid"][t]-a[:down][t]+a[:g_cap_down][g, t]+a[:gd_bid][
            g,
            t,
        ]
    end
    for i in 1:I, t in 1:T
        gradient[:P_IES][i, t]=dt*(-ies[i]["energy_bid"][t]+lmps[ies[i]["node"], t]) +
                               a[:i_cap_down][i, t]-a[:i_cap_up][i, t]+a[:q_bid][i, t]
        gradient[:R_IES_up][i, t]=dt*ies[i]["up_bid"][t]-a[:up][t]+a[:i_cap_up][i, t]+a[:iu_bid][
            i,
            t,
        ]
        gradient[:R_IES_down][i, t]=dt*ies[i]["down_bid"][t]-a[:down][t]+a[:i_cap_down][i, t]+a[:id_bid][
            i,
            t,
        ]
    end
    for (key, g) in gradient, i in axes(g, 1), t in axes(g, 2)
        record(
            "R5-MK_reduced_cost",
            "dual",
            string(key)*string(i),
            t,
            max(0.0, -g[i, t])/(dt*price_scale),
            "1",
            1e-6,
        )
        record(
            "R5-MK_variable_complementarity",
            "dual",
            string(key)*string(i),
            t,
            s[key][i, t]*g[i, t]/money_scale,
            "1",
            1e-6,
        )
        if haskey(r, "lower_bound_duals")
            bound=r5_market_matrix(r["lower_bound_duals"][string(key)], size(g, 1), T)[i, t]
            record(
                "R5-MK_stationarity",
                "dual",
                string(key)*string(i),
                t,
                (g[i, t]-bound)/(dt*price_scale),
                "1",
                1e-6,
            )
        end
    end
    # 独立按拉格朗日常数项重算对偶值；不使用求解器的对偶目标属性。
    dual=0.0
    for t in 1:T
        dual+=a[:energy][t]*sum(d["load_MW"][b][t] for b in 1:B)+a[:up][t]*d["reserve_up_MW"][t]+a[:down][t]*d["reserve_down_MW"][t]
        for g in 1:G
            x=gen[g]
            dual+=-a[:g_cap_up][g, t]*x["p_max"]+a[:g_cap_down][g, t]*x["p_min"] -
                  a[:pg_bid][g, t]*x["p_bid_max"] - a[:gu_bid][g, t]*x["up_max"]-a[:gd_bid][g, t]*x["down_max"] -
                  dt*(a[:ramp_up][g, t]*x["ramp_up_MW_h"]+a[:ramp_down][g, t]*x["ramp_down_MW_h"])
            t==1 && (dual-=(a[:ramp_up][g, 1]-a[:ramp_down][g, 1])*x["p_initial"])
        end
        for i in 1:I
            x=ies[i]
            dual+=a[:i_cap_up][i, t]*x["q_min"]-a[:i_cap_down][i, t]*x["q_max"] -
                  a[:q_bid][i, t]*x["purchase_bid_max"]-a[:iu_bid][i, t]*x["up_max"] -
                  a[:id_bid][i, t]*x["down_max"]
        end
        for l in 1:L
            delta=a[:line_up][l, t]-a[:line_down][l, t]
            dual-=delta*sum(d["network"]["ptdf"][l][b]*d["load_MW"][b][t] for b in 1:B) +
                  (a[:line_up][l, t]+a[:line_down][l, t])*d["network"]["limit_MW"][l]
        end
    end
    gap=abs(obj-dual)/max(1.0, abs(obj))
    record("R5-MK_gap", "dual", "all", 0, gap, "1", 1e-4)
    raw_pass=false
    if haskey(r, "raw_duals")
        raw_pass=true
        for (key, mul) in a
            raw=r["raw_duals"][string(key)]
            raw_array=key in (:energy, :up, :down) ? Float64.(raw) :
                      r5_market_matrix(raw, size(mul, 1), T)
            sign=key in (:g_cap_down, :i_cap_up) ? 1.0 : -1.0
            raw_pass &= maximum(abs.(mul-sign*raw_array); init = 0.0)<=1e-12
        end
        record("R5-MK_MOI_conversion", "dual", "all", 0, raw_pass ? 0.0 : Inf, "1", 1e-12)
    end
    complete_duals=haskey(r, "raw_duals")&&haskey(r, "lower_bound_duals")&&raw_pass
    kkt=complete_duals&&all(x["pass"] for x in rows if x["scope"]=="dual")
    output["dual_record_complete"]=complete_duals
    output["kkt_pass"]=model_pass&&kkt
    output["optimality_pass"]=model_pass&&kkt&&gap<=1e-4
    output["dual_value"]=dual
    output["relative_gap"]=gap
    output["LMP_USD_MWh"]=r5_market_rows(lmps)
    output["reserve_up_price"]=a[:up] ./ dt
    output["reserve_down_price"]=a[:down] ./ dt
    output["status"]="primal_dual_evaluated"
    output
end
