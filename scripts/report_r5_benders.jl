include("r5_benders_report_tables.jl")
include("r5_benders_study_rules.jl")
length(ARGS)==2||error("参数：分解study.toml 新报告目录")
manifest, output=abspath.(ARGS)
ispath(output)&&error("不覆盖分解报告")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "benders", "study.toml")
input=r5_benders_study_inputs(config);
rules=input.rules
study=TOML.parsefile(manifest)
study["schema"]=="r5-benders-study-v1"&&study["complete"]||error("正式分解未完成")
study["rules"]==rules&&study["config_sha256"]==bytes2hex(sha256(read(config)))||error(
    "执行规则改变",
)
expected=Dict(e["id"]=>e for e in rules["runs"])
length(study["records"])==length(expected)&&Set(e["id"] for e in study["records"])==Set(
    keys(expected),
)||error("执行清单不完整")
mkpath(joinpath(output, "references"))
references=Dict{String,Any}()
for (file, ref) in rules["references"]
    path=joinpath(root, split(ref["witness"], '/')...)
    references[file]=TOML.parsefile(path)
    cp(path, joinpath(output, "references", file))
end
tables=Dict{String,Vector{NamedTuple}}();
sources=Dict{String,String}()
for e in study["records"]
    id=e["id"]
    all(e[k]==expected[id][k] for k in ("case", "route", "solver"))||error("研究因素改变")
    dir=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(dir, "result.toml"))))==e["result_sha256"]||error("父结果变化")
    loaded=read_r5_benders_run(dir)
    c, r=loaded.case, loaded.result
    c.sha256==e["case_sha256"]==input.cases[e["case"]].sha256||error("正式输入不同")
    r["spec"]==PaperRebuild.r5_benders_spec(r5_benders_study_spec(rules, e))||error(
        "实际算法规则不同",
    )
    sources[id]=e["result_sha256"]
    r5_benders_write_witness(c, r, joinpath(output, "witnesses", id), e["result_sha256"])
    for (file, rows) in r5_benders_report_tables(c, r, e, references[e["case"]])
        append!(get!(tables, file, NamedTuple[]), rows)
    end
    println("Reported ", id)
    flush(stdout)
end
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
summary=tables["comparison.csv"];
res=tables["selected-residuals.csv"]
meta=Dict(
    "schema"=>"r5-benders-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "science_commit"=>rules["science_commit"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "config_sha256"=>study["config_sha256"],
    "raw_result_sha256"=>sources,
    "source_sha256"=>rules["science_sha256"],
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for
        f in ("report_r5_benders.jl", "r5_benders_report_tables.jl", "r5_benders_witness.jl")
    ),
    "records"=>length(summary),
    "solver_reexecuted"=>false,
    "model_pass"=>count(x->x.model_pass, summary),
    "risk_pass"=>count(x->x.risk_pass, summary),
    "cost_complete"=>count(x->x.cost_complete, summary),
    "restricted_stopping"=>count(x->x.restricted_stopping, summary),
    "A2_pass"=>count(x->x.A2_pass, summary),
    "selected_residual_count"=>length(res),
    "max_selected_normalized_residual"=>maximum(x.normalized for x in res),
    "scope"=>"Synthetic finite-support fixed-price three-route Benders. All scenarios checked; restricted-domain stopping separated. No author-data, scale-speed or out-of-sample claim.",
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Benders report: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model; ",
    meta["cost_complete"],
    " full-domain completion; ",
    meta["restricted_stopping"],
    " restricted stops.",
)
