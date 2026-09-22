using PaperRebuild, TOML, CSV, SHA
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
study_path=abspath(ARGS[1]);
study=TOML.parsefile(study_path)
root=normpath(joinpath(@__DIR__, ".."));
batch=dirname(study_path)
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-network")
ispath(output) && error("不覆盖报告")
config=joinpath(root, "configs", "r4", "reconfiguration", "study.toml")
bytes2hex(sha256(read(config)))==study["config_sha256"] || error("冻结规则改变")
rules=study["rules"];
length(study["records"])==34 || error("整数运行清单缺失")
runs=Dict{Tuple{String,String,String},Any}()
for x in study["records"]
    id=x["id"]
    path=joinpath(batch, id)
    bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"] ||
        error("原始结果哈希变化")
    loaded=read_r4_run(path)
    loaded.case.sha256==rules["input_sha256"][x["case"]]==x["input_sha256"] || error("输入不同")
    key=(x["case"], x["policy"], x["electric"])
    haskey(runs, key) && error("重复运行")
    loaded.result["reconfiguration"]["policy"]==x["policy"] &&
    loaded.result["spec"]["electric"]==x["electric"] || error("模型选择不同")
    runs[key]=loaded
end
oracle_path=joinpath(batch, "oracle-enumeration")
bytes2hex(sha256(read(joinpath(oracle_path, "result.toml"))))==study["oracle_result_sha256"] ||
    error("枚举源变化")
oracle=read_r4_network_enumeration(oracle_path)
summary=NamedTuple[];
residuals=NamedTuple[];
dispatch=NamedTuple[];
topology=NamedTuple[]
embedding=NamedTuple[];
diagnostics=NamedTuple[]
for x in study["records"]
    name, policy, electric=(x[k] for k in ("case", "policy", "electric"))
    loaded=runs[(name, policy, electric)]
    c=loaded.case
    r=loaded.result
    v=loaded.validation
    id=x["id"]
    d=c.data
    T=d["T"]
    dt=d["dt_h"]
    mp=v["model_pass"]
    pp=mp&&v["electric_original_pass"]
    cost=get(r, "operating_cost", NaN)
    switch=get(r, "switching_cost", NaN)
    available=dt*sum(a["PV_max"]*sum(a["PV_profile"]) for a in d["actors"])
    used=NaN
    eloss=NaN
    hloss=NaN
    ea=NaN
    ha=NaN
    resource=NaN
    discomfort=NaN
    external=NaN
    for row in v["rows"]
        push!(
            residuals,
            (;
                run_id = id,
                case = name,
                policy,
                electric,
                equation = row["equation"],
                scope = row["scope"],
                entity = string(row["entity"]),
                t = row["t"],
                residual = row["residual"],
                tolerance = row["tolerance"],
                normalized = abs(row["residual"])/row["tolerance"],
                pass = row["pass"],
                unit = row["unit"],
            ),
        )
    end
    if haskey(r, "values")
        s=r["values"]
        resource=sum(a["resource"] for a in r["ledger"]["actors"])-switch
        discomfort=sum(a["dissatisfaction"] for a in r["ledger"]["actors"])
        external=sum(a["external"] for a in r["ledger"]["actors"])
        used=dt*sum(sum(x) for x in s["P_PV"])
        eloss=dt*d["electric"]["S_base_MVA"]*sum(
            e["r"]*sum(s["ell"][p]) for (p, e) in enumerate(d["electric"]["edges"])
        )
        hloss=dt*sum(sum(s["H_in"][p])-sum(s["H_out"][p]) for p in eachindex(d["heat"]["pipes"]))
        ea=sum(sum(a) for a in s["a_E"])
        ha=sum(s["a_H"])
        for i in 1:3, t in 1:T
            push!(
                dispatch,
                (;
                    run_id = id,
                    case = name,
                    policy,
                    electric,
                    actor = d["actors"][i]["id"],
                    t,
                    CHP_MW = s["P_CHP"][i][t],
                    PV_MW = s["P_PV"][i][t],
                    HP_MW = s["P_HP"][i][t],
                    EB_MW = s["P_EB"][i][t],
                    charge_MW = s["P_ch"][i][t],
                    discharge_MW = s["P_dis"][i][t],
                    P_D_MW = s["P_D"][i][t],
                    H_D_MW = s["H_D"][i][t],
                ),
            )
        end
        for p in 1:3, t in 1:T
            edge=d["electric"]["edges"][p]
            pipe=d["heat"]["pipes"][p]
            push!(
                topology,
                (;
                    run_id = id,
                    case = name,
                    policy,
                    electric,
                    edge = p,
                    from = edge["from"],
                    to = edge["to"],
                    t,
                    u_E = s["u_E"][p][t],
                    a_E = s["a_E"][p][t],
                    P_MW = s["P_branch"][p][t]*d["electric"]["S_base_MVA"],
                    u_H = s["u_H"][p],
                    a_H = s["a_H"][p],
                    direction = s["u_H_arc"][p][t]-s["u_H_arc"][p+3][t],
                    H_in_MW = s["H_in"][p][t]-s["H_in"][p+3][t],
                    heat_loss_MW = s["H_in"][p][t]-s["H_out"][p][t]+s["H_in"][p+3][t]-s["H_out"][p+3][t],
                ),
            )
        end
        for p in eachindex(d["heat"]["pipes"]), t in 1:T
            # 仅额外报告简化热模型未约束的诊断，不能据此悄悄改变既有A1。
            push!(
                diagnostics,
                (;
                    run_id = id,
                    pipe = p,
                    t,
                    mass_kg_s = s["m_pipe"][p][t],
                    heat_MW = s["H_in"][p][t],
                    positive_heat_near_zero_mass = s["H_in"][p][t]>1e-6&&abs(s["m_pipe"][p][t])<=1e-6,
                ),
            )
        end
    end
    fixed=get(runs, (name, "fixed", electric), nothing)
    physical_saving=pp&&fixed!==nothing&&fixed.validation["model_pass"]&&fixed.validation["electric_original_pass"] ?
                    fixed.result["operating_cost"]-cost : NaN
    fraction=isfinite(physical_saving) ?
             physical_saving/max(1, abs(fixed.result["operating_cost"])) : NaN
    push!(
        summary,
        (;
            run_id = id,
            case = name,
            policy,
            electric,
            status = r["status"],
            model_A1 = mp,
            original_electric_A1 = pp,
            heat_A1 = v["heat_pass"],
            ledger_A1 = v["ledger_pass"],
            cost,
            resource_cost = resource,
            discomfort_cost = discomfort,
            external_cost = external,
            switching_cost = switch,
            objective_bound = get(r, "objective_bound", NaN),
            relative_gap = get(r, "relative_gap", NaN),
            certificate_A2 = r["cost_optimization_complete"]&&mp,
            PV_available_MWh = available,
            PV_used_MWh = used,
            PV_curtailed_MWh = available-used,
            electric_loss_MWh = eloss,
            heat_loss_MWh = hloss,
            electric_actions = ea,
            valve_actions = ha,
            electric_checked_saving = physical_saving,
            electric_checked_saving_fraction = fraction,
            elapsed_sec = r["elapsed_sec"],
            budget_sec = r["budget_sec"],
            input_sha256 = c.sha256,
            unit = "USD_synthetic",
        ),
    )
