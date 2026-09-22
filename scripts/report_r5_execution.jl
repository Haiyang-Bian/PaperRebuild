include("r5_execution_report_tables.jl")
length(ARGS)==2 || error("参数：已完成study.toml 新报告目录")
manifest, output=abspath.(ARGS)
ispath(output) && error("不覆盖执行报告")
root=normpath(joinpath(@__DIR__, ".."))
rulepath=joinpath(root, "configs", "r5", "execution", "study.toml")
rules=TOML.parsefile(rulepath)
study=TOML.parsefile(manifest)
study["complete"] &&
study["rules"]==rules &&
study["config_sha256"]==bytes2hex(sha256(read(rulepath))) || error("正式批次不完整或规则不同")
Set(e["id"] for e in study["records"])==Set(e["id"] for e in rules["runs"]) &&
length(study["records"])==length(rules["runs"]) || error("记录清单不同")
study["source_sha256"]==PaperRebuild.r5_execution_science_hashes() || error("科学源码变化")
mkpath(joinpath(output, "witnesses"))
tables=Dict{String,Vector{NamedTuple}}()
for e in rules["runs"]
    record=only(filter(x->x["id"]==e["id"], study["records"]))
    base=joinpath(dirname(manifest), e["id"])
    TOML.parsefile(joinpath(base, "record.toml"))==record || error("原始记录不同")
    w=Dict{String,Any}("record"=>record, "stages"=>Dict{String,Any}())
    for name in record["stages"]
        path=joinpath(base, name)
        h=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
        h==record["stage_sha256"][name] || error("原始阶段改变")
        loaded=read_r5_execution_run(path)
        w["stages"][name]=Dict(
            "payload"=>loaded.payload,
            "result"=>r5_execution_public(loaded.result),
            "raw_result_sha256"=>h,
        )
    end
    for (file, rows) in r5_execution_tables(w, e, root)
        append!(get!(tables, file, NamedTuple[]), rows)
    end
    write(joinpath(output, "witnesses", e["id"]*".toml"), PaperRebuild.r5_market_text(w))
end
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
rows, res=tables["comparison.csv"], tables["residuals.csv"]
meta=Dict{String,Any}(
    "schema"=>"r5-execution-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "source_sha256"=>study["source_sha256"],
    "config_sha256"=>study["config_sha256"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for
        f in ("r5_execution_report_tables.jl", "report_r5_execution.jl")
    ),
    "records"=>length(rows),
    "selection_pass"=>count(x->x.selection_pass, rows),
    "delivery_pass"=>count(x->x.delivery_pass, rows),
    "cost_complete"=>count(x->x.cost_complete, rows),
    "residual_count"=>length(res),
    "max_normalized_residual"=>maximum(x.normalized for x in res),
    "solver_reexecuted"=>false,
    "strategic_reoptimization"=>false,
    "scope"=>"Fixed prior bids; explicit execution selection and conditional finite-support recourse.",
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(meta)
