using PaperRebuild, CSV, TOML, SHA

function r5_execution_public(x)
    x isa AbstractDict && return Dict(
        string(k)=>r5_execution_public(v) for
        (k, v) in x if string(k) ∉ ("validation", "source_hashes_at_solve")
    )
    x isa AbstractVector && return [r5_execution_public(v) for v in x]
    x
end

function r5_execution_expected(e, root)
    if e["mode"]=="market_only"
        path=joinpath(root, split(e["input"], '/')...)
        bytes2hex(sha256(read(path)))==e["input_sha256"] || error("冻结市场输入变化")
        return (; c = nothing, mc = load_r5_market_case(path), parent = nothing)
    end
    path=joinpath(root, split(e["parent"], '/')...)
    bytes2hex(sha256(read(path)))==e["parent_sha256"] || error("冻结策略父见证变化")
    w=TOML.parsefile(path)
    c=R5StrategicCase(w["case"])
    c.sha256==e["case_sha256"] || error("父案例哈希变化")
    bids=e["mode"]=="preset_minimum_norm" ?
         Dict(k=>(b["lower"] .+ b["upper"]) ./ 2 for (k, b) in c.data["bid_bounds"]) :
         w["result"]["bids"]
    (; c, mc = PaperRebuild.r5_strategic_market_case(c, bids), parent = w["result"])
end

