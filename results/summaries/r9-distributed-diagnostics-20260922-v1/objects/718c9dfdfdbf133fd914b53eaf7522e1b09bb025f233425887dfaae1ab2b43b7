const R5_STRATEGIC_BENDERS_SOLVE_FILE = @__FILE__

function r5_strategic_benders_master_result(c, b, deadline, run_id)
    r = r5_benders_master_result(b, deadline)
    r["bound_scope"] = b.bound_scope
    r["objective_type"] = "market_payment_plus_recourse_epigraph"
    if r["has_candidate"]
        selected = r5_strategic_selected_market(c, b, run_id)
        r["bids"], r["selected_market"] = selected.bids, selected.result
    end
    r
end

function r5_strategic_benders_evaluate(c, master, ids, sources, pattern; optimizer, deadline)
    candidate = Dict{String,Any}(
        "bids"=>deepcopy(master["bids"]),
        "selected_market"=>deepcopy(master["selected_market"]),
        "objective_type"=>"evaluated_market_payment_plus_worst_recourse",
    )
    candidate["risk_candidate"] =
        r5_benders_evaluate(R5RiskCase(c.data["risk"]), master, ids, sources; optimizer, deadline)
    remaining = deadline-time()
    if remaining > 0
        # 不固定上层选中的成交或价格，只独立检查同报价下的下层最优值。
        candidate["independent_market"] = solve_r5_market(
            r5_strategic_market_case(c, candidate["bids"]);
            optimizer,
            budget_sec = remaining,
        )
    end
    candidate["validation"] = r5_strategic_benders_candidate_check(c, candidate, sources, pattern)
    candidate
end

