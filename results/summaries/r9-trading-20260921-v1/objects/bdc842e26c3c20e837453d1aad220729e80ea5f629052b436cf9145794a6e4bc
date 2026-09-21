const R5_STRATEGIC_BENDERS_VERIFY_FILE = @__FILE__

function r5_strategic_benders_market_check(c, r, pattern)
    out = Dict{String,Any}("pass"=>false, "rows"=>Dict{String,Any}[])
    all(haskey(r, k) for k in ("bids", "selected_market", "first_stage")) || return out
    chosen = r["selected_market"]
    get(chosen, "multiplier_source", "") == "optimized_KKT_variables" &&
    !haskey(chosen, "raw_duals") || error("市场选择乘子不得冒充求解器原始对偶")
    mc = r5_strategic_market_case(c, r["bids"])
    cv = validate_r5_market(mc, chosen)
    out["selected_market"] = cv
    selected_pass =
        cv["model_pass"] &&
        haskey(chosen, "lower_bound_duals") &&
        haskey(cv, "relative_gap") &&
        all(row["pass"] for row in cv["rows"] if row["scope"] == "dual")
    rec(id, kind, v, tol = 1e-6) = r5_benders_record!(out["rows"], id, kind, v, tol)
    for key in R5_STRATEGIC_BIDS, t in 1:mc.data["T"]
        b = c.data["bid_bounds"][key]
        rec(
            "$key/$t",
            "bid",
            max(0.0, b["lower"][t]-r["bids"][key][t], r["bids"][key][t]-b["upper"][t]) /
            max(1.0, b["upper"][t]),
        )
    end
    if pattern !== nothing
        pairs = r5_strategic_pair_values(mc, chosen, cv)
        Set(keys(pairs)) == Set(keys(pattern)) || error("市场分支清单不符")
        for (id, bit) in pattern
            μ, slack = pairs[id]
            scale = bit == 0 ? mc.data["dt_h"]*cv["price_scale_USD_MWh"] : 1+cv["power_scale_MW"]
            rec(id, "fixed_complementarity", (bit == 0 ? μ : slack)/scale)
        end
    end
    for (key, marketkey) in
        (("P_DA_MW", "P_IES"), ("R_up_MW", "R_IES_up"), ("R_down_MW", "R_IES_down"))
        award = only(chosen["values"][marketkey])
        for t in 1:mc.data["T"]
            rec(
                "$key/$t",
                "bridge",
                award[t]-r["first_stage"][key][t],
                1e-6*(1+max(1.0, mc.data["ies"][1]["q_max"])),
            )
        end
    end
    out["payment"] = r5_market_payment_identity(mc, chosen)
    out["selected_kkt_pass"] = selected_pass
    out["pass"] =
        selected_pass && out["payment"]["identity_pass"] && all(x["pass"] for x in out["rows"])
    out
end

function r5_strategic_benders_master_check(c, spec, r, cuts, pattern)
    r["bound_scope"] == r5_strategic_benders_scope(r["scope"], pattern) ||
        error("市场主问题界作用域变化")
    out = Dict{String,Any}("pass"=>false, "bound_valid"=>false, "rows"=>Dict{String,Any}[])
    rc = R5RiskCase(c.data["risk"])
    if !get(r, "has_candidate", false)
        out["risk_master"] = r5_benders_master_check(rc, spec, r, cuts)
        return out
    end
    market = r5_strategic_benders_market_check(c, r, pattern)
    out["market"] = market
    payment = market["payment"]["affine_payment_USD"]
    # 只构造分项验算视图；不改存档目标，不把完整主问题界冒充补救费用界。
    component = copy(r)
    component["solver_objective"] = r["solver_objective"] - payment
    pop!(component, "solver_objective_bound", nothing)
    pop!(component, "bound_source", nothing)
    v = r5_benders_master_check(rc, spec, component, cuts)
    out["risk_master"] = v
    total = payment + v["objective_recomputed"]
    out["objective_recomputed"] = total
    out["payment_USD"] = market["payment"]["direct_payment_USD"]
    out["recourse_epigraph_USD"] = v["objective_recomputed"]
    out["component_view_source"] = "algebraic_decomposition_not_new_solver_certificate"
    r5_benders_record!(
        out["rows"],
        "master/total",
        "objective",
        (r["solver_objective"]-total)/max(1.0, abs(total)),
        1e-6,
    )
    out["pass"] = v["pass"] && market["pass"] && all(x["pass"] for x in out["rows"])
    bound = get(r, "solver_objective_bound", NaN)
    out["bound_valid"] =
        out["pass"] &&
        isfinite(bound) &&
        get(r, "bound_source", "") in ("MOI.ObjectiveBound", "MOI.DualObjectiveValue") &&
        bound <= total+1e-6*max(1.0, abs(total))
    out
