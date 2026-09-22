using PaperRebuild, TOML, CSV, SHA

function report_r5_dispatch(manifest, output)
    ispath(output)&&error("不覆盖既有IES报告")
    study=TOML.parsefile(manifest)
    study["schema"]=="r5-dispatch-study-v1" && study["complete"] || error("IES批次未完成")
    root=normpath(joinpath(@__DIR__, ".."))
    config=joinpath(root, "configs", "r5", "dispatch", "study.toml")
    rules=TOML.parsefile(config)
    rules==study["rules"] && bytes2hex(sha256(read(config)))==study["config_sha256"] ||
        error("冻结规则变化")
    expected=Dict(x["id"]=>x for x in rules["records"])
    length(study["records"])==length(expected) &&
    Set(x["id"] for x in study["records"])==Set(keys(expected)) || error("正式清单不完整")
    summary, residuals, dispatch, buildings, pipes, components, comparisons=(
        NamedTuple[] for _ in 1:7
    )
    sources=Dict{String,String}()
    for x in study["records"]
        id=x["id"]
        path=joinpath(dirname(manifest), id)
        x["case"]==expected[id]["case"] && x["solver"]==expected[id]["solver"] ||
            error("实验因素变化")
        bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"]||error(
            "原结果变化",
        )
        loaded=read_r5_dispatch_run(path)
        c, r, v=loaded.case, loaded.result, loaded.validation
        c.sha256==x["case_sha256"]==rules["input_sha256"][x["case"]]||error("输入变化")
        sources[id]=x["result_sha256"]
        candidate=haskey(r, "values")
        push!(
            summary,
            (;
                record_id = id,
                run_id = r["run_id"],
                case = x["case"],
                solver = x["solver"],
                case_sha256 = c.sha256,
                status = r["status"],
                candidate,
                model_pass = v["model_pass"],
                electric_pass = v["linear_electric_pass"],
                heat_pass = v["fixed_flow_heat_pass"],
                comfort_pass = v["comfort_pass"],
                delivery_pass = v["delivery_pass"],
                auxiliary_exact_pass = v["auxiliary_exact_pass"],
                cost_pass = v["cost_pass"],
                cost_complete = r["cost_optimization_complete"],
                objective = get(v, "operating_net_cost", NaN),
                bound = get(r, "solver_objective_bound", NaN),
                relative_gap = get(v, "relative_gap", NaN),
                elapsed_sec = r["elapsed_sec"],
                mismatch_MWh = get(v, "mismatch_MWh", NaN),
                mismatch_limit_MWh = get(v, "mismatch_limit_MWh", NaN),
                maximum_normalized_residual = isempty(v["rows"]) ? NaN :
                                              maximum(z["normalized"] for z in v["rows"]),
            ),
        )
        for z in v["rows"]
            push!(
                residuals,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    id = z["id"],
                    group = z["group"],
                    entity = z["entity"],
                    t = z["t"],
                    residual = z["residual"],
                    unit = z["unit"],
                    tolerance = z["tolerance"],
                    normalized = z["normalized"],
                    pass = z["pass"],
                ),
            )
        end
        candidate||continue
        d=c.data
        s=r["values"]
        T=d["T"]
        for t in 1:T
            push!(
                dispatch,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    t,
                    dt_h = d["dt_h"],
                    P_DA_MW = d["award"]["P_DA_MW"][t],
                    P_actual_MW = s["P_PCC"][1][t],
                    request_MW = v["request_MW"][t],
                    delivered_MW = v["delivered_MW"][t],
                    mismatch_MW = v["mismatch_MW"][t],
                    R_up_MW = d["award"]["R_up_MW"][t],
                    R_down_MW = d["award"]["R_down_MW"][t],
                ),
            )
            for (j, b) in enumerate(d["buildings"])
                push!(
                    buildings,
                    (;
                        record_id = id,
                        run_id = r["run_id"],
                        building = b["id"],
                        t,
                        T_IN_K = s["τ_IN"][j][t],
                        T_min_K = b["T_min_K"],
                        T_max_K = b["T_max_K"],
                        H_district_MW = s["H_D"][j][t],
                        H_local_MW = b["COP_DH"]*s["P_DH"][j][t],
                        P_local_MW = s["P_DH"][j][t],
                    ),
                )
            end
            for (p, z) in enumerate(d["heat"]["pipes"]), side in ("S", "R")
                node=side=="S" ? z["from"] : z["to"]
                replay=PaperRebuild.r5_dispatch_pipe_replay(
                    z,
                    d["heat"],
                    d["dt_h"],
                    t,
                    s["τ_$side"][node],
                    d["ambient_K"][t],
                    side,
                )
                push!(
                    pipes,
                    (;
                        record_id = id,
                        run_id = r["run_id"],
                        pipe = z["id"],
                        side,
                        t,
                        T_in_K = s["τ_$side"][node][t],
                        T_out_K = s["τ_pipe_$side"][p][t],
                        replay_K = replay.temperature,
                        m_kg_s = z["m_kg_s"],
                        weight_sum = replay.weight_sum,
                    ),
                )
            end
        end
        for key in ("day_ahead_cost", "device_cost", "real_time_settlement", "delivery_penalty")
            push!(
                components,
                (; record_id = id, run_id = r["run_id"], component = key, amount_USD = v[key]),
            )
        end
    end
    for name in sort!(collect(keys(rules["input_sha256"])))
        rows=filter(x->x.case==name, summary)
        base=only(filter(x->x.solver=="highs", rows))
        for other in rows
            other.solver=="highs"&&continue
            comparable=base.candidate&&other.candidate
            gap=comparable ?
                abs(base.objective-other.objective)/max(
                1,
                abs(base.objective),
                abs(other.objective),
            ) : NaN
            push!(
                comparisons,
                (;
                    case = name,
                    left = base.record_id,
                    right = other.record_id,
                    comparable,
                    relative_objective_difference = gap,
                    A2_pass = comparable&&base.cost_complete&&other.cost_complete&&gap<=1e-4,
                ),
            )
        end
    end
    mkpath(output)
    for (file, rows) in (
        ("comparison.csv", summary),
        ("residuals.csv", residuals),
        ("dispatch.csv", dispatch),
        ("buildings.csv", buildings),
        ("pipes.csv", pipes),
        ("cost-components.csv", components),
        ("solver-comparison.csv", comparisons),
    )
        CSV.write(joinpath(output, file), rows)
    end
    meta=Dict(
        "schema"=>"r5-dispatch-report-v1",
        "origin"=>"synthetic",
        "batch_id"=>study["batch_id"],
        "source_commit"=>study["source_commit"],
        "study_sha256"=>bytes2hex(sha256(read(manifest))),
        "config_sha256"=>study["config_sha256"],
        "raw_source_hashes"=>sources,
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "records"=>length(summary),
        "model_pass"=>count(x->x.model_pass, summary),
        "cost_complete"=>count(x->x.cost_complete, summary),
        "source_scope"=>"Linear electric model, fixed positive flow with author node-method attenuation, hard building comfort; not AC/hydraulic or risk certification.",
    )
    write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
    println(
        "IES report: ",
        length(summary),
        " records, ",
        length(residuals),
        " residuals; model=",
        meta["model_pass"],
        ", cost=",
        meta["cost_complete"],
    )
end
length(ARGS)==2||error("参数：完整study.toml 新报告目录")
report_r5_dispatch(abspath(ARGS[1]), abspath(ARGS[2]))
