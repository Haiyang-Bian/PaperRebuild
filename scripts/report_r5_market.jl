using PaperRebuild, TOML, CSV, SHA
length(ARGS)==2 || error("参数：完整study.toml 新报告目录")
manifest=abspath(ARGS[1])
output=abspath(ARGS[2])
ispath(output) && error("不覆盖市场报告")
study=TOML.parsefile(manifest)
study["schema"]=="r5-market-study-v1" && study["complete"] || error("市场批次未完成")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "market", "study.toml")
bytes2hex(sha256(read(config)))==study["config_sha256"] || error("冻结规则变化")
rules=TOML.parsefile(config)
rules==study["rules"] || error("运行规则不一致")
expected=Dict(x["id"]=>x for x in rules["records"])
length(expected)==length(study["records"]) &&
Set(keys(expected))==Set(x["id"] for x in study["records"]) || error("批次清单缺失/重复")
summary=NamedTuple[]
residuals=NamedTuple[]
prices=NamedTuple[]
dispatch=NamedTuple[]
flows=NamedTuple[]
components=NamedTuple[]
comparisons=NamedTuple[]
source_hashes=Dict{String,String}()
loaded_runs=Dict{String,Any}()
for x in study["records"]
    id=x["id"]
    x["solver"]==expected[id]["solver"] && x["case"]==expected[id]["case"] || error("实验因素变化")
    path=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"] ||
        error("原结果改变")
    loaded=read_r5_market_run(path)
    loaded_runs[id]=loaded
    c, r, v=loaded.case, loaded.result, loaded.validation
    c.sha256==x["case_sha256"]==rules["input_sha256"][x["case"]] || error("输入身份变化")
    source_hashes[id]=x["result_sha256"]
    candidate=haskey(r, "values")
    certificate=r["independent_dual"]
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
            kkt_pass = v["kkt_pass"],
            optimality_pass = v["optimality_pass"],
            cost_optimization_complete = r["cost_optimization_complete"],
            objective = get(v, "clearing_objective", NaN),
            dual_value = get(v, "dual_value", NaN),
            relative_gap = get(v, "relative_gap", NaN),
            independent_dual_pass = certificate["verified"],
            independent_dual_status = certificate["status"],
            independent_dual_value = get(certificate, "objective", NaN),
            independent_dual_gap = get(certificate, "relative_gap", NaN),
            elapsed_sec = r["elapsed_sec"],
            total_method_elapsed_sec = r["total_method_elapsed_sec"],
        ),
    )
    for z in v["rows"]
        push!(
            residuals,
            (;
                record_id = id,
                run_id = r["run_id"],
                case = x["case"],
                solver = x["solver"],
                id = z["id"],
                scope = z["scope"],
                entity = z["entity"],
                t = z["t"],
                residual = z["residual"],
                unit = z["unit"],
                tolerance = z["tolerance"],
                normalized = z["residual"]/z["tolerance"],
                pass = z["pass"],
            ),
        )
    end
    candidate || continue
    d=c.data
    T=d["T"]
    dt=d["dt_h"]
    s=r["values"]
    for b in 1:d["nodes"], t in 1:T
        haskey(v, "LMP_USD_MWh") || continue
        push!(
            prices,
            (;
                record_id = id,
                run_id = r["run_id"],
                case = x["case"],
                solver = x["solver"],
                node = b,
                t,
                dt_h = dt,
                certified = v["kkt_pass"],
                LMP_USD_MWh = v["LMP_USD_MWh"][b][t],
                up_price_USD_MW_h = v["reserve_up_price"][t],
                down_price_USD_MW_h = v["reserve_down_price"][t],
            ),
        )
    end
    for (kind, P, U, D) in
        (("generators", "P_G", "R_G_up", "R_G_down"), ("ies", "P_IES", "R_IES_up", "R_IES_down"))
        for (i, a) in enumerate(d[kind]), t in 1:T
            push!(
                dispatch,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    case = x["case"],
                    solver = x["solver"],
                    kind,
                    actor = a["id"],
                    node = a["node"],
                    t,
                    dt_h = dt,
                    P_MW = s[P][i][t],
                    up_MW = s[U][i][t],
                    down_MW = s[D][i][t],
                ),
            )
        end
    end
    for l in eachindex(d["network"]["limit_MW"]), t in 1:T
        push!(
            flows,
            (;
                record_id = id,
                run_id = r["run_id"],
                case = x["case"],
                solver = x["solver"],
                line = l,
                t,
                flow_MW = v["flow_MW"][l][t],
                limit_MW = d["network"]["limit_MW"][l],
            ),
        )
    end
    for (kind, energy_key, up_key, down_key, energy_sign) in (
        ("generators", "P_G", "R_G_up", "R_G_down", 1.0),
        ("ies", "P_IES", "R_IES_up", "R_IES_down", -1.0),
    )
        for (label, bid, key, sign) in (
            ("energy", "energy_bid", energy_key, energy_sign),
            ("up", "up_bid", up_key, 1.0),
            ("down", "down_bid", down_key, 1.0),
        )
            amount=sum(
                dt*sign*a[bid][t]*s[key][i][t] for (i, a) in enumerate(d[kind]), t in 1:T;
                init = 0.0,
            )
            push!(
                components,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    case = x["case"],
                    solver = x["solver"],
                    component = kind*"_"*label,
                    amount_USD = amount,
                ),
            )
        end
    end