end
for name in rules["cases"],
    electric in rules["electric_models"],
    (from, to) in (
        ("fixed", "electric"),
        ("fixed", "heat"),
        ("fixed", "joint"),
        ("electric", "joint"),
        ("heat", "joint"),
    )

    z=runs[(name, from, electric)]
    raw=deepcopy(z.result)
    raw["reconfiguration"]["policy"]=to
    v=validate_r4_reconfiguration(z.case, raw)
    z.validation["model_pass"]&&!v["model_pass"] && error("受限解不能嵌入自由策略")
    push!(
        embedding,
        (;
            case = name,
            electric,
            source_policy = from,
            target_policy = to,
            model_A1 = v["model_pass"],
            original_electric_A1 = v["electric_original_pass"],
        ),
    )
end
om=NamedTuple[]
for (i, x) in enumerate(oracle.result["records"])
    raw=get(x, "raw", Dict{String,Any}())
    v=get(raw, "validation", Dict{String,Any}())
    push!(
        om,
        (;
            index = i,
            electric_tree = join(x["electric"]),
            heat_tree = join(x["heat"]),
            direction = join(only.(x["directions"])),
            battery = only(x["mode"]),
            status = x["status"],
            model_A1 = get(v, "model_pass", false),
            original_electric_A1 = get(v, "electric_original_pass", false),
            cost = get(raw, "operating_cost", NaN),
            bound = get(raw, "objective_bound", NaN),
        ),
    )
end
mip=runs[("oracle", "joint", "socp")]
same_model_error=abs(mip.result["operating_cost"]-oracle.result["best_model_cost"])/max(
    1,
    abs(oracle.result["best_model_cost"]),
)
checks=Dict(
    "oracle"=>oracle.validation,
    "oracle_same_model_relative_difference"=>same_model_error,
    "oracle_A2_pass"=>oracle.validation["certificate_A2"]&&mip.result["cost_optimization_complete"]&&same_model_error<=1e-4,
    "integer_count"=>length(summary),
    "embedding_count"=>length(embedding),
    "model_pass_count"=>count(x->x.model_A1, summary),
    "original_pass_count"=>count(x->x.original_electric_A1, summary),
    "heat_mass_screen_count"=>count(x->x.positive_heat_near_zero_mass, diagnostics),
    "heat_mass_screen_runs"=>length(
        unique(x.run_id for x in diagnostics if x.positive_heat_near_zero_mass),
    ),
    "heat_mass_screen_max_heat_MW"=>maximum(
        x.heat_MW for x in diagnostics if x.positive_heat_near_zero_mass;
        init = 0.0,
    ),
    "heat_mass_screen_rule"=>"H_in>1e-6 MW and abs(m)<=1e-6 kg/s; diagnostic outside old A1",
    "raw_source_hashes"=>Dict(x["id"]=>x["result_sha256"] for x in study["records"]),
)
mkpath(output)
for (name, rows) in (
    ("comparison.csv", summary),
    ("residuals.csv", residuals),
    ("dispatch.csv", dispatch),
    ("topology.csv", topology),
    ("embedding.csv", embedding),
    ("oracle.csv", om),
    ("thermal-diagnostic.csv", diagnostics),
)
    CSV.write(joinpath(output, name), rows)
end
write(joinpath(output, "checks.toml"), PaperRebuild.r4_text(checks))
meta=Dict(
    "batch_id"=>study["batch_id"],
    "origin"=>"synthetic",
    "source_commit"=>study["source_commit"],
    "config_sha256"=>study["config_sha256"],
    "study_sha256"=>bytes2hex(sha256(read(study_path))),
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "cases"=>rules["cases"],
    "policies"=>rules["policies"],
    "scope"=>"three electric/heat nodes, four periods, static heat energy flow, free terminal topology",
    "integer_count"=>length(summary),
    "oracle_records"=>length(om),
)
write(joinpath(output, "report.toml"), PaperRebuild.r4_text(meta))
println(
    "R4 network report: ",
    length(summary),
    " integer runs; ",
    length(om),
    " oracle rows; physical=",
    checks["original_pass_count"],
)
