include("r5_risk_report_tables.jl")
include("r5_risk_artifact_paths.jl")
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1||error("参数：风险报告目录 [--seal] [--publish]")
dir=abspath(only(args));
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-risk-report-v1"&&meta["origin"]=="synthetic"&&!meta["solver_reexecuted"]||error(
    "风险报告身份错误",
)
config=joinpath(root, "configs", "r5", "risk", "study.toml");
rules=TOML.parsefile(config)
bytes2hex(sha256(read(config)))==meta["config_sha256"]||error("风险规则变化")
for (rel, hash) in meta["source_sha256"]
    bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==hash||error(
        "风险科学源码变化：$rel",
    )
end
for (file, hash) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, file))))==hash||error("风险报告生成器变化：$file")
end
tables=Dict{String,Vector{NamedTuple}}()
for entry in rules["runs"]
    id=entry["id"]
    w=TOML.parsefile(joinpath(dir, "witnesses", id*".toml"))
    c=R5RiskCase(w["case"])
    r=w["result"]
    c.sha256==load_r5_risk_case(joinpath(dirname(config), entry["case"])).sha256||error(
        "风险公共见证输入变化",
    )
    w["parent_result_sha256"]==meta["raw_result_sha256"][id]||error("风险父记录哈希不同")
    v=validate_r5_risk(c, r)
    r["cost_optimization_complete"]==(
        r["status"] in ("solver_optimal", "enumeration_complete")&&v["optimality_pass"]
    )||error("风险费用状态不同")
    for (file, rows) in r5_risk_report_tables(c, r, entry)
        append!(get!(tables, file, NamedTuple[]), rows)
    end
end
tables["method-comparison.csv"]=r5_risk_comparisons(tables["comparison.csv"])
for (file, rows) in tables
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, file))||error("风险表格并非独立回算结果：$file")
end
summary=tables["comparison.csv"];
res=tables["residuals.csv"]
length(summary)==meta["records"]==length(rules["runs"])||error("风险记录清单不完整")
for k in ("model_pass", "risk_pass", "cost_complete")
    count(x->getproperty(x, Symbol(k)), summary)==meta[k]||error("风险状态汇总不同")
end
length(res)==meta["residual_count"]&&maximum(x.normalized for x in res)==meta["max_normalized_residual"]||error(
    "风险残差汇总不同",
)
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"]&&Set(fig["run_ids"])==Set(x.run_id for x in summary)||error(
    "风险图源身份错误",
)
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_risk.jl"))))==fig["script_sha256"]||error(
    "风险绘图源码变化",
)
for (file, hash) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash||error("风险图源变化")
end
hashes=Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(base, file)
    rel=replace(relpath(path, dir), '\\'=>'/')
    filesize(path)<5*1024^2||error("风险公共文件过大：$rel")
    if endswith(file, ".toml")||endswith(file, ".csv")
        r5_risk_has_host_path(read(path, String))&&error("风险公开文件包含本机路径：$rel")
    end
    hashes[rel]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖风险封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("风险封存变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-risk")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖风险文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Risk artifacts: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model; ",
    meta["risk_pass"],
    " risk; all public witnesses and tables replayed without solving.",
)
