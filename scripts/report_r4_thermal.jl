using PaperRebuild, TOML, CSV, SHA
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
manifest=abspath(ARGS[1])
study=TOML.parsefile(manifest)
root=normpath(joinpath(@__DIR__, ".."))
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-thermal")
ispath(output) && error("不覆盖报告")
study["schema"]=="r4-thermal-study-v1" && study["complete"] || error("批次未完成")
config=joinpath(root, "configs", "r4", "thermal-study.toml")
bytes2hex(sha256(read(config)))==study["config_sha256"] || error("实验规则变化")
rules=study["rules"]
expected=Set(x["id"] for x in rules["records"])
length(study["records"])==length(expected) && Set(x["id"] for x in study["records"])==expected ||
    error("正式运行清单缺失或重复")
summary=NamedTuple[]
residuals=NamedTuple[]
states=NamedTuple[]
nodes=NamedTuple[]
source_hashes=Dict{String,String}()
for x in study["records"]
    id=x["id"]
    path=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"] ||
        error("原结果改变")
    loaded=read_r4_run(path)
    c, r, v=loaded.case, loaded.result, loaded.validation
    c.sha256==x["input_sha256"]==rules["input_sha256"][x["case"]] || error("输入变化")
    r["thermal"]["loss"]==x["loss"] && r["thermal"]["policy"]==x["policy"] || error("模型变化")
    r["thermal"]["supply_K"]==rules["supply_K"] &&
    r["thermal"]["return_K"]==rules["return_K"] &&
    r["thermal"]["flow_floor"]==rules["flow_floor"] || error("边界变化")
    source_hashes[id]=x["result_sha256"]
    maximum_residual=isempty(v["rows"]) ? NaN :
                     maximum(z["residual"]/z["tolerance"] for z in v["rows"])
    candidate=haskey(r, "values")
    heat_loss=NaN
    idle_steps=0
    active_steps=0
    used_PV=NaN
    if candidate
        s=r["values"]
        T=c.data["T"]
        dt=c.data["dt_h"]
        heat_loss=dt*sum(s["H_in"][p][t]-s["H_out"][p][t] for p in 1:6, t in 1:T)
        used_PV=dt*sum(s["P_PV"][i][t] for i in 1:3, t in 1:T)
        for p in 1:3, t in 1:T
            open=s["u_H"][p]>0.5
            running=s["u_H_arc"][p][t]+s["u_H_arc"][p+3][t]>0.5
            idle_steps+=open&&!running
            active_steps+=running
        end
        for (p, pipe) in enumerate(c.data["heat"]["pipes"]), t in 1:T
            active=s["u_H_arc"][p][t]>0.5
            i, j=pipe["from"], pipe["to"]
            push!(
                states,
                (;
                    run_id = id,
                    case = x["case"],
                    policy = x["policy"],
                    loss = x["loss"],
                    pipe = p,
                    from = i,
                    to = j,
                    t,
                    active,
                    m_kg_s = s["m_pipe"][p][t],
                    H_in_MW = s["H_in"][p][t],
                    H_out_MW = s["H_out"][p][t],
                    loss_MW = s["H_in"][p][t]-s["H_out"][p][t],
                    S_in_K = active ? s["τ_S"][i][t] : NaN,
                    S_out_K = active ? s["τ_S_out"][p][t] : NaN,
                    R_in_K = active ? s["τ_R"][j][t] : NaN,
                    R_out_K = active ? s["τ_R_out"][p][t] : NaN,
                ),
            )
        end
        for i in 1:3, t in 1:T
            push!(
                nodes,
                (;
                    run_id = id,
                    case = x["case"],
                    policy = x["policy"],
                    loss = x["loss"],
                    node = i,
                    t,
                    H_src_MW = s["H_src"][i][t],
                    H_D_MW = s["H_D"][i][t],
                    P_CHP_MW = s["P_CHP"][i][t],
                    P_HP_MW = s["P_HP"][i][t],
                    P_EB_MW = s["P_EB"][i][t],
                    P_PV_MW = s["P_PV"][i][t],
                    source_mass_kg_s = s["m_source"][i][t],
                    load_mass_kg_s = s["m_load"][i][t],
                    S_K = s["τ_S"][i][t],
                    R_K = s["τ_R"][i][t],
                ),
            )
        end
    end
    push!(
        summary,
        (;
            run_id = id,
            case = x["case"],
            policy = x["policy"],
            loss = x["loss"],
            candidate,
            status = r["status"],
            model_pass = v["model_pass"],
            electric_original_pass = v["electric_original_pass"],
            heat_pass = v["heat_pass"],
            ledger_pass = v["ledger_pass"],
            adopted_physical_pass = v["model_pass"]&&v["electric_original_pass"],
            operating_cost = get(r, "operating_cost", NaN),
            solver_objective = get(r, "solver_objective", NaN),
            objective_bound = get(r, "objective_bound", NaN),
            relative_gap = get(r, "relative_gap", NaN),
            cost_optimization_complete = r["cost_optimization_complete"],
            max_normalized_residual = maximum_residual,
            heat_loss_MWh = heat_loss,
            used_PV_MWh = used_PV,
            active_pipe_steps = active_steps,
            idle_open_pipe_steps = idle_steps,
            elapsed_sec = r["elapsed_sec"],
            switching_cost = get(r, "switching_cost", NaN),
        ),
    )
    for z in v["rows"]
        push!(
            residuals,
            (;
                run_id = id,
                case = x["case"],
                policy = x["policy"],
                loss = x["loss"],
                equation = z["equation"],
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
end
mkpath(output)
for (name, rows) in
    (("comparison", summary), ("residuals", residuals), ("states", states), ("nodes", nodes))
    CSV.write(joinpath(output, name*".csv"), rows)
end
comparisons=NamedTuple[]
for name in keys(rules["input_sha256"]), loss in ("reference", "exponential")
    pair=[
        only(filter(x->x.case==name&&x.loss==loss&&x.policy==p, summary)) for
        p in ("fixed", "joint")
    ]
    a, b=pair
    valid=a.adopted_physical_pass&&b.adopted_physical_pass
    # 不同最优解/松弛版本的费用不能拼成界；这里只算已验算候选的同模型差。
    push!(
        comparisons,
        (;
            case = name,
            loss,
            fixed_run = a.run_id,
            joint_run = b.run_id,
            eligible = valid,
            fixed_cost = a.operating_cost,
            joint_cost = b.operating_cost,
            candidate_saving = valid ? a.operating_cost-b.operating_cost : NaN,
            candidate_saving_percent = valid ?
                                       100*(a.operating_cost-b.operating_cost)/abs(
                a.operating_cost,
            ) : NaN,
            both_cost_complete = a.cost_optimization_complete&&b.cost_optimization_complete,
            saving_bound_lower = valid && isfinite(a.objective_bound) ?
                                 a.objective_bound-b.operating_cost : NaN,
            saving_bound_upper = valid && isfinite(b.objective_bound) ?
                                 a.operating_cost-b.objective_bound : NaN,
        ),
    )
end
CSV.write(joinpath(output, "policy-comparison.csv"), comparisons)
legacy=NamedTuple[]
legacy_hashes=Dict{String,String}()
for x in summary
    parent_id=x.case*"--"*x.policy*"--exact"
    path=joinpath(root, "results", "runs", "r4", rules["parent_batch"], parent_id)
    parent=read_r4_run(path)
    parent.case.sha256==rules["input_sha256"][x.case] || error("父运行输入不同")
    legacy_hashes[parent_id]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    push!(
        legacy,
        (;
            run_id = x.run_id,
            parent_run_id = parent_id,
            case = x.case,
            policy = x.policy,
            loss = x.loss,
            legacy_cost = parent.result["operating_cost"],
            new_cost = x.operating_cost,
            new_minus_legacy = x.candidate ? x.operating_cost-parent.result["operating_cost"] : NaN,
            legacy_energy_model_pass = parent.validation["model_pass"],
            legacy_electric_pass = parent.validation["electric_original_pass"],
            new_steady_pass = x.adopted_physical_pass,
            interpretation = "Combined idle-temperature-mixing model change; not a same-model optimality gap",
        ),
    )
end
CSV.write(joinpath(output, "legacy-comparison.csv"), legacy)
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "schema"=>"r4-thermal-report-v1",
            "origin"=>"synthetic",
            "batch_id"=>study["batch_id"],
            "source_commit"=>study["source_commit"],
            "config_sha256"=>study["config_sha256"],
            "study_sha256"=>bytes2hex(sha256(read(manifest))),
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "raw_source_hashes"=>source_hashes,
            "legacy_source_hashes"=>legacy_hashes,
            "cases"=>sort(collect(keys(rules["input_sha256"]))),
            "scope"=>"Decoupled steady operating pipes; no idle cooling, restart, pressure or pump cost.",
            "required"=>length(expected),
            "saved"=>length(summary),
            "model_pass"=>count(x->x.model_pass, summary),
            "adopted_physical_pass"=>count(x->x.adopted_physical_pass, summary),
            "cost_complete"=>count(x->x.cost_optimization_complete, summary),
        ),
    ),
)
println(
    "Saved ",
    length(summary),
    " runs and ",
    length(residuals),
    " independent residuals to ",
    output,
)
