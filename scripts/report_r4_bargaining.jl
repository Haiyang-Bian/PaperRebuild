# 只读父运行与已存分配；此入口不求解，输出新报告并保留来源哈希。
using PaperRebuild, TOML, SHA, CSV
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
root=normpath(joinpath(@__DIR__, ".."))
study_path=abspath(ARGS[1])
dir=dirname(study_path)
study=TOML.parsefile(study_path)
config=joinpath(root, "configs", "r4", "bargaining-study.toml")
study["config_sha256"]==bytes2hex(sha256(read(config))) || error("冻结规则改变")
hashes=TOML.parsefile(joinpath(dir, "batch-hashes.toml"))["sha256"]
actual=Set{String}()
for (folder, _, files) in walkdir(dir), file in files
    rel=replace(relpath(joinpath(folder, file), dir), '\\'=>'/')
    rel=="batch-hashes.toml" && continue
    push!(actual, rel)
end
actual==Set(keys(hashes)) || error("批次清单变化")
for (rel, hash) in hashes
    !isabspath(rel) && !(".." in split(rel, '/')) || error("非法批次路径")
    bytes2hex(sha256(read(joinpath(dir, rel))))==hash || error("批次文件改变")
end
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-bargaining")
ispath(output) && error("不覆盖已有报告")
records=Dict{String,Any}[]
rows=NamedTuple[]
residuals=NamedTuple[]
for entry in study["allocations"]
    record=TOML.parsefile(joinpath(dir, entry["file"]))
    parent=joinpath(root, study["parent_directory"])
    agpath=joinpath(parent, record["parent_independent"])
    swpath=joinpath(parent, record["parent_central"])
    for (label, path) in (("independent", agpath), ("central", swpath))
        bytes2hex(sha256(read(joinpath(path, "result.toml"))))==record["parent_result_sha256"][label] ||
            error("父记录改变")
    end
    ag=read_r4_run(agpath)
    sw=read_r4_run(swpath)
    regenerated=r4_allocate_coordination(
        ag.case,
        ag.result,
        sw.result;
        weights = r4_bargaining_weights(ag.case; rule = Symbol(entry["rule"]))["weights"],
    )
    all(regenerated[k]==record[k] for k in keys(regenerated)) || error("分配或验收重读不一致")
    push!(records, record)
    alloc=record["allocation"]
    for i in 1:3
        push!(
            rows,
            (
                run_id = entry["id"],
                case = entry["case"],
                rule = entry["rule"],
                actor = record["actors"][i],
                weight = alloc["weights"][i],
                disagreement = alloc["disagreement_utility"][i],
                prepayment_utility = alloc["prepayment_utility"][i],
                previous_utility = record["previous_utility"][i],
                previous_gain = record["previous_utility"][i]-alloc["disagreement_utility"][i],
                total_transfer = alloc["total_transfer"][i],
                incremental_compensation = record["incremental_compensation"][i],
                utility_after = alloc["utility_after"][i],
                gain = alloc["gain"][i],
                surplus = alloc["surplus"],
                unit = "USD_synthetic",
                input_sha256 = record["input_sha256"],
            ),
        )
    end
    for row in record["validation"]["rows"]
        push!(
            residuals,
            (
                run_id = entry["id"],
                equation = row["equation"],
                residual = row["residual"],
                tolerance = row["tolerance"],
                pass = row["pass"],
            ),
        )
    end
end
cert=TOML.parsefile(joinpath(dir, "certificates.toml"))
for row in cert["certificates"]
    read_r4_run(joinpath(dir, row["run"]))
end
mkpath(output)
CSV.write(joinpath(output, "allocations.csv"), rows)
CSV.write(joinpath(output, "residuals.csv"), residuals)
write(joinpath(output, "allocations.toml"), PaperRebuild.r4_text(Dict("records"=>records)))
cp(joinpath(dir, "certificates.toml"), joinpath(output, "certificates.toml"))
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>study["batch"],
            "origin"=>"synthetic",
            "bargaining"=>"single_stage_fixed_dispatch",
            "config_sha256"=>study["config_sha256"],
            "study_sha256"=>bytes2hex(sha256(read(study_path))),
            "batch_hashes_sha256"=>bytes2hex(sha256(read(joinpath(dir, "batch-hashes.toml")))),
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "not_claimed"=>["TSPA", "coalition_core", "full_thermal_physics", "thesis_same_input"],
        ),
    ),
)
println("Validated and reported ", length(records), " allocations: ", abspath(output))
