const R5_MARKET_SELECTION_FILE = @__FILE__

function r5_market_fixed_payment(c, s, a)
    d = c.data
    _, I, _, L, T = r5_market_sizes(c)
    sum(
        (
            a[:energy][t]-sum(
                d["network"]["ptdf"][l][d["ies"][i]["node"]] *
                (a[:line_up][l, t]-a[:line_down][l, t]) for l in 1:L;
                init = 0.0,
            )
        )*s[:P_IES][i, t] - a[:up][t]*s[:R_IES_up][i, t] - a[:down][t]*s[:R_IES_down][i, t] for
        i in 1:I, t in 1:T;
        init = 0.0,
    )
end

"""
    r5_market_settlement_range(case, market_result; optimizer, budget_sec=60)

固定已认证的报价及全部成交量，在下层对偶最优面上分别求IES净支付最小/最大值。
原问题最优值作为强对偶等式；不设置价格限幅，不调整成交量，不重新优化IES补救。
返回两端完整乘子见证和原市场数值检查；价格区间为无界/未决时保留真实状态。
两个LP共享预算；本检查只解释给定成交下的结算不唯一，不认证悲观双层最优决策。
"""
function r5_market_settlement_range(c::R5MarketCase, r; optimizer, budget_sec = 60.0)
    isfinite(budget_sec) && budget_sec>0 || error("结算范围预算错误")
    check = validate_r5_market(c, r)
    check["model_pass"] && haskey(check, "relative_gap") && all(x["pass"] for x in check["rows"]) ||
        error("结算范围需要可信原/对偶最优见证")
    start = time()
    deadline = start+budget_sec
    out = Dict{String,Any}(
        "schema"=>"r5-market-selection-v1",
        "case_sha256"=>c.sha256,
        "parent_run_id"=>r["run_id"],
        "scope"=>"fixed_all_primal_quantities",
        "budget_sec"=>Float64(budget_sec),
        "endpoints"=>Dict{String,Any}(),
        "source_hashes_at_solve"=>Dict(
            "src/algorithms/r5_market_selection.jl" =>
                bytes2hex(sha256(read(R5_MARKET_SELECTION_FILE))),
        ),
    )
    s = r5_market_values(c, r["values"])
    out["primal_sha256"] = bytes2hex(sha256(r5_market_text(r["values"])))
    for side in ("minimum", "maximum")
        time()<deadline || break
        e = Dict{String,Any}()
        out["endpoints"][side] = e
        try
            b = build_r5_market_dual(c; optimizer)
            @constraint(b.model, objective_function(b.model) == check["clearing_objective"])
            payment = r5_market_fixed_payment(c, s, b.variables)
            @objective(b.model, Min, (side=="minimum" ? 1.0 : -1.0)*payment)
            merge!(e, r5_risk_optimize!(b.model, deadline))
            if e["has_candidate"]
                e["payment_USD"] = value(payment)
                trial = deepcopy(r)
                trial["multipliers"] = Dict(
                    string(k)=>(ndims(v)==1 ? value.(v) : r5_market_rows(value.(v))) for
                    (k, v) in b.variables
                )
                pop!(trial, "raw_duals", nothing)
                pop!(trial, "lower_bound_duals", nothing)
                trial["multiplier_source"] = "optimized_dual_optimal_face"
                e["market_witness"] = trial
                e["validation"] = r5_market_selection_endpoint(c, r, e, side)
            end
        catch err
            r5_risk_exception!(e, err)
        end
    end
    out["elapsed_sec"] = time()-start
    out["range_complete"] =
        length(out["endpoints"])==2 && all(
            get(e, "status", "")=="solver_optimal" &&
            get(get(e, "validation", Dict()), "pass", false) for e in values(out["endpoints"])
        )
    if out["range_complete"]
        out["payment_width_USD"] =
            out["endpoints"]["maximum"]["payment_USD"] - out["endpoints"]["minimum"]["payment_USD"]
    end
    out
end

function r5_market_selection_endpoint(c, parent, e, side)
    w = e["market_witness"]
    w["values"] == parent["values"] || error("结算范围改变了成交量")
    w["solver_objective"] == parent["solver_objective"] || error("结算范围改变了下层目标")
    haskey(w, "raw_duals") && error("最优面变量不得伪造市场原始乘子")
    v = validate_r5_market(c, w)
    p = r5_market_payment_identity(c, w)
    value = p["direct_payment_USD"]
    sign = side=="minimum" ? 1.0 : -1.0
    tol = 1e-6*max(1.0, abs(value))
    bound = get(e, "solver_objective_bound", NaN)
    pass =
        v["model_pass"] &&
        all(x["pass"] for x in v["rows"]) &&
        p["identity_pass"] &&
        abs(e["payment_USD"]-value)<=tol &&
        abs(e["solver_objective"]-sign*value)<=tol &&
        isfinite(bound) &&
        bound<=sign*value+tol &&
        abs(sign*value-bound)/max(1.0, abs(value), abs(bound))<=1e-4
    Dict{String,Any}("pass"=>pass, "market"=>v, "payment"=>p)
end
