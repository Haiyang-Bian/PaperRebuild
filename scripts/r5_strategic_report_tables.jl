using PaperRebuild, CSV, TOML, SHA

function r5_strategic_public(x)
    if x isa AbstractDict
        return Dict(
            string(k)=>r5_strategic_public(v) for
            (k, v) in x if string(k) ∉ ("validation", "source_hashes_at_solve")
        )
    elseif x isa AbstractVector
        return [r5_strategic_public(v) for v in x]
    end
    x
end

function r5_strategic_tables(c, r, e)
    v=validate_r5_strategic(c, r)
    id, run=e["id"], r["run_id"]
    tables=Dict(
        k=>NamedTuple[] for k in (
            "comparison.csv",
            "residuals.csv",
            "bids-awards.csv",
            "risk-scenarios.csv",
            "trajectories.csv",
        )
    )
    rv=get(v, "risk_policy", Dict())
    external=NaN
    devices=NaN
    if haskey(r, "selected_market")
        m=c.data["market"]
        external=m["dt_h"]*sum(
            g["energy_bid"][t]*r["selected_market"]["values"]["P_G"][i][t] for
            (i, g) in enumerate(m["generators"]), t in 1:m["T"]
        )
        devices=sum(
            s["probability"]*rv["scenarios"][s["id"]]["validation"]["device_cost"] for
            s in c.data["risk"]["commitment"]["scenarios"]
        )
    end
    push!(
        tables["comparison.csv"],
        (;
            record_id = id,
            run_id = run,
            case = e["case"],
            case_sha256 = c.sha256,
            solver = e["solver"],
            method = e["method"],
            status = r["status"],
            model_pass = v["model_pass"],
            selected_kkt_pass = v["selected_kkt_pass"],
            independent_market_pass = v["independent_market_kkt_pass"],
            risk_pass = v["risk_pass"],
            cost_complete = r["cost_optimization_complete"],
            total_cost_USD = get(v, "worst_total_cost_USD", NaN),
            net_payment_USD = get(v, "selected_payment_USD", NaN),
            worst_recourse_USD = get(v, "worst_recourse_USD", NaN),
            bound = get(r, "solver_objective_bound", NaN),
            bound_scope = get(v, "bound_scope", "no_candidate"),
            relative_gap = get(v, "relative_gap", NaN),
            worst_risk = get(rv, "worst_violation_probability", NaN),
            epsilon = c.data["risk"]["epsilon"],
            radius = c.data["risk"]["ambiguity"]["radius"],
            external_energy_bid_cost_USD = external,
            nominal_internal_device_cost_USD = devices,
            nominal_energy_resource_proxy_USD = external+devices,
            elapsed_sec = r["elapsed_sec"],
        ),
    )
    function residuals(x, path)
        if x isa AbstractDict
            for a in get(x, "rows", [])
                haskey(a, "residual")&&haskey(a, "tolerance") || continue
                push!(
                    tables["residuals.csv"],
                    (;
                        record_id = id,
                        run_id = run,
                        scope = path*"/"*string(get(a, "group", get(a, "scope", ""))),
                        id = a["id"],
                        entity = string(get(a, "entity", "")),
                        t = get(a, "t", 0),
                        residual = a["residual"],
                        tolerance = a["tolerance"],
                        normalized = abs(a["residual"])/a["tolerance"],
                        pass = a["pass"],
                        unit = get(a, "unit", "1"),
                    ),
                )
            end
            for k in sort!(collect(keys(x)); by = string)
                k=="rows" || residuals(x[k], path*"/"*string(k))
            end
        end
    end
    residuals(v, "strategy")
    if haskey(r, "risk_policy")
        rp=r["risk_policy"]
        for t in 1:c.data["market"]["T"]
            push!(
                tables["bids-awards.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    t,
                    energy_bid = r["bids"]["energy_bid"][t],
                    up_bid = r["bids"]["up_bid"][t],
                    down_bid = r["bids"]["down_bid"][t],
                    energy_price = v["selected_market"]["LMP_USD_MWh"][1][t],
                    up_price = v["selected_market"]["reserve_up_price"][t],
                    down_price = v["selected_market"]["reserve_down_price"][t],
                    P_DA_MW = rp["first_stage"]["P_DA_MW"][t],
                    R_up_MW = rp["first_stage"]["R_up_MW"][t],
                    R_down_MW = rp["first_stage"]["R_down_MW"][t],
                ),
            )
        end
        for (i, s) in enumerate(c.data["risk"]["commitment"]["scenarios"])
            sid=s["id"]
            sv=rv["scenarios"][sid]
            worst(label) = get(
                get(get(rv, "transport_checks", Dict()), label, Dict()),
                "worst_weights",
                fill(NaN, length(c.data["risk"]["commitment"]["scenarios"])),
            )[i]
            push!(
                tables["risk-scenarios.csv"],
                (;
                    record_id = id,
                    run_id = run,
                    scenario = sid,
                    nominal = s["probability"],
                    z = rp["z"][i],
                    cost_USD = sv["recourse_cost"],
                    cost_worst = worst("cost"),
                    risk_worst = worst("risk"),
                    comfort_excess_K = sv["comfort_excess_K"],
                ),
            )
            for (j, building) in enumerate(s["case"]["buildings"]), t in 1:s["case"]["T"]
                vals=rp["scenarios"][sid]["values"]
                push!(
                    tables["trajectories.csv"],
                    (;
                        record_id = id,
                        run_id = run,
                        scenario = sid,
                        building = building["id"],
                        t,
                        dt_h = s["case"]["dt_h"],
                        room_K = vals["τ_IN"][j][t],
                        heat_MW = vals["H_D"][j][t],
                        import_MW = vals["P_PCC"][1][t],
                        delivered_MW = sv["validation"]["delivered_MW"][t],
                        requested_MW = sv["validation"]["request_MW"][t],
                    ),
                )
            end
        end
    end
    sort!(tables["residuals.csv"]; by = x->(x.scope, x.id, x.entity, x.t, x.residual))
    tables
