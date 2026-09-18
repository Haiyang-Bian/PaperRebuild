# 从不可变完整运行提取比较数据；此入口没有求解器调用。
using PaperRebuild, TOML, SHA, CSV
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
root=normpath(joinpath(@__DIR__, ".."))
study_path=abspath(ARGS[1])
dir=dirname(study_path)
study=TOML.parsefile(study_path)
config=joinpath(root, "configs", "r4", "tspa-study.toml")
study["config_sha256"]==bytes2hex(sha256(read(config))) || error("冻结规则变化")
hashes=TOML.parsefile(joinpath(dir, "batch-hashes.toml"))["sha256"]
actual=Set{String}()
for (folder, _, files) in walkdir(dir), file in files
    rel=replace(relpath(joinpath(folder, file), dir), '\\'=>'/')
    rel=="batch-hashes.toml" || push!(actual, rel)
end
actual==Set(keys(hashes)) || error("批次文件清单改变")
for (rel, h) in hashes
    !isabspath(rel) && !(".." in split(rel, '/')) || error("非法文件路径")
    bytes2hex(sha256(read(joinpath(dir, rel))))==h || error("批次内容变化")
end
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-tspa")
ispath(output) && error("不覆盖已有报告")
summary=NamedTuple[]
payments=NamedTuple[]
residuals=NamedTuple[]
contracts=NamedTuple[]
records=Dict{String,Any}[]
selected_hashes=Dict{String,String}()
for entry in study["records"]
    loaded=read_r4_tspa_run(joinpath(dir, entry["id"]))
    c, r=loaded.case, loaded.result
    r["validation"]["record_pass"] || error("运行记录不一致")
    sh=bytes2hex(sha256(PaperRebuild.r4_text(r["trading_selected"]["values"])))
    if haskey(selected_hashes, entry["case"])
        selected_hashes[entry["case"]]==sh || error("罚系数对照混入不同AG控制")
    else
        selected_hashes[entry["case"]]=sh
    end
    economics=r["economics"]
    rawstrict=r["strict_network"]
    rawelastic=r["elastic_network"]
    ev=rawelastic["validation"]
    push!(
        records,
        Dict(
            "run_id"=>entry["id"],
            "case"=>entry["case"],
            "penalty"=>entry["penalty"],
            "input_sha256"=>c.sha256,
            "selected_values_sha256"=>sh,
            "economics"=>economics,
            "validation"=>r["validation"],
            "source_result_sha256"=>bytes2hex(
                sha256(read(joinpath(dir, entry["id"], "result.toml"))),
            ),
        ),
    )
    second=economics["stage2"]
    for x in (isempty(second) ? [nothing] : second)
        push!(
            summary,
            (
                run_id = entry["id"],
                case = entry["case"],
                penalty = entry["penalty"],
                variant = x===nothing ? "not_evaluated" : x["variant"],
                stage1_surplus = economics["stage1"]["surplus"],
                trading_status = r["trading_solver"]["status"],
                selection = r["selection"],
                trading_cost_complete = r["trading_solver"]["cost_optimization_complete"],
                strict_status = rawstrict["status"],
                strict_physical = r["validation"]["strict_network_physical_pass"],
                elastic_status = rawelastic["status"],
                elastic_model = r["validation"]["relaxed_network_pass"],
                elastic_physical = r["validation"]["relaxed_point_physical_pass"],
                penalty_cost = get(ev, "penalty_cost", missing),
                resource_surplus = x===nothing ? missing : x["resource_surplus"],
                stage2_surplus = x===nothing ? missing : x["allocation"]["surplus"],
                allocation_status = x===nothing ? "not_evaluated" : x["allocation"]["status"],
                allocation_pass = x===nothing ? false : x["validation"]["allocation_pass"],
                elapsed_sec = r["elapsed_sec"],
                unit = "USD_synthetic",
                input_sha256 = c.sha256,
            ),
        )
        x===nothing && continue
        alloc=x["allocation"]
        for i in 1:3
            push!(
                payments,
                (
                    run_id = entry["id"],
                    case = entry["case"],
                    penalty = entry["penalty"],
                    variant = x["variant"],
                    actor = c.data["actors"][i]["id"],
                    disagreement = alloc["disagreement_utility"][i],
                    prepayment_utility = alloc["prepayment_utility"][i],
                    gain = haskey(alloc, "gain") ? alloc["gain"][i] : missing,
                    total_transfer = haskey(alloc, "total_transfer") ? alloc["total_transfer"][i] :
                                     missing,
                    utility_after = haskey(alloc, "utility_after") ? alloc["utility_after"][i] :
                                    missing,
                    unit = "USD_synthetic",
                ),
            )
        end
    end
    for x in economics["trading_ledger"]["contracts"]
        push!(
            contracts,
            (
                run_id = entry["id"],
                case = entry["case"],
                penalty = entry["penalty"],
                actor = x["actor"],
                carrier = x["carrier"],
                t = x["t"],
                peer_export_MW = x["peer_export_MW"],
                retail_buy_MW = x["retail_buy_MW"],
                retail_sell_MW = x["retail_sell_MW"],
            ),
        )
    end
    collections=[
        ("trading", r["trading_selected"]["validation"]["rows"]),
        ("strict_physical", rawstrict["validation"]["rows"]),
        ("elastic_model", ev["rows"]),
        (
            "elastic_original",
            haskey(ev, "physical_validation") ? ev["physical_validation"]["rows"] : Any[],
        ),
    ]
    for (stage, rs) in collections, x in rs
        # SOCP的原等式残差单列；不是弹性模型硬约束通过条件。
        push!(
            residuals,
            (
                run_id = entry["id"],
                stage = stage,
                equation = x["equation"],
                scope = x["scope"],
                entity = x["entity"],
                t = x["t"],
                residual = x["residual"],
                unit = x["unit"],
                tolerance = x["tolerance"],
                pass = x["pass"],
            ),
        )
    end
end
mkpath(output)
CSV.write(joinpath(output, "comparison.csv"), summary)
CSV.write(joinpath(output, "actors.csv"), payments)
CSV.write(joinpath(output, "contracts.csv"), contracts)
CSV.write(joinpath(output, "residuals.csv"), residuals)
write(joinpath(output, "evidence.toml"), PaperRebuild.r4_text(Dict("records"=>records)))
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>study["batch"],
            "origin"=>"synthetic",
            "runs"=>length(records),
            "allocation_rows"=>length(summary),
            "selected_flow_hashes"=>selected_hashes,
            "config_sha256"=>study["config_sha256"],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "batch_hashes_sha256"=>bytes2hex(sha256(read(joinpath(dir, "batch-hashes.toml")))),
            "not_claimed"=>[
                "arbitrary_coalition_stability",
                "full_thermal_physics",
                "thesis_same_input",
                "distributed_algorithm",
            ],
        ),
    ),
)
println("Independently checked ", length(records), " TSPA runs: ", abspath(output))
