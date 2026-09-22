using PaperRebuild, CSV, TOML, SHA

function r5_risk_public_result(r)
    d=deepcopy(r)
    pop!(d, "validation", nothing)
    pop!(d, "source_hashes_at_solve", nothing)
    for oracle in values(get(d, "oracles", Dict()))
        pop!(oracle, "validation", nothing)
    end
    if haskey(d, "branches")
        d["branches"]=[r5_risk_public_result(b) for b in d["branches"]]
    end
    d
end

function r5_risk_report_tables(c, r, entry)
    v=validate_r5_risk(c, r)
    id=entry["id"]
    run=r["run_id"]
    tables=Dict(
        k=>NamedTuple[] for k in (
            "comparison.csv",
            "residuals.csv",
            "commitments.csv",
            "scenarios.csv",
            "trajectories.csv",
            "branches.csv",
        )
    )
    push!(
        tables["comparison.csv"],
        (;
            record_id = id,
            run_id = run,
            case = entry["case"],
            case_sha256 = c.sha256,
            solver = entry["solver"],
            method = entry["method"],
            status = r["status"],
            model_pass = v["model_pass"],
            risk_pass = v["risk_pass"],
            cost_pass = v["cost_pass"],
            cost_complete = r["cost_optimization_complete"],
            objective = get(v, "worst_net_cost", NaN),
            nominal_cost = get(v, "nominal_net_cost", NaN),
            solver_objective = get(r, "solver_objective", NaN),
            bound = get(r, "solver_objective_bound", NaN),
            relative_gap = get(v, "relative_gap", NaN),
            day_ahead_cost = get(v, "day_ahead_cost", NaN),
            radius = c.data["ambiguity"]["radius"],
            epsilon = c.data["epsilon"],
            actual_risk = get(v, "worst_violation_probability", NaN),
            selected_risk = get(v, "selected_violation_bound", NaN),
            elapsed_sec = r["elapsed_sec"],
            branch_count = length(get(r, "branches", [])),
        ),
    )
    function residuals(vv, prefix, scenario)
        for a in vv["rows"]
            push!(
                tables["residuals.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    scenario,
                    group = prefix*"/"*a["group"],
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
    residuals(v, "joint", "shared")
    for sid in sort!(collect(keys(v["scenarios"])))
        residuals(v["scenarios"][sid]["validation"], "physical", sid)
    end
    for label in sort!(collect(keys(get(v, "transport_checks", Dict()))))
        residuals(v["transport_checks"][label], "oracle_"*label, "transport")
    end
    if haskey(r, "first_stage")&&haskey(v, "nominal_net_cost")
        sc=c.data["commitment"]["scenarios"]
        for t in 1:first(sc)["case"]["T"]
            push!(
                tables["commitments.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    t,
                    P_DA_MW = r["first_stage"]["P_DA_MW"][t],
                    R_up_MW = r["first_stage"]["R_up_MW"][t],
                    R_down_MW = r["first_stage"]["R_down_MW"][t],
                ),
            )
        end
        checks=get(v, "transport_checks", Dict())
        for (i, s) in enumerate(sc)
            sid=s["id"]
            sv=v["scenarios"][sid]
            values=r["scenarios"][sid]["values"]
            worst(label) =
                get(get(checks, label, Dict()), "worst_weights", fill(NaN, length(sc)))[i]
            push!(
                tables["scenarios.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    scenario = sid,
                    probability = s["probability"],
                    z = r["z"][i],
                    actual_event = v["actual_event"][i],
                    raw_event = v["raw_event"][i],
                    comfort_excess_K = sv["comfort_excess_K"],
                    recourse_cost = sv["recourse_cost"],
                    epigraph_cost = sv["epigraph_recourse_cost"],
                    cost_worst_probability = worst("cost"),
                    risk_worst_probability = worst("risk"),
                    actual_worst_probability = worst("actual"),
                ),
            )
            for (j, b) in enumerate(s["case"]["buildings"]), t in 1:s["case"]["T"]
                vv=sv["validation"]
                push!(
                    tables["trajectories.csv"],
                    (;
                        record_id = id,
                        run_id = run,
                        scenario = sid,
                        building = b["id"],
                        t,
                        dt_h = s["case"]["dt_h"],
                        room_K = values["τ_IN"][j][t],
                        comfort_lower_K = b["T_min_K"],
                        comfort_upper_K = b["T_max_K"],
                        heat_MW = values["H_D"][j][t],
                        import_MW = values["P_PCC"][1][t],
                        request_MW = vv["request_MW"][t],
                        delivered_MW = vv["delivered_MW"][t],
                        mismatch_MW = vv["mismatch_MW"][t],
                    ),
                )
            end
        end
    end
    for b in get(r, "branches", [])
        bv=validate_r5_risk(c, b)
        push!(
            tables["branches.csv"],
            (;
                record_id = id,
                run_id = run,
                branch_run_id = b["run_id"],
                pattern = join(b["pattern"]),
                status = b["status"],
                model_pass = bv["model_pass"],
                risk_pass = bv["risk_pass"],
                cost_complete = b["cost_optimization_complete"],
                objective = get(bv, "worst_net_cost", NaN),
                bound = get(b, "solver_objective_bound", NaN),
            ),
        )
    end
    sort!(tables["residuals.csv"]; by = a->(a.scenario, a.group, a.id, a.entity, a.t))
    tables
end

function r5_risk_comparisons(rows)
    out=NamedTuple[]
    for file in sort(unique(x.case for x in rows))
        group=filter(x->x.case==file, rows)
        a=only(filter(x->x.solver=="highs", group))
        for b in filter(x->x.solver!="highs", group)
            comparable=a.cost_complete&&b.cost_complete
            gap=comparable ?
                abs(a.objective-b.objective)/max(1, abs(a.objective), abs(b.objective)) : NaN
            push!(
                out,
                (;
                    case = file,
                    reference = a.record_id,
                    other = b.record_id,
                    comparable,
                    both_infeasible = a.status==b.status=="solver_infeasible",
                    objective_relative_difference = gap,
                    A2_pass = comparable&&gap<=1e-4,
                ),
            )
        end
    end
    out
end
