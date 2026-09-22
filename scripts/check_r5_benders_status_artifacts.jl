include("r5_benders_status_rules.jl")
include("r5_benders_status_tables.jl")
include("r5_risk_artifact_paths.jl")
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1||error("参数：状态报告目录 [--seal] [--publish]")
dir=abspath(only(args));
root=normpath(joinpath(@__DIR__, ".."))
input=r5_benders_status_inputs(joinpath(root, "configs", "r5", "benders", "status-study.toml"))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-benders-status-report-v1"&&meta["origin"]=="synthetic"&&!meta["solver_reexecuted"]||error(
    "状态报告身份错误",
)
meta["config_sha256"]==bytes2hex(
    sha256(read(joinpath(root, "configs", "r5", "benders", "status-study.toml"))),
)||error("规则改变")
meta["source_sha256"]==input.rules["science_sha256"]||error("来源改变")
for (file, hash) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, file))))==hash||error("报告生成器改变")
end
for p in input.rules["probes"]
    rel="probes/"*p["id"]*".toml"
    bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...))))==meta["raw_sha256"][rel]||error(
        "探测原值改变",
    )
end
for e in input.rules["runs"]
    w=TOML.parsefile(joinpath(dir, "witnesses", e["id"], "witness.toml"))
    w["parent_result_sha256"]==meta["raw_sha256"][e["id"]]||error("完整方法父记录改变")
end
a, b=deepcopy(meta["requested_parameters"]["0"]), deepcopy(meta["requested_parameters"]["1"])
pop!(a, "DualReductions")==0&&pop!(b, "DualReductions")==1&&a==b||error("参数配对不符")
meta["effective_DualReductions"]==Dict("0"=>0, "1"=>1)||error("实际参数不符")
tables=r5_benders_status_tables(dir, input)
for (file, rows) in tables
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, file))||error("表格与独立回算不同：$file")
end
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
fig["origin"]=="synthetic"&&!fig["solver_reexecuted"] &&
Set(fig["run_ids"])==Set(x.run_id for x in tables["comparison.csv"])||error("状态图源身份不同")
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_benders_status.jl"))))||error(
    "状态绘图源码改变",
)
for (file, hash) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash||error("状态图源变化")
end
hashes=Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(base, file)
    rel=replace(relpath(path, dir), '\\'=>'/')
    islink(path)&&error("不允许链接")
    filesize(path)<5*1024^2||error("公开文件过大")
    (endswith(file, ".toml")||endswith(file, ".csv"))&&r5_risk_has_host_path(read(path, String))&&error(
        "公开文件含本机路径",
    )
    hashes[rel]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖状态证据封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("状态封存改变")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-benders-status")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖状态文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Status artifacts independently replayed: ",
    count(x->x.A2_pass, tables["comparison.csv"]),
    "/3 A2; ",
    count(x->x.positive_infeasibility_certificate, tables["status-probes.csv"]),
    "/5 diagnostic certificates.",
)
