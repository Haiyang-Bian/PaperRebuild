const R5_EXECUTION_SOLVE_FILE = @__FILE__

"""
    solve_r5_market_execution(case; lp_optimizer, qp_optimizer,
                              spec=R5MarketExecutionSpec(), budget_sec=600)

先独立出清固定报价LP，再顺序选择唯一的最小范数成交与对偶价格。
建模、三次求解及验算共享截止时间；任何一层未认证都保留失败，不换用有利的旧成交。
返回的market是优化选出的原市场乘子，不伪造市场原始MOI对偶。
此接口只执行给定报价，不重新优化领导者报价。
"""
function solve_r5_market_execution(
    c::R5MarketCase;
    lp_optimizer,
    qp_optimizer,
    spec = R5MarketExecutionSpec(),
    budget_sec = 600.0,
)
    isfinite(budget_sec) && budget_sec>0 || error("执行预算必须有限正数")
    start = time()
    deadline = start+budget_sec
    r = Dict{String,Any}(
        "schema"=>"r5-execution-result-v1",
        "kind"=>"market_execution",
        "version"=>"r5_execution_min_norm_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-execution-"*string(uuid4()),
        "spec"=>r5_execution_spec(spec),
        "budget_sec"=>Float64(budget_sec),
        "status"=>"not_started",
        "created_utc"=>string(now(UTC)),
        "source_hashes_at_solve"=>r5_execution_science_hashes(),
    )
    try
        r["primary"] = solve_r5_market(c; optimizer = lp_optimizer, budget_sec = 0.2*budget_sec)
        primary = validate_r5_market(c, r["primary"])
        if !r5_execution_market_certified(primary)
            r["status"] = "primary_"*r["primary"]["status"]
        else
            r["status"] = "selectors_incomplete"
            built = Dict{Symbol,Any}()
            for (kind, fraction) in ((:primal, 0.55), (:dual, 0.9))
                b = build_r5_execution_selector(
                    c,
                    primary["clearing_objective"];
                    kind,
                    optimizer = qp_optimizer,
                    spec,
                )
                built[kind] = b
                stage = r5_risk_optimize!(b.model, min(deadline, start+fraction*budget_sec))
                r[string(kind)] = stage
                if stage["has_candidate"]
                    stage["witness"] = r5_execution_qp_witness(b)
                    stage["validation"] = r5_execution_qp_check(stage["witness"])
                end
                if stage["status"] != "solver_optimal" ||
                   !get(get(stage, "validation", Dict()), "pass", false)
                    r["status"] = string(kind)*"_uncertified"
                    break
                end
            end
            if all(
                haskey(r, k) && get(get(r[k], "validation", Dict()), "pass", false) for
                k in ("primal", "dual")
            )
                p, d = built[:primal], built[:dual]
                r["market"] = Dict{String,Any}(
                    "schema"=>"r5-market-result-v1",
                    "version"=>"r5_market_clearing_checked_v1",
                    "case_sha256"=>c.sha256,
                    "run_id"=>r["run_id"]*"/market",
                    "status"=>"unique_minimum_norm_market_selection",
                    "solver_objective"=>primary["clearing_objective"],
                    "multiplier_source"=>"optimized_minimum_norm_dual_face",
                    "values"=>Dict(
                        string(k)=>r5_market_rows(value.(a)) for (k, a) in pairs(p.base.variables)
                    ),
                    "multipliers"=>Dict(
                        string(k)=>(ndims(a)==1 ? value.(a) : r5_market_rows(value.(a))) for
                        (k, a) in d.base.variables
                    ),
                )
                r["status"] = "selection_solved"
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r["validation"] = validate_r5_market_execution(c, r)
    r["elapsed_sec"] = time()-start
    r["source_hashes_at_solve"]==r5_execution_science_hashes() || error("执行期间源码变化")
    r
end

"""
    evaluate_r5_execution_delivery(strategic_case, market_case, market_result;
                                   optimizer, oracle_optimizer, budget_sec=600)

冻结给定市场的真实成交量，重新求解既有有限支持风险补救，检查能否实际交付。
不改变报价、成交、设备、历史或风险上限。保留原变量上下界，追加等式而非force-fix删除界。
返回的最优界仅属于该成交下的条件补救，市场支付另作常数计入；不是策略重优化。
"""
function evaluate_r5_execution_delivery(
    c::R5StrategicCase,
    mc::R5MarketCase,
    market;
    optimizer,
    oracle_optimizer,
    budget_sec = 600.0,
)
    isfinite(budget_sec) && budget_sec>0 || error("交付预算必须有限正数")
    start = time()
    deadline = start+budget_sec
    awards = r5_execution_awards(c, mc, market)
    rc = R5RiskCase(c.data["risk"])
    r = Dict{String,Any}(
        "schema"=>"r5-execution-result-v1",
        "kind"=>"fixed_award_delivery",
        "version"=>"r5_execution_delivery_v1",
        "case_sha256"=>c.sha256,
        "market_case_sha256"=>mc.sha256,
        "market_witness_sha256"=>r5_execution_hash(market),
        "awards"=>awards,
        "run_id"=>"r5-delivery-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r5_execution_science_hashes(),
        "status"=>"not_started",
    )
    try
        b = build_r5_risk(rc; optimizer)
        for k in R5_COMMITMENT_KEYS, t in eachindex(awards[k])
            # R5-EX4：保留原始容量界，成交超过可交付容量应导致不可行。
            @constraint(b.model, b.base.first_stage[k][t]==awards[k][t])
        end
        status = r5_risk_optimize!(b.model, start+0.85*budget_sec)
        r["status"] = status["status"]
        rr = Dict{String,Any}(
            "schema"=>"r5-risk-result-v1",
            "case_sha256"=>rc.sha256,
            "version"=>"r5_finite_support_checked_v1",
            "run_id"=>r["run_id"]*"/risk",
            "method"=>"fixed_executed_awards",
        )
        if status["has_candidate"]
            rr = r5_strategic_risk_policy(c, (; risk = b), r["run_id"])
            rr["method"] = "fixed_executed_awards"
            rr["commitment_source"] = "fixed_executed_market_awards"
            policy = r5_risk_policy(rc, rr)
            p = [s["probability"] for s in rc.data["commitment"]["scenarios"]]
            for (label, score) in (
                ("cost", policy.costs),
                ("risk", Float64.(round.(Int, rr["z"]))),
                ("actual", Float64.(policy.events)),
            )
                remaining = deadline-time()
                remaining>0 || break
                rr["oracles"][label] = r5_worst_distribution(
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
        merge!(rr, status)
        r["risk"] = rr
    catch err
        r5_risk_exception!(r, err)
    end
    r["validation"] = validate_r5_execution_delivery(c, mc, market, r)
    r["elapsed_sec"] = time()-start
    r["source_hashes_at_solve"]==r5_execution_science_hashes() || error("交付评价期间源码变化")
    r
end
