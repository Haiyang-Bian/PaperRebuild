include("r5_benders_witness.jl")
using CSV

"""从已重验原值生成分解表格；受限域停止、完整域费用完成和可行候选分别记账。"""
function r5_benders_report_tables(c, r, entry, reference)
    v=r["validation"]
    id=entry["id"]
    run=r["run_id"]
    ref=reference["result"]
    rc=R5RiskCase(reference["case"])
    rc.sha256==c.sha256||error("跨输入比较分解")
    rv=validate_r5_risk(rc, ref)
    usable=v["model_pass"]&&v["risk_pass"]&&v["cost_pass"]
    refusable=rv["model_pass"]&&rv["risk_pass"]&&rv["cost_pass"]
    cost=v["upper_bound"]
    refcost=get(rv, "worst_net_cost", Inf)
    comparable=usable&&refusable
    difference=comparable ? cost-refcost : NaN
    relative=comparable ? abs(difference)/max(1, abs(cost), abs(refcost)) : NaN
    certified=comparable&&r["cost_optimization_complete"]&&ref["cost_optimization_complete"]
    lastcheck=isempty(v["iteration_checks"]) ? Dict() : last(v["iteration_checks"])
    laststep=isempty(r["iterations"]) ? Dict() : last(r["iterations"])
    tables=Dict(
        k=>NamedTuple[] for k in (
            "comparison.csv",
            "iterations.csv",
            "subproblems.csv",
            "cuts.csv",
            "residuals.csv",
            "selected-residuals.csv",
        )
    )
    push!(
        tables["comparison.csv"],
        (;
            record_id = id,
            run_id = run,
            case = entry["case"],
            case_sha256 = c.sha256,
            route = entry["route"],
            solver = entry["solver"],
            status = r["status"],
            model_pass = v["model_pass"],
            risk_pass = v["risk_pass"],
            cost_pass = v["cost_pass"],
            evidence_pass = v["evidence_pass"],
            cost_complete = r["cost_optimization_complete"],
            full_stopping = v["stopping_pass"],
            restricted_stopping = v["restricted_stopping_pass"],
            upper_bound = cost,
            full_lower_bound = v["lower_bound"],
            full_relative_gap = v["gap"]["relative"],
            final_bound_scope = get(lastcheck, "scope", "none"),
            final_scoped_lower = get(lastcheck, "lower_bound", -Inf),
            scoped_relative_gap = get(get(lastcheck, "gap", Dict()), "relative", Inf),
            iterations = length(r["iterations"]),
            critical_count = length(get(laststep, "critical_after", [])),
            cuts = length(r["cuts"]),
            cost_subproblems = count(s->!s["elastic"], values(r["subproblems"])),
            diagnostic_subproblems = count(s->s["elastic"], values(r["subproblems"])),
            elapsed_sec = r["elapsed_sec"],
            budget_sec = r["budget_sec"],
            budget_overrun_sec = r["budget_overrun_sec"],
            reference_run_id = ref["run_id"],
            reference_cost = refcost,
            reference_cost_complete = ref["cost_optimization_complete"],
            candidate_comparable = comparable,
            candidate_cost_difference = difference,
            candidate_relative_difference = relative,
            same_domain_certified_pair = certified,
            A2_pass = certified&&relative<=1e-4,
            reference_infeasible = ref["status"]=="solver_infeasible",
            infeasibility_scope = v["infeasibility_scope"],
        ),
    )
    # 残差按每一阶段/情景/类别保存最大项、原始项数和失败数；完整原值在拆分见证中。
    function residuals(rows, phase, iteration, scenario; selected = false)
        groups=sort!(unique(get(a, "kind", get(a, "group", "unknown")) for a in rows))
        for group in groups
            members=filter(a->get(a, "kind", get(a, "group", "unknown"))==group, rows)
            sort!(members; by = a->(get(a, "id", ""), get(a, "entity", ""), get(a, "t", 0)))
            largest=members[argmax([a["normalized"] for a in members])]
            push!(
                tables["residuals.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    phase,
                    iteration,
                    scenario,
                    group,
                    count = length(members),
                    failures = count(a->!a["pass"], members),
                    worst_id = largest["id"],
                    residual = largest["residual"],
                    tolerance = largest["tolerance"],
                    normalized = largest["normalized"],
                    pass = all(a["pass"] for a in members),
                ),
            )
        end
        if selected
            for a in rows
                push!(
                    tables["selected-residuals.csv"],
                    (;
                        record_id = id,
                        run_id = run,
                        phase,
                        iteration,
                        scenario,
                        group = get(a, "kind", get(a, "group", "unknown")),
                        id = a["id"],
                        entity = get(a, "entity", ""),
                        t = get(a, "t", 0),
                        residual = a["residual"],
                        tolerance = a["tolerance"],
                        normalized = a["normalized"],
                        pass = a["pass"],
                        unit = get(a, "unit", "1"),
                    ),
                )
            end
        end
    end
    cumulative=0.0
    for (i, step) in enumerate(r["iterations"])
        m=get(step, "master", Dict())
        cv=get(get(step, "candidate", Dict()), "validation", Dict())
        recorded=filter(a->a["iteration"]==i, v["iteration_checks"])
        check=isempty(recorded) ?
              Dict(
            "scope"=>"missing",
            "master_pass"=>false,
            "bound_valid"=>false,
            "lower_bound"=>-Inf,
            "upper_bound"=>Inf,
            "gap"=>Dict("relative"=>Inf),
            "candidate_pass"=>false,
        ) : only(recorded)
        cumulative+=get(step, "elapsed_sec", 0.0)
        push!(
            tables["iterations.csv"],
            (;
                record_id = id,
                run_id = run,
                iteration = i,
                bound_scope = check["scope"],
                master_status = get(m, "status", "missing"),
                master_pass = check["master_pass"],
                bound_valid = check["bound_valid"],
                lower_bound = check["lower_bound"],
                upper_bound = check["upper_bound"],
                relative_gap = check["gap"]["relative"],
                candidate_pass = check["candidate_pass"],
                candidate_cost = get(cv, "worst_net_cost", NaN),
                critical_before = join(get(m, "critical", []), ";"),
                critical_after = join(step["critical_after"], ";"),
                critical_count = length(step["critical_after"]),
                new_cuts = length(step["new_cut_ids"]),
                cost_scenarios = length(step["cost_source_ids"]),
                diagnostic_scenarios = length(step["diagnostic_source_ids"]),
                elapsed_sec = get(step, "elapsed_sec", NaN),
                cumulative_stage_sec = cumulative,
            ),
        )
        residuals(get(get(m, "validation", Dict()), "rows", []), "master", i, "shared")
        for (kind, ids) in
            (("cost", step["cost_source_ids"]), ("diagnostic", step["diagnostic_source_ids"]))
            for sid in sort!(collect(keys(ids)))
                source=ids[sid]
                s=r["subproblems"][source]
                sv=s["validation"]
                push!(
                    tables["subproblems.csv"],
                    (;
                        record_id = id,
                        run_id = run,
                        iteration = i,
                        scenario = sid,
                        source_id = source,
                        kind,
                        branch = s["branch"],
                        status = s["status"],
                        model_pass = sv["model_pass"],
                        kkt_pass = sv["kkt_pass"],
                        kkt_status = sv["status"],
                        objective = get(s, "solver_objective", NaN),
                        objective_unit = kind=="cost" ? "synthetic_USD" : "normalized_violation",
                        numerical_scale = get(s, "numerical_scale", 1.0),
                    ),
                )
                residuals(get(sv, "rows", []), kind*"_KKT", i, sid)
                residuals(get(get(sv, "physical", Dict()), "rows", []), kind*"_physical", i, sid)
            end
        end
        if haskey(step, "candidate")
            selected=i==get(v, "selected_iteration", 0)
            residuals(cv["rows"], "candidate_joint", i, "shared"; selected)
            for sid in sort!(collect(keys(cv["scenarios"])))
                residuals(
                    cv["scenarios"][sid]["validation"]["rows"],
                    "candidate_physical",
                    i,
                    sid;
                    selected,
                )
            end
            for label in sort!(collect(keys(get(cv, "transport_checks", Dict()))))
                residuals(
                    cv["transport_checks"][label]["rows"],
                    "candidate_transport_"*label,
                    i,
                    "transport";
                    selected,
                )
            end
        end
        for source in step["new_cut_ids"]
            cut=r["cuts"][source]
            push!(
                tables["cuts.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    iteration = i,
                    source_id = source,
                    scenario = cut["scenario"],
                    branch = cut["branch"],
                    kind = cut["kind"],
                    source_value = cut["source_value"],
                    guard = cut["guard"],
                    lower_cost = cut["lower_cost"],
                    deactivation_M = cut["deactivation_M"],
                    productive = cut["productive"],
                    arithmetic = cut["arithmetic"],
                    unit = cut["units"],
                    certificate_scope = cut["certificate_scope"],
                ),
            )
        end
    end
    for file in ("residuals.csv", "selected-residuals.csv")
        sort!(
            tables[file];
            by = x->(
                x.iteration,
                x.phase,
                x.scenario,
                x.group,
                haskey(x, :id) ? x.id : x.worst_id,
                haskey(x, :entity) ? x.entity : "",
                haskey(x, :t) ? x.t : 0,
            ),
        )
    end
    tables
end
