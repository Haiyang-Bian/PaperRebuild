include("r5_strategic_benders_report_tables.jl")
include("r5_strategic_benders_study_rules.jl")
length(ARGS) == 2 || error("参数：正式study.toml 新报告目录")
manifest, output = abspath.(ARGS)
ispath(output) && error("不覆盖策略分解报告")
root = normpath(joinpath(@__DIR__, ".."))
config = joinpath(root, "configs", "r5", "strategic-benders", "study.toml")
input = r5_sb_study_inputs(config)
rules = input.rules
study = TOML.parsefile(manifest)
study["schema"] == "r5-strategic-benders-study-v1" &&
study["complete"] &&
study["rules"] == rules &&
study["config_sha256"] == bytes2hex(sha256(read(config))) || error("正式批次未完成或规则不同")
expected = Dict(e["id"]=>e for e in rules["runs"])
length(study["records"]) == length(expected) &&
Set(e["id"] for e in study["records"]) == Set(keys(expected)) || error("执行范围不完整")
mkpath(joinpath(output, "references"))
references = Dict{String,Any}()
for (file, ref) in rules["references"]
    path = joinpath(root, split(ref["witness"], '/')...)
    references[file] = TOML.parsefile(path)
    cp(path, joinpath(output, "references", file))
end
tables = Dict{String,Vector{NamedTuple}}()
sources = Dict{String,String}()
for e in study["records"]
    id = e["id"]
    all(e[k] == expected[id][k] for k in ("case", "route")) || error("研究因素不同")
    dir = joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(dir, "result.toml")))) == e["result_sha256"] ||
        error("原运行篡改")
    loaded = read_r5_strategic_benders_run(dir)
    c, r = loaded.case, loaded.result
    c.sha256 == e["case_sha256"] == input.cases[e["case"]].sha256 || error("输入不同")
    r["spec"] == PaperRebuild.r5_benders_spec(r5_sb_study_spec(rules, e)) || error("实际规则不同")
    r["budget_sec"] == rules["budget_sec"] &&
    r["source_hashes_at_solve"] == rules["science_sha256"] || error("实际预算或科学版本不同")
    sources[id] = e["result_sha256"]
    r5_sb_write_witness(c, r, joinpath(output, "witnesses", id), e["result_sha256"])
    for (file, rows) in r5_sb_report_tables(c, r, e, references[e["case"]])
        append!(get!(tables, file, NamedTuple[]), rows)
    end
    println("Reported ", id)
    flush(stdout)
end
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
meta = Dict{String,Any}(
    "schema"=>"r5-strategic-benders-report-v1",
    "origin"=>"synthetic",
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "science_commit"=>rules["science_commit"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "config_sha256"=>study["config_sha256"],
    "raw_result_sha256"=>sources,
    "source_sha256"=>rules["science_sha256"],
    "solver_reexecuted"=>false,
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for f in (
            "report_r5_strategic_benders.jl",
            "r5_strategic_benders_report_tables.jl",
            "r5_strategic_benders_witness.jl",
            "r5_benders_witness.jl",
        )
    ),
    "scope"=>"Full-market optimistic strategy plus finite-support risk, synthetic inputs. Conditional subproblem and master-relaxation status do not establish complete-model infeasibility or unboundedness without their declared evidence. No scale-speed or out-of-sample claim.",
)
merge!(meta, r5_sb_report_counts(tables))
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println("Strategy Benders report: ", r5_sb_report_counts(tables))