end

function r5_strategic_benders_candidate_check(c, candidate, sources, pattern)
    rc = R5RiskCase(c.data["risk"])
    risk = candidate["risk_candidate"]
    rv = r5_benders_candidate_check(rc, risk, sources)
    r5_risk_validation_text(rv) == r5_risk_validation_text(risk["validation"]) ||
        error("候选补救原验算变化")
    policy = r5_benders_policy_view(rc, risk, sources)
    if !haskey(policy, "solver_objective")
        return Dict{String,Any}(
            "model_pass"=>false,
            "risk_pass"=>false,
            "cost_pass"=>false,
            "independent_market_kkt_pass"=>false,
            "status"=>"missing_transport_certificate",
        )
    end
    market = r5_strategic_market_case(c, candidate["bids"])
    pay = r5_market_payment_identity(market, candidate["selected_market"])
    view = Dict{String,Any}(
        "case_sha256"=>c.sha256,
        "bids"=>candidate["bids"],
        "selected_market"=>candidate["selected_market"],
        "risk_policy"=>policy,
        "solver_objective"=>pay["affine_payment_USD"]+policy["solver_objective"],
    )
    pattern === nothing || (view["complementarity_pattern"] = pattern)
    haskey(candidate, "independent_market") &&
        (view["independent_market"] = candidate["independent_market"])
    v = validate_r5_strategic(c, view)
    v["objective_source"] = "evaluated_market_payment_and_recourse_not_master_epigraph"
    # 无完整主问题界注入此候选视图；全局间隙由外层按声明域单独判断。
    v
end