function r5_execution_tables(w, e, root)
    for (key, value) in e
        w["record"][key]==value || error("公开规则身份不符")
    end
    record, stages=w["record"], w["stages"]
    Set(keys(stages))==Set(record["stages"]) || error("阶段清单不符")
    expected=r5_execution_expected(e, root)
    validations=Dict{String,Any}()
    for (name, stage) in stages
        stage["raw_result_sha256"]==record["stage_sha256"][name] || error("阶段原值身份不符")
        p, r=stage["payload"], stage["result"]
        if name=="selection"
            R5MarketCase(p["case"]).sha256==expected.mc.sha256 || error("选择输入变化")
        elseif name=="delivery"
            expected.c===nothing && error("纯市场记录不能新增补救")
            R5StrategicCase(p["case"]).sha256==expected.c.sha256 &&
            R5MarketCase(p["market_case"]).sha256==expected.mc.sha256 || error("交付输入变化")
            market=e["mode"] in ("saved_selected", "saved_independent") ?
                   expected.parent[e["mode"]=="saved_selected" ? "selected_market" :
                                   "independent_market"] : stages["selection"]["result"]["market"]
            PaperRebuild.r5_execution_hash(p["market"])==PaperRebuild.r5_execution_hash(market) ||
                error("成交来源变化")
        else
            error("未知阶段")
        end
        validations[name]=PaperRebuild.r5_execution_payload_validation(p, r)
    end
    selection_pass=haskey(stages, "selection") ? validations["selection"]["execution_pass"] :
                   record["selection_status"]=="preserved_parent_market_witness"
    selection_pass==record["selection_pass"] || error("选择判定不同")
    delivery=get(validations, "delivery", Dict())
    get(delivery, "delivery_pass", false)==get(record, "delivery_pass", false) &&
    get(delivery, "cost_complete", false)==get(record, "cost_complete", false) ||
        error("交付判定不同")
    sr=get(stages, "selection", Dict())
    dr=get(stages, "delivery", Dict())
    r=get(dr, "result", get(sr, "result", Dict()))
    run=get(r, "run_id", e["id"]*"/no-stage")
    tables=Dict(
        k=>NamedTuple[] for
        k in ("comparison.csv", "residuals.csv", "awards.csv", "trajectories.csv")
    )
    oldcost=NaN
    if expected.parent!==nothing && haskey(expected.parent, "selected_market")
        oldcost=validate_r5_strategic(expected.c, expected.parent)["worst_total_cost_USD"]
    end
    payment=get(delivery, "payment_USD", NaN)
    if haskey(sr, "result") && haskey(sr["result"], "market")
        payment=r5_market_payment_identity(expected.mc, sr["result"]["market"])["direct_payment_USD"]
    end
    push!(
        tables["comparison.csv"],
        (;
            record_id = e["id"],
            run_id = run,
            case = e["case"],
            mode = e["mode"],
            market_case_sha256 = expected.mc.sha256,
            selection_status = record["selection_status"],
            selection_pass,
            delivery_status = get(record, "delivery_status", "not_applicable"),
            delivery_pass = get(delivery, "delivery_pass", false),
            cost_complete = get(delivery, "cost_complete", false),
            market_payment_USD = payment,
            recourse_USD = get(delivery, "worst_recourse_USD", NaN),
            total_cost_USD = get(delivery, "total_cost_USD", NaN),
            parent_selected_cost_USD = oldcost,
            conditional_cost_change_USD = get(delivery, "total_cost_USD", NaN)-oldcost,
            bound_scope = get(delivery, "bound_scope", "no_delivery_candidate"),
            worst_risk = get(get(delivery, "risk", Dict()), "worst_violation_probability", NaN),
            elapsed_sec = record["elapsed_sec"],
        ),
    )
    function residuals(x, path)
        x isa AbstractDict || return
        for row in get(x, "rows", [])
            haskey(row, "residual") && haskey(row, "tolerance") || continue
            push!(
                tables["residuals.csv"],
                (;
                    record_id = e["id"],
                    run_id = run,
                    scope = path*"/"*string(get(row, "group", get(row, "scope", ""))),
                    id = row["id"],
                    entity = string(get(row, "entity", "")),
                    t = get(row, "t", 0),
                    residual = row["residual"],
                    tolerance = row["tolerance"],
                    normalized = abs(row["residual"])/row["tolerance"],
                    pass = row["pass"],
                    unit = get(row, "unit", "1"),
                ),
            )
        end
        for key in sort!(collect(keys(x)); by = string)
            key=="rows" || residuals(x[key], path*"/"*string(key))
        end
    end
    residuals(validations, "execution")
    market=haskey(dr, "payload") ? dr["payload"]["market"] :
           get(get(sr, "result", Dict()), "market", nothing)
    if market!==nothing
        vm=validate_r5_market(expected.mc, market)
        m=expected.mc.data
        for (i, actor) in enumerate(m["ies"]), t in 1:m["T"]
            push!(
                tables["awards.csv"],
                (;
                    record_id = e["id"],
                    run_id = run,
                    ies = actor["id"],
                    t,
                    dt_h = m["dt_h"],
                    energy_bid = actor["energy_bid"][t],
                    up_bid = actor["up_bid"][t],
                    down_bid = actor["down_bid"][t],
                    P_DA_MW = market["values"]["P_IES"][i][t],
                    R_up_MW = market["values"]["R_IES_up"][i][t],
                    R_down_MW = market["values"]["R_IES_down"][i][t],
                    energy_price = vm["LMP_USD_MWh"][actor["node"]][t],
                    up_price = vm["reserve_up_price"][t],
                    down_price = vm["reserve_down_price"][t],
                ),
            )
        end
    end
    if haskey(delivery, "risk") && haskey(get(r, "risk", Dict()), "scenarios")
        for s in expected.c.data["risk"]["commitment"]["scenarios"]
            sid=s["id"]
            vals=r["risk"]["scenarios"][sid]["values"]
            v=delivery["risk"]["scenarios"][sid]["validation"]
            for (i, b) in enumerate(s["case"]["buildings"]), t in 1:s["case"]["T"]
                push!(
                    tables["trajectories.csv"],
                    (;
                        record_id = e["id"],
                        run_id = run,
                        scenario = sid,
                        building = b["id"],
                        t,
                        dt_h = s["case"]["dt_h"],
                        room_K = vals["τ_IN"][i][t],
                        heat_MW = vals["H_D"][i][t],
                        import_MW = vals["P_PCC"][1][t],
                        delivered_MW = v["delivered_MW"][t],
                        requested_MW = v["request_MW"][t],
                    ),
                )
            end
        end
    end
    sort!(tables["residuals.csv"]; by = x->(x.scope, x.id, x.entity, x.t, x.residual))
    tables
end
