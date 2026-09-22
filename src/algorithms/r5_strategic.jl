const R5_STRATEGIC_SOLVE_FILE = @__FILE__

function r5_strategic_selected_market(c, b, run_id)
    bid = Dict(k=>value.(v) for (k, v) in b.market.bids)
    mc = r5_strategic_market_case(c, bid)
    r = Dict{String,Any}(
        "schema"=>"r5-market-result-v1",
        "version"=>"r5_market_clearing_checked_v1",
        "run_id"=>run_id*"/selected-market",
        "case_sha256"=>mc.sha256,
        "status"=>"selected_lower_optimum",
        "multiplier_source"=>"optimized_KKT_variables",
        "objective_source"=>"recomputed_selected_lower_objective",
        "solver_objective"=>0.0,
        "values"=>Dict(string(k)=>r5_market_rows(value.(v)) for (k, v) in b.market.variables),
        "multipliers"=>Dict(
            string(k)=>(ndims(v)==1 ? value.(v) : r5_market_rows(value.(v))) for
            (k, v) in b.market.multipliers
        ),
        "lower_bound_duals"=>Dict(
            string(k)=>r5_market_rows(value.(v)) for (k, v) in b.market.lower
        ),
    )
    # 此下层值是从选定报价和成交量重算，不是上层求解器的目标，也不复用上层的界。
    r["solver_objective"] = validate_r5_market(mc, r)["clearing_objective"]
    (; bids = bid, case = mc, result = r)
end

function r5_strategic_risk_policy(c, b, run_id)
    q = b.risk
    x = Dict(k=>value.(v) for (k, v) in q.base.first_stage)
    r = Dict{String,Any}(
        "schema"=>"r5-risk-result-v1",
        "version"=>"r5_finite_support_checked_v1",
        "case_sha256"=>R5RiskCase(c.data["risk"]).sha256,
        "run_id"=>run_id*"/risk",
        "method"=>"embedded_strategic_policy",
        "status"=>"embedded_strategic_policy",
        "commitment_source"=>"selected_market_awards",
        "solver_objective"=>value(q.duals["cost"].objective),
        "first_stage"=>x,
        "z"=>value.(q.z),
        "embedded_duals"=>Dict(
            k=>Dict("lambda"=>value(v.lambda), "nu"=>value.(v.nu)) for (k, v) in q.duals
        ),
        "scenarios"=>Dict{String,Any}(),
        "oracles"=>Dict{String,Any}(),
    )
    for (i, s) in enumerate(q.physical.data["scenarios"])
        id = s["id"]
        view = r5_commitment_view(q.physical, s, x)
        sys = q.base.systems[id]
        r["scenarios"][id] = Dict{String,Any}(
            "schema"=>"r5-dispatch-result-v1",
            "version"=>"r5_dispatch_checked_v1",
            "case_sha256"=>view.sha256,
            "run_id"=>r["run_id"]*"/"*id,
            "status"=>"embedded_strategic_policy",
            "solver_objective"=>value(q.q[i]),
            "values"=>Dict(
                k=>[
                    [value(q.base.variables[id]["$k/$j/$t"]) for t in 1:view.data["T"]] for j in 1:n
                ] for (k, n) in sys.sizes
            ),
        )
    end
    q.pattern===nothing || (r["pattern"]=q.pattern)
    r
end

"""
    solve_r5_strategic(case; optimizer, oracle_optimizer, budget_sec=600,
                       risk_pattern=nothing, complementarity_pattern=nothing)

连续报价、乐观下层KKT和风险补救联合求解；建模、MPEC、独立市场和三个运输对手共享预算。
主求解最多使用90%时间（600秒时最多540秒），余下用于独立认证，不自动切换算法或注入参考解。
SOS1需支持该类型的求解器；固定全部互补/舒适分支可用开放LP，界只适用于该分支。
未完成独立验算时保留候选和未决状态，不把求解器OPTIMAL单独视为科学验收成功。
"""
function solve_r5_strategic(
    c::R5StrategicCase;
    optimizer,
    oracle_optimizer,
    budget_sec = 600.0,
    risk_pattern = nothing,
    complementarity_pattern = nothing,
)
    isfinite(budget_sec) && budget_sec>0 || error("策略预算须有限正数")
    r5_strategic_assert_case(c)
    start = time()
    deadline = start+budget_sec
    r = Dict{String,Any}(
        "schema"=>"r5-strategic-result-v1",
        "version"=>"r5_strategic_checked_v1",
        "run_id"=>"r5-strategic-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "source_hashes_at_solve"=>r5_strategic_science_hashes(),
        "selection"=>c.data["selection"],
        "budget_sec"=>Float64(budget_sec),
        "objective_type"=>"market_net_payment_plus_worst_recourse",
        "has_candidate"=>false,
    )
    risk_pattern===nothing ||
        (r["risk_pattern"]=r5_risk_pattern(R5RiskCase(c.data["risk"]), risk_pattern))
    complementarity_pattern===nothing ||
        (r["complementarity_pattern"]=deepcopy(complementarity_pattern))
    try
        b = build_r5_strategic(c; optimizer, risk_pattern, complementarity_pattern)
        r["model_type"], r["model_types"] = b.model_type, b.model_types
        r["complementarity_count"] = length(b.market.pairs)
        merge!(r, r5_risk_optimize!(b.model, start+0.9*budget_sec))
        if r["has_candidate"]
            selected = r5_strategic_selected_market(c, b, r["run_id"])
            r["bids"], r["selected_market"] = selected.bids, selected.result
            r["risk_policy"] = r5_strategic_risk_policy(c, b, r["run_id"])
            # 独立市场不固定选定成交或乘子，检查最优值相同而非强行价格/成交相同。
            remaining = deadline-time()
            if remaining>0
                r["independent_market"] = solve_r5_market(
                    selected.case;
                    optimizer = oracle_optimizer,
                    budget_sec = remaining,
                )
            end
            rc = R5RiskCase(c.data["risk"])
            policy = r5_risk_policy(rc, r["risk_policy"])
            p = [s["probability"] for s in rc.data["commitment"]["scenarios"]]
            for (label, score) in (
                ("cost", policy.costs),
                ("risk", Float64.(round.(Int, r["risk_policy"]["z"]))),
                ("actual", Float64.(policy.events)),
            )
                remaining = deadline-time()
                remaining>0 || break
                r["risk_policy"]["oracles"][label] = r5_worst_distribution(
                    p,
                    rc.data["ambiguity"]["distance"],
                    score,
                    rc.data["ambiguity"]["radius"];
                    optimizer = oracle_optimizer,
                    budget_sec = remaining,
                    quantity = label=="cost" ? :cost : :probability,
                )
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r["validation"] = validate_r5_strategic(c, r)
    r["cost_optimization_complete"] =
        r["status"]=="solver_optimal" && r["validation"]["optimality_pass"]
    r["elapsed_sec"] = time()-start
    r["source_hashes_at_solve"] == r5_strategic_science_hashes() || error("策略求解期间源码变化")
    r
end
