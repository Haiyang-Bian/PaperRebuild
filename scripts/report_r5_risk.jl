include("r5_risk_report_tables.jl")
length(ARGS)==2||error("参数：风险study.toml 新报告目录")
manifest, output=abspath.(ARGS)
ispath(output)&&error("不覆盖风险报告")
study=TOML.parsefile(manifest)
study["schema"]=="r5-risk-study-v1"&&study["complete"]||error("风险研究未完成")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "risk", "study.toml");
rules=TOML.parsefile(config)
rules==study["rules"]&&bytes2hex(sha256(read(config)))==study["config_sha256"]||error(
    "风险规则变化",
)
expected=Dict(e["id"]=>e for e in rules["runs"])
length(study["records"])==length(expected)&&Set(e["id"] for e in study["records"])==Set(
    keys(expected),
)||error("风险记录范围错误")
tables=Dict{String,Vector{NamedTuple}}();
sources=Dict{String,String}()
mkpath(joinpath(output, "witnesses"))
for e in study["records"]
    id=e["id"]
    all(e[k]==expected[id][k] for k in ("case", "solver", "method"))||error("风险因素变化")
    dir=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(dir, "result.toml"))))==e["result_sha256"]||error(
        "风险原结果变化",
    )
    loaded=read_r5_risk_run(dir)
    c, r=loaded.case, loaded.result
    c.sha256==e["case_sha256"]==load_r5_risk_case(joinpath(dirname(config), e["case"])).sha256||error(
        "风险输入身份变化",
    )
    sources[id]=e["result_sha256"]
    for (file, rows) in r5_risk_report_tables(c, r, e)
        append!(get!(tables, file, NamedTuple[]), rows)
    end
    witness=Dict(
        "case"=>c.data,
        "result"=>r5_risk_public_result(r),
        "parent_result_sha256"=>e["result_sha256"],
    )
    write(joinpath(output, "witnesses", id*".toml"), PaperRebuild.r5_market_text(witness))
end
tables["method-comparison.csv"]=r5_risk_comparisons(tables["comparison.csv"])
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
summary=tables["comparison.csv"];
res=tables["residuals.csv"]
meta=Dict(
    "schema"=>"r5-risk-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "config_sha256"=>study["config_sha256"],
    "raw_result_sha256"=>sources,
    "source_sha256"=>PaperRebuild.r5_risk_science_hashes(),
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for
        f in ("report_r5_risk.jl", "r5_risk_report_tables.jl")
    ),
    "records"=>length(summary),
    "solver_reexecuted"=>false,
    "model_pass"=>count(x->x.model_pass, summary),
    "risk_pass"=>count(x->x.risk_pass, summary),
    "cost_complete"=>count(x->x.cost_complete, summary),
    "residual_count"=>length(res),
    "max_normalized_residual"=>maximum(x.normalized for x in res),
    "scope"=>"Synthetic fixed-price finite-support DRO and joint comfort risk; not strategic bidding, continuous support, online control or out-of-sample reliability.",
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Risk report: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model; ",
    meta["risk_pass"],
    " risk; ",
    meta["residual_count"],
    " residuals.",
)
