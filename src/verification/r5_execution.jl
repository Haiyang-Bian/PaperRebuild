const R5_EXECUTION_VERIFY_FILE = @__FILE__

function r5_execution_qp_check(w)
    out = Dict{String,Any}("pass"=>false, "rows"=>Dict{String,Any}[])
    all(haskey(w, k) for k in ("system", "x", "raw_duals", "solver_objective")) || return out
    sys, x, raw = w["system"], w["x"], w["raw_duals"]
    h, rows = sys["h"], sys["rows"]
    n = length(h)
    length(x)==n && length(raw)==length(rows) && all(isfinite, vcat(x, raw, h)) && all(>(0), h) ||
        return out
    rec(id, v) = r5_risk_record!(out, id, "selector_KKT", v, 1e-6)
    gradient, contributions = h .* x, abs.(h .* x)
    atmu = zeros(n)
    constant_dual = 0.0
    for (i, row) in enumerate(rows)
        a, c0 = row["a"], row["constant"]
        length(a)==n && all(isfinite, a) && isfinite(c0) || return out
        μ = row["moi_to_multiplier"]*raw[i]
        value = sum(a .* x)+c0
        scale = max(1.0, abs(c0), sum(abs.(a .* x)))
        rec("primal/$i", (row["equality"] ? abs(value) : max(0.0, value))/scale)
        if !row["equality"]
            rec("dual/$i", max(0.0, -μ)/max(1.0, abs(μ)))
            rec("complementarity/$i", μ*value/max(1.0, abs(μ)*scale))
        end
        gradient .+= μ .* a
        contributions .+= abs.(μ .* a)
        atmu .+= μ .* a
        constant_dual += μ*c0
    end
    rec("stationarity", maximum(abs.(gradient) ./ max.(1.0, contributions)))
    primal = 0.5*sum(h .* x .^ 2)
    # R5-EX3：正定对角H使拉格朗日函数的无约束下确界可直接求得。
    dual_value = constant_dual-0.5*sum(atmu .^ 2 ./ h)
    rec("gap", (primal-dual_value)/max(1.0, abs(primal), abs(dual_value)))
    rec("objective", (w["solver_objective"]-primal)/max(1.0, abs(primal)))
    out["primal_objective"], out["dual_objective"] = primal, dual_value
    out["pass"] = all(r["pass"] for r in out["rows"])
    out
end

"""
    validate_r5_market_execution(case, result)

重验保存的原市场见证、两个选择QP的原始MOI乘子和唯一性条件，以及最终市场原KKT/支付。
选择QP的乘子不能当作原市场价格；原市场乘子来自显式对偶最优面的优化变量。
只重建确定的仿射系数作身份比较，不重新求解；A1/A2/KKT门槛不变。
"""
function validate_r5_market_execution(c::R5MarketCase, r)
    r["case_sha256"] == c.sha256 || error("执行结果输入不匹配")
    spec = r5_execution_spec(r["spec"])
    out = Dict{String,Any}(
        "execution_pass"=>false,
        "market_pass"=>false,
        "selector_pass"=>false,
        "status"=>"incomplete",
    )
    haskey(r, "primary") || return out
    v = validate_r5_market(c, r["primary"])
    out["primary"] = v
    r5_execution_market_certified(v) || return out
    for kind in (:primal, :dual)
        stage = get(r, string(kind), Dict())
        haskey(stage, "witness") || return out
        b = build_r5_execution_selector(c, v["clearing_objective"]; kind, spec)
        expected = r5_execution_qp_system(b)
        r5_execution_hash(expected) == r5_execution_hash(stage["witness"]["system"]) ||
            error("选择QP系数被修改")
        check = r5_execution_qp_check(stage["witness"])
        out[string(kind)] = check
        stage["status"] == "solver_optimal" && check["pass"] || return out
    end
    out["selector_pass"] = true
    haskey(r, "market") || return out
    chosen = r["market"]
    haskey(chosen, "raw_duals") && error("选择QP的乘子不得伪装成原市场MOI对偶")
    # 核验市场值确实来自两个唯一选择结果，而非替换成其他福利最优解。
    for (kind, field) in ((:primal, "values"), (:dual, "multipliers"))
        b = build_r5_execution_selector(c, v["clearing_objective"]; kind, spec)
        values_by_name = Dict(
            zip(
                r[kind == :primal ? "primal" : "dual"]["witness"]["system"]["names"],
                r[string(kind)]["witness"]["x"],
            ),
        )
        expected = Dict(
            string(k) => (
                ndims(a)==1 ? [values_by_name[name(v)] for v in a] :
                r5_market_rows(map(v->values_by_name[name(v)], a))
            ) for (k, a) in pairs(b.base.variables)
        )
        r5_execution_hash(expected) == r5_execution_hash(chosen[field]) ||
            error("执行市场没有使用所选值")
    end
    vm = validate_r5_market(c, chosen)
    payment = r5_market_payment_identity(c, chosen)
    out["market"], out["payment"] = vm, payment
    out["market_pass"] =
        r5_execution_market_certified(vm) &&
        payment["identity_pass"] &&
        abs(vm["clearing_objective"]-v["clearing_objective"]) <=
        1e-6*max(1.0, abs(v["clearing_objective"]))
    out["execution_pass"] = out["market_pass"] && out["selector_pass"]
    out["status"] = "evaluated"
    out
end

"""
    validate_r5_execution_delivery(strategic_case, market_case, market_result, result)

核查固定的实际市场成交与补救共同承诺逐时相等，独立回算全部采用物理/风险关系及总费用。
市场净支付是固定常数；补救的条件最优界不能作为新执行规则下策略报价的全局界。
无候选、模型通过、风险通过及费用完成分别报告，不用弹性调度替代交付。
"""
function validate_r5_execution_delivery(c::R5StrategicCase, mc::R5MarketCase, market, r)
    x = r5_execution_awards(c, mc, market)
    r["case_sha256"] == c.sha256 && r["market_case_sha256"] == mc.sha256 ||
        error("交付输入身份不同")
    r["market_witness_sha256"] == r5_execution_hash(market) || error("市场见证改变")
    r["awards"] == x || error("交付评价替换了成交量")
    out =
        Dict{String,Any}("delivery_pass"=>false, "cost_complete"=>false, "rows"=>Dict{String,Any}[])
    haskey(r, "risk") || return out
    rr = r["risk"]
    v = validate_r5_risk(R5RiskCase(c.data["risk"]), rr)
    out["risk"] = v
    haskey(rr, "first_stage") || return out
    for k in R5_COMMITMENT_KEYS
        r5_risk_record!(
            out,
            k,
            "fixed_awards",
            maximum(abs.(rr["first_stage"][k]-x[k])),
            1e-6*(1+maximum(abs.(x[k])));
            unit = "MW",
        )
    end
    payment = r5_market_payment_identity(mc, market)
    out["delivery_pass"] =
        v["model_pass"] &&
        v["risk_pass"] &&
        payment["identity_pass"] &&
        all(row["pass"] for row in out["rows"])
    out["cost_complete"] =
        out["delivery_pass"] && v["optimality_pass"] && rr["status"] == "solver_optimal"
    out["payment_USD"] = payment["direct_payment_USD"]
    if haskey(v, "worst_net_cost")
        out["worst_recourse_USD"] = v["worst_net_cost"]
        out["total_cost_USD"] = out["payment_USD"]+v["worst_net_cost"]
    end
    out["bound_scope"] = "fixed_bids_and_executed_awards_only"
    out
end
