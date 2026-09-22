include("r5_strategic_benders_witness.jl")
using CSV

"""从独立验算值生成三路线比较、真实迭代及市场/物理/风险残差；私人费用不称为社会成本。"""
function r5_sb_report_tables(c, r, entry, reference)
    v = r["validation"]
    ref = reference["result"]
    R5StrategicCase(reference["case"]).sha256 == c.sha256 || error("跨输入比较策略分解")
    haskey(r, "complementarity_pattern") && error("正式实验不允许固定互补分支")
    haskey(ref, "complementarity_pattern") && error("正式参考不是完整市场域")
    rv = validate_r5_strategic(c, ref)
    ref["cost_optimization_complete"] ==
    (ref["status"] == "solver_optimal" && rv["optimality_pass"]) || error("参考费用证书不符")
    usable(x) =
        all(x[k] for k in ("model_pass", "risk_pass", "cost_pass", "independent_market_kkt_pass"))
    comparable = usable(v) && usable(rv)
    cost, refcost = v["upper_bound"], get(rv, "worst_total_cost_USD", Inf)
    difference = comparable ? cost-refcost : NaN
    relative = comparable ? abs(difference)/max(1, abs(cost), abs(refcost)) : NaN
    certified = comparable && r["cost_optimization_complete"] && ref["cost_optimization_complete"]
    id, run = entry["id"], r["run_id"]
    tables = Dict(
        k=>NamedTuple[] for k in (
            "comparison.csv",
            "iterations.csv",
            "subproblems.csv",
            "residuals.csv",
            "selected-residuals.csv",
        )
    )
    lastcheck = isempty(v["iteration_checks"]) ? Dict() : last(v["iteration_checks"])
    sv = get(v, "selected_validation", Dict())
    push!(
        tables["comparison.csv"],
        (;
            record_id = id,
            run_id = run,
            case = entry["case"],
            case_sha256 = c.sha256,
            route = entry["route"],
            status = r["status"],
            model_pass = v["model_pass"],
            risk_pass = v["risk_pass"],
            cost_pass = v["cost_pass"],
            evidence_pass = v["evidence_pass"],
            independent_market_pass = v["independent_market_kkt_pass"],
            cost_complete = r["cost_optimization_complete"],
            restricted_stopping = v["restricted_stopping_pass"],
            upper_bound = cost,
            net_payment_USD = get(sv, "selected_payment_USD", NaN),
            worst_recourse_USD = get(sv, "worst_recourse_USD", NaN),
            full_lower_bound = v["lower_bound"],
            full_relative_gap = v["gap"]["relative"],
            final_bound_scope = get(lastcheck, "bound_scope", "none"),
            final_scoped_lower = get(lastcheck, "lower_bound", -Inf),
            scoped_relative_gap = get(get(lastcheck, "gap", Dict()), "relative", Inf),
            iterations = length(r["iterations"]),
            cuts = length(r["cuts"]),
            selected_iteration = get(v, "selected_iteration", 0),
            elapsed_sec = r["elapsed_sec"],
            budget_sec = r["budget_sec"],
            budget_overrun_sec = r["budget_overrun_sec"],
            reference_run_id = ref["run_id"],
            reference_status = ref["status"],
            reference_cost = refcost,
            candidate_comparable = comparable,
            candidate_cost_difference = difference,
            candidate_relative_difference = relative,
            A2_pass = certified && relative<=1e-4,
            infeasibility_scope = v["infeasibility_scope"],
            unboundedness_scope = v["unboundedness_scope"],
        ),
    )
    function residuals(x, scope, phase, iteration; selected = false)
        x isa AbstractDict || return
        rows = [a for a in get(x, "rows", []) if haskey(a, "residual") && haskey(a, "tolerance")]
        sort!(rows; by = PaperRebuild.r5_market_text)
        if !isempty(rows)
            values = [abs(a["residual"])/a["tolerance"] for a in rows]
            worst = rows[argmax(values)]
            push!(
                tables["residuals.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    phase,
                    iteration,
                    scope,
                    count = length(rows),
                    failures = count(a->!a["pass"], rows),
                    worst_id = worst["id"],
                    normalized = maximum(values),
                    pass = all(a["pass"] for a in rows),
                ),
            )
            if selected
                for (a, normalized) in zip(rows, values)
                    push!(
                        tables["selected-residuals.csv"],
                        (;
                            record_id = id,
                            run_id = run,
                            scope,
                            id = a["id"],
                            entity = string(get(a, "entity", "")),
                            t = get(a, "t", 0),
                            residual = a["residual"],
                            tolerance = a["tolerance"],
                            normalized,
                            pass = a["pass"],
                            unit = get(a, "unit", "1"),
                        ),
                    )
                end
            end
        end
        for key in sort!(collect(keys(x)); by = string)
            key == "rows" || residuals(x[key], scope*"/"*string(key), phase, iteration; selected)
        end
    end
    for (i, step) in enumerate(r["iterations"])
        matches = filter(x->x["iteration"]==i, v["iteration_checks"])
        ck = isempty(matches) ? Dict() : only(matches)
        m = get(step, "master", Dict())
        cv = get(get(step, "candidate", Dict()), "validation", Dict())
        push!(
            tables["iterations.csv"],
            (;
                record_id = id,
                run_id = run,
                route = entry["route"],
                iteration = i,
                master_status = get(m, "status", "missing"),
                bound_scope = get(m, "bound_scope", "none"),
                lower_bound = get(ck, "lower_bound", -Inf),
                upper_bound = get(ck, "upper_bound", Inf),
                relative_gap = get(get(ck, "gap", Dict()), "relative", Inf),
                master_objective = get(m, "solver_objective", NaN),
                candidate_cost = get(cv, "worst_total_cost_USD", NaN),
                net_payment_USD = get(cv, "selected_payment_USD", NaN),
                worst_recourse_USD = get(cv, "worst_recourse_USD", NaN),
                candidate_pass = get(ck, "candidate_pass", false),
                critical_count = length(step["critical_after"]),
                cost_scenarios = length(step["cost_source_ids"]),
                diagnostic_scenarios = length(step["diagnostic_source_ids"]),
                new_cuts = length(step["new_cut_ids"]),
                elapsed_sec = get(step, "elapsed_sec", 0.0),
            ),
        )
        residuals(get(m, "validation", Dict()), "master", "master", i)
        residuals(cv, "candidate", "candidate", i; selected = i==get(v, "selected_iteration", 0))
        for (kind, key) in (("cost", "cost_source_ids"), ("diagnostic", "diagnostic_source_ids"))
            for (sid, source) in sort!(collect(step[key]); by = first)
                src = r["subproblems"][source]
                vv = src["validation"]
                push!(
                    tables["subproblems.csv"],
                    (;
                        record_id = id,
                        run_id = run,
                        iteration = i,
                        scenario = sid,
                        source_id = source,
                        kind,
                        status = src["status"],
                        branch = src["branch"],
                        model_pass = vv["model_pass"],
                        kkt_pass = vv["kkt_pass"],
                        objective = get(src, "solver_objective", NaN),
                        numerical_scale = get(src, "numerical_scale", 1.0),
                    ),
                )
                residuals(vv, "$kind/$sid", kind, i)
            end
        end
    end
    tables
end

function r5_sb_report_counts(tables)
    rows, res = tables["comparison.csv"], tables["selected-residuals.csv"]
    d = Dict{String,Any}(
        "records"=>length(rows),
        "selected_residual_count"=>length(res),
        "max_selected_normalized_residual"=>maximum(x.normalized for x in res; init = 0.0),
        "selected_residual_failures"=>count(x->!x.pass, res),
    )
    for key in ("model_pass", "risk_pass", "cost_complete", "restricted_stopping", "A2_pass")
        d[key] = count(x->getproperty(x, Symbol(key)), rows)
    end
    d
end
