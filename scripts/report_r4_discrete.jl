# 只读完整存档生成比较，不求解、不改原始模式或失败状态。
using PaperRebuild, TOML, SHA, CSV
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
root=normpath(joinpath(@__DIR__, ".."))
studyfile=abspath(ARGS[1]);
dir=dirname(studyfile)
study=TOML.parsefile(studyfile)
config=joinpath(root, "configs", "r4", "discrete-study.toml")
rules=TOML.parsefile(config)
bytes2hex(sha256(read(config)))==study["config_sha256"] || error("冻结规则改变")
hs=TOML.parsefile(joinpath(dir, "batch-hashes.toml"))["sha256"]
actual=Set(
    replace(relpath(joinpath(d, f), dir), '\\'=>'/') for (d, _, fs) in walkdir(dir) for
    f in fs if f!="batch-hashes.toml"
)
actual==Set(keys(hs)) || error("批次文件清单改变")
for (rel, h) in hs
    !isabspath(rel)&&!(".." in split(rel, '/')) || error("非法路径")
    bytes2hex(sha256(read(joinpath(dir, rel))))==h || error("批次文件哈希改变")
end
length(study["records"])==20 || error("20项完整方法/精度对照缺失")
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-discrete")
ispath(output) && error("不覆盖报告")
runs=Dict{Tuple{String,String},Any}()
for entry in study["records"]
    path=joinpath(dir, entry["id"])
    method=entry["method"]
    reader=startswith(method, "precision_") ? read_r4_distributed_run :
           method in ("distributed", "central_enumeration") ? read_r4_discrete_run : read_r4_run
    loaded=reader(path)
    loaded.case.sha256==entry["input_sha256"]==rules["input_sha256"][entry["case"]] ||
        error("输入比较不一致")
    key=(entry["case"], method)
    haskey(runs, key) && error("重复配置")
    runs[key]=loaded
end
summary=NamedTuple[];
modes=NamedTuple[];
residuals=NamedTuple[];
trajectory=NamedTuple[]
dispatch=NamedTuple[];
evidence=Dict{String,Any}[]
function append_candidate!(name, method, id, index, c, candidate)
    for x in candidate["validation"]["rows"]
        push!(
            residuals,
            (
                run_id = id,
                case = name,
                method,
                pattern = index,
                equation = x["equation"],
                scope = x["scope"],
                entity = string(x["entity"]),
                t = x["t"],
                residual = x["residual"],
                tolerance = x["tolerance"],
                unit = x["unit"],
                pass = x["pass"],
            ),
        )
    end
    s=candidate["values"]
    for i in 1:3, t in 1:c.data["T"]
        push!(
            dispatch,
            (
                run_id = id,
                case = name,
                method,
                pattern = index,
                actor = i,
                t,
                CHP_MW = s["P_CHP"][i][t],
                PV_MW = s["P_PV"][i][t],
                HP_MW = s["P_HP"][i][t],
                EB_MW = s["P_EB"][i][t],
                charge_MW = s["P_ch"][i][t],
                discharge_MW = s["P_dis"][i][t],
                electric_load_MW = s["P_D"][i][t],
                heat_load_MW = s["H_D"][i][t],
                energy_MWh = s["E"][i][t],
            ),
        )
    end