"""
    validate_r5_strategic_benders(case, result)

只读重验连续报价分解的全部市场KKT、成交桥接、情景对偶、条件割、运输证书与历史上下界。
最优候选按市场支付加最坏补救费选择，不能按补救费单项选择；原始求解目标和界不被改写。
R5-SB2/SB3分别限定割和上下界。固定互补分支与原5-102受限舒适域均不认证完整乐观MPEC。
松弛主问题无界不能推出完整模型无界；历史负结果与缺失证据保持明确状态。
"""
function validate_r5_strategic_benders(c::R5StrategicCase, r)
    r5_strategic_assert_case(c)
    r["case_sha256"] == c.sha256 &&
    r["schema"] == "r5-strategic-benders-result-v1" &&
    r["version"] == "r5_strategic_benders_checked_v1" || error("策略分解身份或版本变化")
    r["selection"] == c.data["selection"] &&
    r["objective_type"] == "market_net_payment_plus_worst_recourse" ||
        error("不得改变策略选择制度或私人费用口径")
    r5_strategic_benders_source_check(r)
    spec = r5_benders_spec(r["spec"])
    pattern = r5_strategic_benders_pattern(c, get(r, "complementarity_pattern", nothing))
    rc = R5RiskCase(c.data["risk"])
    sources, sc = r["subproblems"], rc.data["commitment"]["scenarios"]
    out = Dict{String,Any}(
        "model_pass"=>false,
        "risk_pass"=>false,
        "cost_pass"=>false,
        "independent_market_kkt_pass"=>false,
        "optimality_pass"=>false,
        "domain_optimality_pass"=>false,
        "stopping_pass"=>false,
        "restricted_stopping_pass"=>false,
        "evidence_pass"=>true,
        "subproblem_checks"=>Dict{String,Any}(),
        "iteration_checks"=>Dict{String,Any}[],
        "market_scope"=>pattern === nothing ? "full_optimistic_MPEC" :
                        "fixed_complementarity_domain",
    )
    for (id, src) in sources
        id == src["run_id"] &&
        src["case_sha256"] == rc.sha256 &&
        src["source_unchanged"] &&
        src["source_hashes_at_solve"] ==
        src["source_hashes_at_return"] ==
        r["subproblem_source_hashes"] || error("情景子问题来源不一致")
        v = validate_r5_benders_subproblem(rc, src)
        r5_risk_validation_text(v) == r5_risk_validation_text(src["validation"]) ||
            error("情景KKT历史判定变化")
        out["subproblem_checks"][id] = Dict(k=>v[k] for k in ("model_pass", "kkt_pass", "status"))
    end
    length(unique(r["cut_order"])) == length(r["cut_order"]) &&
    Set(r["cut_order"]) == Set(keys(r["cuts"])) || error("割清单改变")
    cuts = Dict{String,Any}()
    for id in r["cut_order"]
        haskey(sources, id) || error("割缺来源")
        cuts[id] = r5_benders_cut(rc, sources[id]; arithmetic = spec.cut_arithmetic)
        r5_market_text(cuts[id]) == r5_market_text(r["cuts"][id]) || error("条件割被修改")
    end
    accumulated, critical, used = String[], Int[], Set{String}()
    lower, restricted, best, selected = -Inf, -Inf, Inf, 0
    for (i, step) in enumerate(r["iterations"])
        step["iteration"] == i || error("策略分解迭代顺序变化")
        if !haskey(step, "master")
            out["evidence_pass"] = false
            continue
        end
        m = step["master"]
        m["critical"] == critical && m["cut_source_ids"] == accumulated ||
            error("主问题使用了未来或未声明的割/关键情景")
        mv =
            r5_strategic_benders_master_check(c, spec, m, [cuts[id] for id in accumulated], pattern)
        r5_risk_validation_text(mv) == r5_risk_validation_text(m["validation"]) ||
            error("主问题市场/支付/补救历史验算变化")
        if mv["bound_valid"]
            if m["scope"] == "full_risk_domain"
                lower = max(lower, m["solver_objective_bound"])
            else
                restricted = m["solver_objective_bound"]
            end
        else
            restricted = -Inf
        end
        get(m, "has_candidate", false) && (out["evidence_pass"] &= mv["pass"])
        for (kind, elastic) in (("cost_source_ids", false), ("diagnostic_source_ids", true)),
            (sid, id) in step[kind]

            s = findfirst(item->item["id"] == sid, sc)
            s === nothing && error("未知情景")
            src = sources[id]
            src["scenario"] == s &&
            src["elastic"] == elastic &&
            isequal(src["first_stage"], m["first_stage"]) &&
            src["branch"] == round(Int, m["z"][s]) || error("子问题与当前市场成交或舒适分支不一致")
            get(src, "numerical_scale", 1.0) == (elastic ? spec.diagnostic_scale : 1.0) ||
                error("子问题数值表示变化")
            if elastic
                sources[step["cost_source_ids"][sid]]["status"] == "solver_infeasible" ||
                    error("未证明条件不可行即启动诊断")
            end
            push!(used, id)
        end
        current_ids = Set(
            vcat(
                collect(values(step["cost_source_ids"])),
                collect(values(step["diagnostic_source_ids"])),
            ),
        )
        for id in step["new_cut_ids"]
            id in current_ids && id ∉ accumulated && haskey(cuts, id) ||
                error("新增割来源不属于当前轮")
            cuts[id]["productive"] || error("非分离诊断不能记为新有效割")
            spec.feasibility != :cuts &&
                cuts[id]["kind"] == "feasibility" &&
                error("关键路线暗中加入可行性割")
            push!(accumulated, id)
        end
        next = r5_benders_critical(rc, spec, step["critical_after"])
        ranking = Tuple{Float64,Int}[]
        if spec.feasibility != :cuts
            for (sid, id) in step["diagnostic_source_ids"]
                s = findfirst(item->item["id"] == sid, sc)
                s ∉ critical &&
                    out["subproblem_checks"][id]["kkt_pass"] &&
                    push!(ranking, (sources[id]["solver_objective"], s))
            end
        end
        sort!(ranking; by = x->(-x[1], x[2]))
        expected =
            sort(vcat(critical, [p[2] for p in Iterators.take(ranking, spec.critical_count)]))
        next == expected || error("关键情景没有按预定规则选择")
        cv = Dict{String,Any}()
        if haskey(step, "candidate")
            candidate = step["candidate"]
            q = candidate["risk_candidate"]
            isequal(q["first_stage"], m["first_stage"]) &&
            isequal(q["z"], m["z"]) &&
            q["source_ids"] == step["cost_source_ids"] &&
            r5_market_text(candidate["bids"]) == r5_market_text(m["bids"]) &&
            r5_market_text(candidate["selected_market"]) == r5_market_text(m["selected_market"]) ||
                error("候选市场或补救被替换")
            cv = r5_strategic_benders_candidate_check(c, candidate, sources, pattern)
            r5_risk_validation_text(cv) == r5_risk_validation_text(candidate["validation"]) ||
                error("完整候选历史核查变化")
            if r5_strategic_benders_candidate_pass(cv) && cv["worst_total_cost_USD"] < best
                best, selected = cv["worst_total_cost_USD"], i
            end
        end
        scope_lower = m["scope"] == "full_risk_domain" ? lower : restricted
        gap = r5_benders_gap(best, scope_lower, spec)
        haskey(step, "gap") &&
            r5_market_text(gap) != r5_market_text(step["gap"]) &&
            error("策略总费用间隙变化")
        push!(
            out["iteration_checks"],
            Dict(
                "iteration"=>i,
                "master_pass"=>mv["pass"],
                "bound_valid"=>mv["bound_valid"],
                "bound_scope"=>m["bound_scope"],
                "risk_scope"=>m["scope"],
                "lower_bound"=>scope_lower,
                "upper_bound"=>best,
                "gap"=>gap,
                "candidate_pass"=>!isempty(cv) && r5_strategic_benders_candidate_pass(cv),
            ),
        )
        critical = next
    end
    accumulated == r["cut_order"] && used == Set(keys(sources)) || error("来源不属于完整轨迹")
    get(r, "selected_iteration", 0) == selected || error("未按已认证总费用选择最佳候选")
    gap = r5_benders_gap(best, lower, spec)
    out["lower_bound"], out["upper_bound"], out["gap"] = lower, best, gap
    if selected > 0
        v = r5_strategic_benders_candidate_check(
            c,
            r["iterations"][selected]["candidate"],
            sources,
            pattern,
        )
        out["selected_iteration"], out["selected_validation"] = selected, v
        for k in ("model_pass", "risk_pass", "cost_pass", "independent_market_kkt_pass")
            out[k] = v[k]
        end
        out["domain_optimality_pass"] =
            out["evidence_pass"] && r5_strategic_benders_candidate_pass(v) && gap["a2_pass"]
        out["optimality_pass"] = out["domain_optimality_pass"] && pattern === nothing
        out["stopping_pass"] = out["domain_optimality_pass"] && gap["stopping_pass"]
        if !isempty(out["iteration_checks"])
            lastcheck = last(out["iteration_checks"])
            out["restricted_stopping_pass"] =
                out["evidence_pass"] &&
                lastcheck["risk_scope"] == "restricted_comfort_domain" &&
                lastcheck["gap"]["stopping_pass"]
        end
    end
    if r["status"] in ("declared_domain_infeasible", "restricted_domain_infeasible") ||
       startswith(r["status"], "master_relaxation_")
        !isempty(r["iterations"]) && haskey(last(r["iterations"]), "master") ||
            error("状态声明缺少原始主问题记录")
    end
    out["infeasibility_scope"] =
        r["status"] in ("declared_domain_infeasible", "restricted_domain_infeasible") ?
        last(r["iterations"])["master"]["bound_scope"] : "not_proved"
    out["unboundedness_scope"] =
        startswith(r["status"], "master_relaxation_") ?
        "master_relaxation_only_not_original_strategy" : "not_proved"
    if r["status"] in ("declared_domain_gap", "restricted_domain_gap")
        isempty(r["iterations"]) && error("无迭代却报告收敛")
        laststep = last(r["iterations"])
        expected =
            r["status"] == "declared_domain_gap" ? "full_risk_domain" : "restricted_comfort_domain"
        laststep["master"]["scope"] == expected &&
        laststep["master"]["critical"] == laststep["critical_after"] &&
        out["evidence_pass"] &&
        selected > 0 &&
        last(out["iteration_checks"])["gap"]["stopping_pass"] || error("收敛标签没有同域证据")
    elseif r["status"] in ("declared_domain_infeasible", "restricted_domain_infeasible")
        isempty(r["iterations"]) && error("无主问题却报告不可行")
        m = last(r["iterations"])["master"]
        expected =
            r["status"] == "declared_domain_infeasible" ? "full_risk_domain" :
            "restricted_comfort_domain"
        !m["has_candidate"] &&
        m["status"] == "solver_infeasible" &&
        m["scope"] == expected &&
        selected == 0 &&
        out["evidence_pass"] || error("不可行标签证据矛盾")
    elseif startswith(r["status"], "master_relaxation_")
        m = last(r["iterations"])["master"]
        !m["has_candidate"] &&
        m["status"] in ("DUAL_INFEASIBLE", "INFEASIBLE_OR_UNBOUNDED") &&
        r["status"] == "master_relaxation_"*m["status"] ||
            error("松弛无界/未消歧标签与原始求解状态不符")
    elseif r["status"] == "iteration_limit"
        length(r["iterations"]) == spec.max_iterations || error("未达到迭代上限")
    end
    out
end