"""
    solve_r5_strategic_benders(case; optimizer, subproblem_optimizer=optimizer,
                               oracle_optimizer=subproblem_optimizer, spec=R5BendersSpec(),
                               budget_sec=600, complementarity_pattern=nothing)

执行连续报价、市场KKT与有限支持风险补救的条件分解。自空割/空关键集开始，不接受参考解注入；
每轮求完整市场主问题、逐情景LP/必要诊断及独立市场与运输对手，按总费用形成上下界。
默认有理保护割和1024倍等价诊断；cuts/critical/paper_critical的域差异按R5-SB3记录。
固定市场互补分支仅供开放测试并单列费用证书。全部建模与嵌套检查共用至多600秒、200轮。
初始松弛无界只报告主问题状态，不调用完整直接模型、截断价格或偷偷增加乘子上界。
"""
function solve_r5_strategic_benders(
    c::R5StrategicCase;
    optimizer,
    subproblem_optimizer = optimizer,
    oracle_optimizer = subproblem_optimizer,
    spec = R5BendersSpec(cut_arithmetic = :rational_box, diagnostic_scale = 1024.0),
    budget_sec = 600.0,
    complementarity_pattern = nothing,
)
    r5_strategic_assert_case(c)
    isfinite(budget_sec) && 0 < budget_sec <= 600 || error("策略分解总预算须为(0,600]秒")
    start = time()
    deadline = start+budget_sec
    pattern = r5_strategic_benders_pattern(c, complementarity_pattern)
    rc = R5RiskCase(c.data["risk"])
    r = Dict{String,Any}(
        "schema"=>"r5-strategic-benders-result-v1",
        "version"=>"r5_strategic_benders_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-strategic-benders-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "spec"=>r5_benders_spec(spec),
        "budget_sec"=>Float64(budget_sec),
        "selection"=>c.data["selection"],
        "objective_type"=>"market_net_payment_plus_worst_recourse",
        "source_hashes_at_solve"=>r5_strategic_benders_science_hashes(),
        "subproblem_source_hashes"=>r5_benders_science_hashes(),
        "iterations"=>Dict{String,Any}[],
        "subproblems"=>Dict{String,Any}(),
        "cuts"=>Dict{String,Any}(),
        "cut_order"=>String[],
        "status"=>"iteration_limit",
    )
    pattern === nothing || (r["complementarity_pattern"] = deepcopy(pattern))
    critical, seen = Int[], Set{String}()
    best, lower, selected = Inf, -Inf, 0
    sc = rc.data["commitment"]["scenarios"]
    function add_cut!(src, step)
        cut = r5_benders_cut(rc, src; arithmetic = spec.cut_arithmetic)
        key = r5_benders_cut_key(cut)
        key in seen && return false
        src["elastic"] && !cut["productive"] && return false
        push!(seen, key)
        id = src["run_id"]
        r["cuts"][id] = cut
        push!(r["cut_order"], id)
        push!(step["new_cut_ids"], id)
        true
    end
    try
        for iteration in 1:spec.max_iterations
            if time() >= deadline
                r["status"] = "budget_exhausted"
                break
            end
            step = Dict{String,Any}(
                "iteration"=>iteration,
                "new_cut_ids"=>String[],
                "critical_after"=>copy(critical),
                "cost_source_ids"=>Dict{String,String}(),
                "diagnostic_source_ids"=>Dict{String,String}(),
            )
            push!(r["iterations"], step)
            tick = time()
            b = build_r5_strategic_benders_master(
                c;
                optimizer,
                spec,
                subproblems = [r["subproblems"][id] for id in r["cut_order"]],
                critical,
                complementarity_pattern = pattern,
            )
            master = r5_strategic_benders_master_result(c, b, deadline, r["run_id"]*"/$iteration")
            step["master"] = master
            master["validation"] =
                r5_strategic_benders_master_check(c, spec, master, b.cuts, pattern)
            if !master["has_candidate"]
                if master["status"] == "solver_infeasible"
                    r["status"] =
                        b.scope == "full_risk_domain" ? "declared_domain_infeasible" :
                        "restricted_domain_infeasible"
                    isfinite(best) &&
                        (r["status"] = "master_infeasibility_conflicts_with_candidate")
                elseif master["status"] in ("DUAL_INFEASIBLE", "INFEASIBLE_OR_UNBOUNDED")
                    r["status"] = "master_relaxation_"*master["status"]
                else
                    r["status"] = "master_"*master["status"]
                end
                step["elapsed_sec"] = time()-tick
                break
            elseif !master["validation"]["pass"]
                r["status"] = "master_validation_failed"
                step["elapsed_sec"] = time()-tick
                break
            end
            if master["validation"]["bound_valid"] && b.scope == "full_risk_domain"
                lower = max(lower, master["solver_objective_bound"])
            end
            untrusted, unresolved = false, false
            ranking = Tuple{Float64,Int}[]
            # 即使最坏分布给某情景零概率，也不能免除其硬设备/交付检查。
            for (s, item) in enumerate(sc)
                remaining = deadline-time()
                remaining > 0 || break
                src = solve_r5_benders_subproblem(
                    rc,
                    s,
                    master["first_stage"];
                    branch = round(Int, master["z"][s]),
                    optimizer = subproblem_optimizer,
                    budget_sec = min(600, remaining),
                    deadline,
                )
                id = src["run_id"]
                r["subproblems"][id] = src
                step["cost_source_ids"][item["id"]] = id
                if src["validation"]["kkt_pass"]
                    add_cut!(src, step)
                elseif src["status"] == "solver_infeasible"
                    remaining = deadline-time()
                    remaining > 0 || break
                    diagnostic = solve_r5_benders_subproblem(
                        rc,
                        s,
                        master["first_stage"];
                        branch = round(Int, master["z"][s]),
                        elastic = true,
                        optimizer = subproblem_optimizer,
                        budget_sec = min(600, remaining),
                        deadline,
                        numerical_scale = spec.diagnostic_scale,
                    )
                    did = diagnostic["run_id"]
                    r["subproblems"][did] = diagnostic
                    step["diagnostic_source_ids"][item["id"]] = did
                    if diagnostic["validation"]["kkt_pass"]
                        if spec.feasibility == :cuts
                            added = add_cut!(diagnostic, step)
                            !added &&
                                !r5_benders_cut(
                                    rc,
                                    diagnostic;
                                    arithmetic = spec.cut_arithmetic,
                                )["productive"] &&
                                (unresolved = true)
                        elseif s in critical
                            unresolved = true
                        else
                            push!(ranking, (diagnostic["solver_objective"], s))
                        end
                    else
                        untrusted = true
                    end
                else
                    untrusted = true
                end
            end
            step["unresolved_sources"] = [
                Dict(
                    "source_id"=>id,
                    "status"=>r["subproblems"][id]["status"],
                    "kkt_status"=>r["subproblems"][id]["validation"]["status"],
                ) for id in vcat(
                    collect(values(step["cost_source_ids"])),
                    collect(values(step["diagnostic_source_ids"])),
                ) if !r["subproblems"][id]["validation"]["kkt_pass"] &&
                    r["subproblems"][id]["status"] != "solver_infeasible"
            ]
            if length(step["cost_source_ids"]) == length(sc) && all(
                r["subproblems"][id]["validation"]["model_pass"] for
                id in values(step["cost_source_ids"])
            )
                candidate = r5_strategic_benders_evaluate(
                    c,
                    master,
                    step["cost_source_ids"],
                    r["subproblems"],
                    pattern;
                    optimizer = oracle_optimizer,
                    deadline,
                )
                step["candidate"] = candidate
                if r5_strategic_benders_candidate_pass(candidate["validation"])
                    cost = candidate["validation"]["worst_total_cost_USD"]
                    if cost < best
                        best, selected = cost, iteration
                    end
                end
            end
            sort!(ranking; by = x->(-x[1], x[2]))
            append!(critical, [p[2] for p in Iterators.take(ranking, spec.critical_count)])
            sort!(critical)
            step["critical_after"] = copy(critical)
            local_lower =
                b.scope == "full_risk_domain" ? lower :
                (master["validation"]["bound_valid"] ? master["solver_objective_bound"] : -Inf)
            step["gap"] = r5_benders_gap(best, local_lower, spec)
            step["elapsed_sec"] = time()-tick
            if time() >= deadline
                r["status"] = "budget_exhausted"
                break
            elseif untrusted
                r["status"] = "untrusted_or_unresolved_subproblem"
                r["failure_sources"] = deepcopy(step["unresolved_sources"])
                break
            elseif unresolved
                r["status"] = "nonseparating_or_conflicting_diagnostic"
                break
            elseif step["gap"]["stopping_pass"] && critical == b.critical
                r["status"] =
                    b.scope == "full_risk_domain" ? "declared_domain_gap" : "restricted_domain_gap"
                break
            elseif isempty(step["new_cut_ids"]) && critical == b.critical
                r["status"] = "no_new_cuts"
                break
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    selected > 0 && (r["selected_iteration"] = selected)
    r["source_hashes_at_return"] = r5_strategic_benders_science_hashes()
    r["source_unchanged"] = r["source_hashes_at_solve"] == r["source_hashes_at_return"]
    r["validation"] = validate_r5_strategic_benders(c, r)
    completion = r5_strategic_benders_completion(r, r["validation"])
    r["cost_optimization_complete"], r["declared_branch_cost_complete"] =
        completion.full, completion.branch
    r["elapsed_sec"], r["budget_overrun_sec"] = time()-start, max(0.0, time()-deadline)
    r
end