end
for entry in study["records"]
    name, method, id=(entry[k] for k in ("case", "method", "id"))
    loaded=runs[(name, method)]
    c, r, v=loaded.case, loaded.result, loaded.validation
    central=runs[(name, "central_enumeration")].result
    reference=central["validation"]["best_model_cost"]
    refok=central["validation"]["cost_optimization_complete"]
    cost=NaN
    physcost=NaN
    mp=false
    pp=false
    selectedphysical=false
    best=0
    bestphys=0
    accepted=0
    phycount=0
    attempted=0
    lower=NaN
    gap=NaN
    certificate=false
    totaliterations=0
    if method in ("distributed", "central_enumeration")
        best=v["best_model_index"]
        bestphys=v["best_physical_index"]
        cost=v["best_model_cost"]
        physcost=v["best_physical_cost"]
        mp=best>0
        pp=bestphys>0
        selectedphysical=mp&&v["mode_checks"][best]["electric_original_pass"]
        accepted=v["accepted_model_count"]
        phycount=v["electric_original_pass_count"]
        attempted=v["attempted_modes"]
        lower=v["objective_bound"]
        gap=v["relative_gap"]
        certificate=v["cost_optimization_complete"]
        for row in r["records"]
            j=row["index"]
            raw=get(row, "raw", Dict{String,Any}())
            check=v["mode_checks"][j]
            cand=haskey(row, "reconstruction") ? row["reconstruction"]["candidate"] : nothing
            mode_ref=central["validation"]["mode_checks"][j]
            nc=cand===nothing ? NaN : cand["operating_cost"]
            iterations=length(get(raw, "trace", []))
            totaliterations+=iterations
            push!(
                modes,
                (
                    run_id = id,
                    case = name,
                    method,
                    pattern = j,
                    mode = join(row["modes"]),
                    status = row["status"],
                    raw_A1 = get(get(raw, "validation", Dict()), "model_pass", false),
                    model_A1 = check["model_pass"],
                    electric_original_A1 = check["electric_original_pass"],
                    cost = nc,
                    central_cost = get(mode_ref, "operating_cost", NaN),
                    bound = get(raw, "objective_bound", NaN),
                    gap = get(raw, "relative_gap", NaN),
                    iterations,
                    elapsed_sec = get(raw, "elapsed_sec", 0.0),
                ),
            )
            if j==best && cand!==nothing
                append_candidate!(name, method, id, j, c, cand)
                for x in get(raw, "trace", [])
                    push!(
                        trajectory,
                        (
                            run_id = id,
                            case = name,
                            method,
                            pattern = j,
                            iteration = x["iteration"],
                            cost = x["candidate_cost"],
                            primal = x["primal"],
                            dual = x["dual"],
                            model_A1 = x["model_pass"],
                            electric_original_A1 = x["electric_original_pass"],
                        ),
                    )
                end
            end
        end
    elseif startswith(method, "precision_")
        j=findfirst(==(rules["precision_pattern"]), r4_battery_patterns(c))
        reference=central["validation"]["mode_checks"][j]["operating_cost"]
        refraw=central["records"][j]["raw"]
        refok=refraw["validation"]["model_pass"]&&get(refraw, "relative_gap", Inf)<=rules["gap_A2"]
        if haskey(r, "candidate")
            cand=reconstruct_r4_cost(c, r["candidate"])["candidate"]
            mp=v["consensus_A4_pass"]&&cand["validation"]["model_pass"]
            pp=mp&&cand["validation"]["electric_original_pass"]
            selectedphysical=pp
            cost=cand["operating_cost"]
            physcost=pp ? cost : NaN
            append_candidate!(name, method, id, j, c, cand)
        end
        attempted=1
        accepted=Int(mp)
        phycount=Int(pp)
        for x in r["trace"]
            push!(
                trajectory,
                (
                    run_id = id,
                    case = name,
                    method,
                    pattern = j,
                    iteration = x["iteration"],
                    cost = x["candidate_cost"],
                    primal = x["primal"],
                    dual = x["dual"],
                    model_A1 = x["model_pass"],
                    electric_original_A1 = x["electric_original_pass"],
                ),
            )
        end
        totaliterations=length(r["trace"])
    else
        mp=v["model_pass"]
        pp=mp&&v["electric_original_pass"]
        selectedphysical=pp
        cost=get(r, "operating_cost", NaN)
        physcost=pp ? cost : NaN
        lower=get(r, "objective_bound", NaN)
        gap=get(r, "relative_gap", NaN)
        certificate=r["cost_optimization_complete"]&&mp
        attempted=1
        accepted=Int(mp)
        phycount=Int(pp)
        haskey(r, "values")&&append_candidate!(name, method, id, 0, c, r)
    end
    difference=abs(cost-reference)/max(1, abs(reference))
    comparable=method!="central_exact"
    push!(
        summary,
        (
            run_id = id,
            case = name,
            method,
            status = r["status"],
            attempted_modes = attempted,
            accepted_model_modes = accepted,
            physical_modes = phycount,
            best_model_index = best,
            best_physical_index = bestphys,
            model_A1 = mp,
            selected_model_physical_A1 = selectedphysical,
            physical_candidate_exists = pp,
            cost,
            best_physical_cost = physcost,
            objective_bound = lower,
            relative_gap = gap,
            certificate_A2 = certificate,
            reference_cost = reference,
            same_model_comparison = comparable,
            relative_cost_difference = comparable ? difference : NaN,
            cost_A4 = comparable&&mp&&refok&&difference<=rules["relative_cost_A4"],
            total_outer_iterations = totaliterations,
            elapsed_sec = r["elapsed_sec"],
            budget_sec = get(r, "budget_sec", 600.0),
            input_sha256 = c.sha256,
            unit = "USD_synthetic",
        ),
    )
    push!(
        evidence,
        Dict(
            "run_id"=>id,
            "method"=>method,
            "case"=>name,
            "input_sha256"=>c.sha256,
            "result_sha256"=>bytes2hex(sha256(read(joinpath(dir, id, "result.toml")))),
            "validation"=>v,
            "effective_parameters"=>get(r, "effective_parameters", Dict()),
        ),
    )
end
mkpath(output)
for (name, rows) in (
    ("comparison.csv", summary),
    ("modes.csv", modes),
    ("residuals.csv", residuals),
    ("trajectory.csv", trajectory),
    ("dispatch.csv", dispatch),
)
    CSV.write(joinpath(output, name), rows)
end
write(joinpath(output, "evidence.toml"), PaperRebuild.r4_text(Dict("records"=>evidence)))
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "origin"=>"synthetic",
            "batch_id"=>basename(dir),
            "source_commit"=>study["source_commit"],
            "source_study_sha256"=>bytes2hex(sha256(read(studyfile))),
            "config_sha256"=>study["config_sha256"],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "methods"=>20,
            "mode_records"=>length(modes),
            "frozen_rules"=>rules,
        ),
    ),
)
println("Saved read-only comparison: ", output)
