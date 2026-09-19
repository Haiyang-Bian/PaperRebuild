include("r5_execution_report_tables.jl")
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：执行报告目录 [--seal] [--publish]")
dir=abspath(only(args))
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "execution", "study.toml")
rules=TOML.parsefile(config)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-execution-report-v1" &&
meta["origin"]=="synthetic" &&
!meta["solver_reexecuted"] &&
!meta["strategic_reoptimization"] &&
meta["config_sha256"]==bytes2hex(sha256(read(config))) || error("报告身份不符")
for (rel, h) in meta["source_sha256"]
    bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==h || error("科学源码不同")
end
for (file, h) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, file))))==h || error("报告脚本不同")
end
tables=Dict{String,Vector{NamedTuple}}()
for e in rules["runs"]
    w=TOML.parsefile(joinpath(dir, "witnesses", e["id"]*".toml"))
    for (file, rows) in r5_execution_tables(w, e, root)
        append!(get!(tables, file, NamedTuple[]), rows)
    end
end
for (file, rows) in tables
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, file)) || error("公开数值重算不同：$file")
end
rows, res=tables["comparison.csv"], tables["residuals.csv"]
length(rows)==meta["records"]==length(rules["runs"]) &&
length(res)==meta["residual_count"] &&
maximum(x.normalized for x in res)==meta["max_normalized_residual"] || error("计数或残差不同")
for key in ("selection_pass", "delivery_pass", "cost_complete")
    count(x->getproperty(x, Symbol(key)), rows)==meta[key] || error("状态计数不同")
end
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"] && Set(fig["run_ids"])==Set(x.run_id for x in rows) ||
    error("图源身份不同")
for (file, h) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==h || error("图源数据不同")
end
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_execution.jl"))))==fig["script_sha256"] ||
    error("绘图脚本不同")
hashes=Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml" && continue
    path=joinpath(base, file)
    filesize(path)<5*1024^2 || error("公开文件超过5MiB")
    if endswith(file, ".toml") || endswith(file, ".csv")
        # TOML错误文字中的because:\n不是Windows盘符；盘符前不能还有单词字符。
        occursin(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/]", read(path, String)) &&
            error("公开文件含本机路径：$file")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal) && error("不覆盖封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes || error("封存不同")
end
if "--publish" in ARGS
    # 只写本地Documenter资产，不涉及远程发布。
    target=joinpath(root, "docs", "src", "assets", "r5-execution")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst) || error("不覆盖不同的文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Execution public witnesses and CSV independently verified: ",
    length(rows),
    " records, no optimization.",
)