end

function r5_strategic_pairs(rows)
    out=NamedTuple[]
    for case in sort(unique(x.case for x in rows))
        group=filter(x->x.case==case, rows)
        length(group)==2 || continue
        a=only(filter(x->x.method=="sos1", group))
        b=only(filter(x->x.method=="fixed_complementarity", group))
        comparable=a.cost_complete&&b.cost_complete
        gap=comparable ?
            abs(a.total_cost_USD-b.total_cost_USD) /
            max(1.0, abs(a.total_cost_USD), abs(b.total_cost_USD)) : NaN
        push!(
            out,
            (;
                case,
                sos1 = a.record_id,
                branch = b.record_id,
                comparable,
                objective_relative_difference = gap,
                A2_pass = comparable&&gap<=1e-4,
                interpretation = "fixed_branch_agreement_not_general_branch_lower_bound",
            ),
        )
    end
    out
end

function r5_strategic_selection_table(w, id)
    c=R5MarketCase(w["case"])
    parent, range=w["parent"], w["range"]
    range["primal_sha256"]==bytes2hex(sha256(PaperRebuild.r5_market_text(parent["values"]))) ||
        error("价格范围成交指纹不同")
    out=NamedTuple[]
    for side in ("minimum", "maximum")
        e=range["endpoints"][side]
        v=PaperRebuild.r5_market_selection_endpoint(c, parent, e, side)
        v["pass"]||error("价格范围端点没有通过验算")
        push!(
            out,
            (;
                record_id = id,
                run_id = parent["run_id"],
                case_sha256 = c.sha256,
                side,
                payment_USD = e["payment_USD"],
                status = e["status"],
                lower_objective = parent["solver_objective"],
                pass = v["pass"],
            ),
        )
    end
    out
end
