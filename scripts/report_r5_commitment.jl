using PaperRebuild, TOML, CSV, SHA
length(ARGS)==2||error("参数：共同承诺study.toml 新报告目录")
manifest, output=abspath.(ARGS)
ispath(output)&&error("不覆盖共同承诺报告")
study=TOML.parsefile(manifest)
study["schema"]=="r5-commitment-study-v1"&&study["complete"]||error("共同承诺研究未完成")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "commitment", "study.toml")
rules=TOML.parsefile(config)
rules==study["rules"]&&bytes2hex(sha256(read(config)))==study["config_sha256"]||error(
    "冻结规则变化",
)
expected=Dict(x["id"]=>x for x in rules["runs"])
length(study["records"])==length(expected)&&Set(x["id"] for x in study["records"])==Set(
    keys(expected),
)||error("记录不完整或重复")
summary, residuals, commitments, scenarios, trajectories, comparisons=(NamedTuple[] for _ in 1:6)
sources=Dict{String,String}()
mkpath(joinpath(output, "witnesses"))
function emit_residual(record, run, scenario, group, id, entity, t, residual, tol, norm, pass, unit)
    push!(
        residuals,
        (;
            record_id = record,
            run_id = run,
            scenario,
            group,
            id,
            entity = string(entity),
            t,
            residual,
            tolerance = tol,
            normalized = norm,
            pass,
            unit,
        ),
    )
end
for item in study["records"]
    id=item["id"]
    item["case"]==expected[id]["case"]&&item["solver"]==expected[id]["solver"]||error(
        "实验因素变化",
    )
    path=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(path, "result.toml"))))==item["result_sha256"]||error(
        "原结果变化",
    )
    loaded=read_r5_commitment_run(path)
    c, r, v=loaded.case, loaded.result, loaded.validation
    c.sha256==item["case_sha256"]==load_r5_commitment_case(
        joinpath(dirname(config), item["case"]),
    ).sha256||error("情景输入变化")
    sources[id]=item["result_sha256"]
    push!(
        summary,
        (;
            record_id = id,
            run_id = r["run_id"],
            case = item["case"],
            solver = item["solver"],
            case_sha256 = c.sha256,
            status = r["status"],
            model_pass = v["model_pass"],
            cost_pass = v["cost_pass"],
            conditional_kkt_pass = v["conditional_kkt_pass"],
            kkt_pass = v["kkt_pass"],
            cost_complete = r["cost_optimization_complete"],
            objective = get(v, "expected_net_cost", NaN),
            bound = get(r, "solver_objective_bound", NaN),
            relative_gap = get(v, "relative_gap", NaN),
            day_ahead_cost = get(v, "day_ahead_cost", NaN),
            expected_recourse_cost = get(v, "expected_recourse_cost", NaN),
            elapsed_sec = r["elapsed_sec"],
        ),
    )
    for z in v["rows"]
        unit=z["group"]=="first_stage" ? "MW" : z["group"]=="cost" ? "USD" : "1"
        emit_residual(
            id,
            r["run_id"],
            "shared",
            z["group"],
            z["id"],
            "shared",
            0,
            z["residual"],
            z["tolerance"],
            z["normalized"],
            z["pass"],
            unit,
        )
    end
    if haskey(r, "first_stage")
        T=first(c.data["scenarios"])["case"]["T"]
        for t in 1:T
            push!(
                commitments,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    t,
                    P_DA_MW = r["first_stage"]["P_DA_MW"][t],
                    R_up_MW = r["first_stage"]["R_up_MW"][t],
                    R_down_MW = r["first_stage"]["R_down_MW"][t],
                ),
            )
        end
        for s in c.data["scenarios"]
            sid=s["id"]
            inner=v["scenarios"][sid]
            p, k=inner["validation"], inner["kkt"]
            push!(
                scenarios,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    scenario = sid,
                    probability = s["probability"],
                    model_pass = p["model_pass"],
                    kkt_pass = k["kkt_pass"],
                    recourse_cost = inner["recourse_cost"],
                    device_cost = p["device_cost"],
                    real_time_settlement = p["real_time_settlement"],
                    penalty = p["delivery_penalty"],
                    mismatch_MWh = p["mismatch_MWh"],
                    mismatch_limit_MWh = p["mismatch_limit_MWh"],
                ),
            )
            for z in p["rows"]
                emit_residual(
                    id,
                    r["run_id"],
                    sid,
                    z["group"],
                    z["id"],
                    z["entity"],
                    z["t"],
                    z["residual"],
                    z["tolerance"],
                    z["normalized"],
                    z["pass"],
                    z["unit"],
                )
            end
            for z in k["rows"]
                emit_residual(
                    id,
                    r["run_id"],
                    sid,
                    "conditional_"*z["kind"],
                    z["id"],
                    "all",
                    0,
                    z["residual"],
                    z["tolerance"],
                    z["normalized"],
                    z["pass"],
                    "1",
                )
            end
            for t in 1:T
                val=r["scenarios"][sid]["values"]
                push!(
                    trajectories,
                    (;
                        record_id = id,
                        run_id = r["run_id"],
                        scenario = sid,
                        t,
                        dt_h = s["case"]["dt_h"],
                        P_actual_MW = val["P_PCC"][1][t],
                        request_MW = p["request_MW"][t],
                        delivered_MW = p["delivered_MW"][t],
                        mismatch_MW = p["mismatch_MW"][t],
                        building_1_K = val["τ_IN"][1][t],
                        heat_1_MW = val["H_D"][1][t],
                    ),
                )
            end
        end
    end
    public=Dict(
        k=>r[k] for k in (
            "schema",
            "version",
            "case_sha256",
            "run_id",
            "status",
            "solver_objective",
            "solver_objective_bound",
            "first_stage",
            "scenarios",
            "weighted_raw_scenario_duals",
            "raw_first_stage_duals",
            "cost_optimization_complete",
            "elapsed_sec",
        ) if haskey(r, k)
    )
    witness=Dict("case"=>c.data, "result"=>public, "parent_result_sha256"=>item["result_sha256"])
    write(joinpath(output, "witnesses", id*".toml"), PaperRebuild.r5_market_text(witness))