end
for name in sort!(collect(keys(rules["input_sha256"])))
    left=name*"--highs"
    for solver in ("clarabel", "gurobi")
        right=name*"--"*solver
        haskey(loaded_runs, right) || continue
        compare=compare_r5_market_runs(
            joinpath(dirname(manifest), left),
            joinpath(dirname(manifest), right),
        )
        push!(
            comparisons,
            (;
                case = name,
                left_record = left,
                right_record = right,
                comparable = compare["comparable"],
                relative_objective_difference = get(compare, "relative_objective_difference", NaN),
                A2_pass = compare["A2_pass"],
            ),
        )
    end
end
mkpath(output)
for (name, rows, headers) in (
    (
        "comparison.csv",
        summary,
        [
            "record_id",
            "run_id",
            "case",
            "solver",
            "case_sha256",
            "status",
            "candidate",
            "model_pass",
            "kkt_pass",
            "optimality_pass",
            "cost_optimization_complete",
            "objective",
            "dual_value",
            "relative_gap",
            "independent_dual_pass",
            "independent_dual_status",
            "independent_dual_value",
            "independent_dual_gap",
            "elapsed_sec",
            "total_method_elapsed_sec",
        ],
    ),
    (
        "residuals.csv",
        residuals,
        [
            "record_id",
            "run_id",
            "case",
            "solver",
            "id",
            "scope",
            "entity",
            "t",
            "residual",
            "unit",
            "tolerance",
            "normalized",
            "pass",
        ],
    ),
    (
        "prices.csv",
        prices,
        [
            "record_id",
            "run_id",
            "case",
            "solver",
            "node",
            "t",
            "dt_h",
            "certified",
            "LMP_USD_MWh",
            "up_price_USD_MW_h",
            "down_price_USD_MW_h",
        ],
    ),
    (
        "dispatch.csv",
        dispatch,
        [
            "record_id",
            "run_id",
            "case",
            "solver",
            "kind",
            "actor",
            "node",
            "t",
            "dt_h",
            "P_MW",
            "up_MW",
            "down_MW",
        ],
    ),
    (
        "flows.csv",
        flows,
        ["record_id", "run_id", "case", "solver", "line", "t", "flow_MW", "limit_MW"],
    ),
    (
        "objective-components.csv",
        components,
        ["record_id", "run_id", "case", "solver", "component", "amount_USD"],
    ),
    (
        "solver-comparison.csv",
        comparisons,
        [
            "case",
            "left_record",
            "right_record",
            "comparable",
            "relative_objective_difference",
            "A2_pass",
        ],
    ),
)
    if isempty(rows)
        write(joinpath(output, name), join(headers, ",")*"\n")
    else
        CSV.write(joinpath(output, name), rows)
    end
end
meta=Dict(
    "schema"=>"r5-market-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "scope"=>rules["objective"],
    "source_commit"=>study["source_commit"],
    "raw_source_hashes"=>source_hashes,
    "required"=>length(expected),
    "saved"=>length(summary),
    "model_pass"=>count(x->x.model_pass, summary),
    "kkt_pass"=>count(x->x.kkt_pass, summary),
    "cost_complete"=>count(x->x.cost_optimization_complete, summary),
    "independent_dual_pass"=>count(x->x.independent_dual_pass, summary),
    "config_sha256"=>study["config_sha256"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "producer_sha256"=>study["producer_sha256"],
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Market report: ",
    length(summary),
    " records, ",
    length(residuals),
    " independent residuals; no solve.",
)
