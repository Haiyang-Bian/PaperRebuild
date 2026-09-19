include("r5_benders_report_tables.jl")
include("r5_benders_study_rules.jl")
include("r5_risk_artifact_paths.jl")
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1||error("参数：分解报告目录 [--seal] [--publish]")
dir=abspath(only(args));
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-benders-report-v1"&&meta["origin"]=="synthetic"&&!meta["solver_reexecuted"]||error(
    "分解报告身份错误",
)
config=joinpath(root, "configs", "r5", "benders", "study.toml")
input=r5_benders_study_inputs(config);
rules=input.rules
bytes2hex(sha256(read(config)))==meta["config_sha256"]||error("报告规则哈希改变")
meta["source_sha256"]==rules["science_sha256"]||error("报告科学来源改变")
for (file, hash) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, file))))==hash||error("分解报告生成器改变：$file")
end
references=Dict{String,Any}()
for (file, ref) in rules["references"]
    path=joinpath(dir, "references", file)
    bytes2hex(sha256(read(path)))==ref["witness_sha256"]||error("公开直接参考变化")
    references[file]=TOML.parsefile(path)
end
tables=Dict{String,Vector{NamedTuple}}()
for entry in rules["runs"]
    id=entry["id"]
    w=r5_benders_read_witness(joinpath(dir, "witnesses", id))
    w.parent_result_sha256==meta["raw_result_sha256"][id]||error("父结果身份变化")
    w.case.sha256==input.cases[entry["case"]].sha256||error("公开输入改变")
    w.result["source_hashes_at_solve"]==meta["source_sha256"]||error("见证科学来源改变")
    w.result["spec"]==PaperRebuild.r5_benders_spec(r5_benders_study_spec(rules, entry))||error(
        "公开算法规则不同",
    )
    for (file, rows) in r5_benders_report_tables(w.case, w.result, entry, references[entry["case"]])
        append!(get!(tables, file, NamedTuple[]), rows)
    end
end
for (file, rows) in tables
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, file))||error("分解表格并非独立回算：$file")
end
summary=tables["comparison.csv"];
res=tables["selected-residuals.csv"]
length(summary)==meta["records"]==length(rules["runs"])||error("分解范围不完整")
for key in ("model_pass", "risk_pass", "cost_complete", "restricted_stopping", "A2_pass")
    count(x->getproperty(x, Symbol(key)), summary)==meta[key]||error("分解状态汇总不同：$key")
end
length(res)==meta["selected_residual_count"]&&maximum(x.normalized for x in res)==meta["max_selected_normalized_residual"]||error(
    "分解最终残差汇总不同",
)
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
fig["origin"]=="synthetic"&&!fig["solver_reexecuted"]&&Set(fig["run_ids"])==Set(
    x.run_id for x in summary
)||error("分解图源身份不同")
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_benders.jl"))))==fig["script_sha256"]||error(
    "分解绘图源码改变",
)
for (file, hash) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash||error("分解图源改变")
end
hashes=Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(base, file)
    rel=replace(relpath(path, dir), '\\'=>'/')
    islink(path)&&error("公开证据不允许符号链接")
    filesize(path)<5*1024^2||error("分解公开文件过大：$rel")
    (endswith(file, ".toml")||endswith(file, ".csv"))&&r5_risk_has_host_path(read(path, String))&&error(
        "分解公开证据含本机路径：$rel",
    )
    hashes[rel]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖分解封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("分解封存变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-benders")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖分解文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Benders artifacts: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model; ",
    meta["cost_complete"],
    " full completions; ",
    meta["restricted_stopping"],
    " restricted stops. All public raw witnesses replayed without solving.",
)
