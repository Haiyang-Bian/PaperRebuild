include("r5_benders_status_rules.jl")
include("r5_benders_status_tables.jl")
length(ARGS)==2||error("参数：状态study.toml 新报告目录")
manifest, output=abspath.(ARGS)
ispath(output)&&error("不覆盖状态复核报告")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "benders", "status-study.toml")
input=r5_benders_status_inputs(config)
study=TOML.parsefile(manifest)
study["complete"]&&study["schema"]=="r5-benders-status-study-v1"&&study["rules"]==input.rules||error(
    "状态研究不完整或规则不同",
)
study["config_sha256"]==bytes2hex(sha256(read(config)))||error("状态规则哈希不同")
Set(p["id"] for p in study["probes"])==Set(p["id"] for p in input.rules["probes"])&&length(
    study["probes"],
)==5||error("探测范围不完整")
Set(e["id"] for e in study["records"])==Set(e["id"] for e in input.rules["runs"])&&length(
    study["records"],
)==3||error("方法范围不完整")
for (key, v) in (("0", 0), ("1", 1))
    study["effective_DualReductions"][key]==v||error("实际参数不符")
end
a, b=deepcopy(study["requested_parameters"]["0"]), deepcopy(study["requested_parameters"]["1"])
pop!(a, "DualReductions")==0&&pop!(b, "DualReductions")==1&&a==b||error("不是单因素对照")
mkpath(joinpath(output, "probes"))
raw=Dict{String,String}()
for p in study["probes"]
    p["file"]=="probes/"*p["id"]*".toml"||error("探测路径错误")
    source=joinpath(dirname(manifest), split(p["file"], '/')...)
    bytes2hex(sha256(read(source)))==p["sha256"]||error("原探测文件变化")
    cp(source, joinpath(output, split(p["file"], '/')...))
    raw[p["file"]]=p["sha256"]
end
for e in study["records"]
    source=joinpath(dirname(manifest), e["id"])
    bytes2hex(sha256(read(joinpath(source, "result.toml"))))==e["result_sha256"]||error(
        "完整方法原值变化",
    )
    x=read_r5_benders_run(source)
    r5_benders_write_witness(
        x.case,
        x.result,
        joinpath(output, "witnesses", e["id"]),
        e["result_sha256"],
    )
    raw[e["id"]]=e["result_sha256"]
end
tables=r5_benders_status_tables(output, input)
for (file, rows) in tables
    CSV.write(joinpath(output, file), rows)
end
meta=Dict(
    "schema"=>"r5-benders-status-report-v1",
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "batch_id"=>study["batch_id"],
    "source_commit"=>study["source_commit"],
    "config_sha256"=>study["config_sha256"],
    "study_sha256"=>bytes2hex(sha256(read(manifest))),
    "raw_sha256"=>raw,
    "requested_parameters"=>study["requested_parameters"],
    "effective_DualReductions"=>study["effective_DualReductions"],
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for f in (
            "report_r5_benders_status.jl",
            "r5_benders_status_tables.jl",
            "r5_benders_witness.jl",
            "r5_benders_report_tables.jl",
        )
    ),
    "source_sha256"=>input.rules["science_sha256"],
    "scope"=>"Subproblem-only DualReductions contrast. Original failure points remain conditionally infeasible; algorithm may restore feasible first-stage decisions. No tolerance/model change or reference injection.",
)
write(joinpath(output, "report.toml"), PaperRebuild.r5_market_text(meta))
println(
    "Status report: ",
    count(x->x.A2_pass, tables["comparison.csv"]),
    "/3 A2; ",
    count(x->x.positive_infeasibility_certificate, tables["status-probes.csv"]),
    "/5 positive diagnostic certificates.",
)
