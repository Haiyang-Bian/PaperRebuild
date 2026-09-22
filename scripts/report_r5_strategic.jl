include("r5_strategic_report_tables.jl")
length(ARGS)==2||error("参数：策略study.toml 新报告目录")
manifest, output=abspath.(ARGS)
ispath(output)&&error("报告不覆盖")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "strategic", "study.toml")
rules=TOML.parsefile(config)
study=TOML.parsefile(manifest)
study["complete"]&&study["rules"]==rules &&
study["config_sha256"]==bytes2hex(sha256(read(config))) || error("正式规则不同或批次未完成")
Set(e["id"] for e in study["records"])==Set(e["id"] for e in rules["runs"]) &&
length(study["records"])==length(rules["runs"]) || error("正式记录不完整")
mkpath(joinpath(output, "witnesses"))
tables=Dict{String,Vector{NamedTuple}}()
sources=Dict{String,String}()
for e in rules["runs"]
    id=e["id"]
    parent=only(filter(x->x["id"]==id, study["records"]))
    dir=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(dir, "result.toml"))))==parent["result_sha256"]||error(
        "原值改变",
    )
    loaded=read_r5_strategic_run(dir)
    c, r=loaded.case, loaded.result
    c.sha256==load_r5_strategic_case(joinpath(dirname(config), e["case"])).sha256 ||
        error("案例改变")
    for (file, rows) in r5_strategic_tables(c, r, e)
        append!(get!(tables, file, NamedTuple[]), rows)
    end
    sources[id]=parent["result_sha256"]
    write(
        joinpath(output, "witnesses", id*".toml"),
        PaperRebuild.r5_market_text(
            Dict(
                "case"=>c.data,
                "result"=>r5_strategic_public(r),
                "parent_result_sha256"=>parent["result_sha256"],
            ),
        ),
    )
end
tables["method-comparison.csv"]=r5_strategic_pairs(tables["comparison.csv"])
tables["settlement-range.csv"]=NamedTuple[]
for e in rules["selection_cases"]
    file="settlement-"*e["id"]*".toml"
    path=joinpath(dirname(manifest), file)
    bytes2hex(sha256(read(path)))==study["settlement"][e["id"]]||error("结算记录改变")
    w=TOML.parsefile(path)
    append!(tables["settlement-range.csv"], r5_strategic_selection_table(w, e["id"]))
    write(joinpath(output, "witnesses", file), PaperRebuild.r5_market_text(r5_strategic_public(w)))
end
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
rows=tables["comparison.csv"]
res=tables["residuals.csv"]
meta=Dict{String,Any}(
    "schema"=>"r5-strategic-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "config_sha256"=>study["config_sha256"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "raw_result_sha256"=>sources,
    "source_sha256"=>PaperRebuild.r5_strategic_science_hashes(),
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for
        f in ("r5_strategic_report_tables.jl", "report_r5_strategic.jl")
    ),
    "records"=>length(rows),
    "solver_reexecuted"=>false,
    "model_pass"=>count(x->x.model_pass, rows),
    "cost_complete"=>count(x->x.cost_complete, rows),
    "residual_count"=>length(res),
    "max_normalized_residual"=>maximum(x.normalized for x in res),
    "scope"=>rules["scope"],
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Strategy: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model, ",
    meta["cost_complete"],
    " cost certified, ",
    meta["residual_count"],
    " residuals.",
)