end
for name in sort!(collect(keys(rules["files"])))
    group=filter(x->x.case==name, summary)
    reference=only(filter(x->x.solver=="highs", group))
    for other in filter(x->x.solver!="highs", group)
        comparable=reference.cost_complete&&other.cost_complete
        diff=comparable ?
             abs(reference.objective-other.objective)/max(
            1,
            abs(reference.objective),
            abs(other.objective),
        ) : NaN
        push!(
            comparisons,
            (;
                case = name,
                reference = reference.record_id,
                other = other.record_id,
                comparable,
                both_infeasible = reference.status==other.status=="solver_infeasible",
                objective_relative_difference = diff,
                A2_pass = comparable&&diff<=1e-4,
            ),
        )
    end
end
for (file, rows) in (
    ("comparison.csv", summary),
    ("residuals.csv", residuals),
    ("commitments.csv", commitments),
    ("scenarios.csv", scenarios),
    ("trajectories.csv", trajectories),
    ("solver-comparison.csv", comparisons),
)
    CSV.write(joinpath(output, file), rows)
end
meta=Dict(
    "schema"=>"r5-commitment-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "config_sha256"=>study["config_sha256"],
    "raw_result_sha256"=>sources,
    "source_sha256"=>PaperRebuild.r5_commitment_science_hashes(),
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "records"=>length(summary),
    "solver_reexecuted"=>false,
    "model_pass"=>count(x->x.model_pass, summary),
    "kkt_pass"=>count(x->x.kkt_pass, summary),
    "cost_complete"=>count(x->x.cost_complete, summary),
    "residual_count"=>length(residuals),
    "max_normalized_residual"=>maximum(x.normalized for x in residuals),
    "scope"=>"Synthetic fixed-price positive-probability expected net cost; hard comfort and full-trajectory recourse. Not bidding, DRO, online control or out-of-sample certification.",
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Shared commitment report: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model; ",
    meta["kkt_pass"],
    " KKT; ",
    length(residuals),
    " residuals.",
)
