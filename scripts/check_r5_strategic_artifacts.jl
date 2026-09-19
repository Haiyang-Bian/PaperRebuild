include("r5_strategic_report_tables.jl")
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1||error("参数：策略报告目录 [--seal] [--publish]")
dir=abspath(only(args))
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "strategic", "study.toml")
rules=TOML.parsefile(config)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-strategic-report-v1" &&
meta["origin"]=="synthetic" &&
!meta["solver_reexecuted"] &&
meta["config_sha256"]==bytes2hex(sha256(read(config))) || error("策略报告身份错误")
for (rel, h) in meta["source_sha256"]
    bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==h||error("科学源码变化：$rel")
end
for (file, h) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, file))))==h||error("报告生成器变化")
end
tables=Dict{String,Vector{NamedTuple}}()
for e in rules["runs"]
    w=TOML.parsefile(joinpath(dir, "witnesses", e["id"]*".toml"))
    c=R5StrategicCase(w["case"])
    r=w["result"]
    c.sha256==load_r5_strategic_case(joinpath(dirname(config), e["case"])).sha256 ||
        error("公开输入不符")
    w["parent_result_sha256"]==meta["raw_result_sha256"][e["id"]]||error("公开父记录身份不同")
    v=validate_r5_strategic(c, r)
    r["cost_optimization_complete"]==(r["status"]=="solver_optimal"&&v["optimality_pass"]) ||
        error("费用状态不同")
    for (file, rows) in r5_strategic_tables(c, r, e)
        append!(get!(tables, file, NamedTuple[]), rows)
    end
end
tables["method-comparison.csv"]=r5_strategic_pairs(tables["comparison.csv"])
tables["settlement-range.csv"]=NamedTuple[]
for e in rules["selection_cases"]
    w=TOML.parsefile(joinpath(dir, "witnesses", "settlement-"*e["id"]*".toml"))
    R5MarketCase(w["case"]).sha256==load_r5_market_case(joinpath(root, split(e["case"], '/')...)).sha256 ||
        error("结算公开输入不符")
    append!(tables["settlement-range.csv"], r5_strategic_selection_table(w, e["id"]))
end
for (file, rows) in tables
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, file)) || error("独立重算CSV不同：$file")
end
rows=tables["comparison.csv"]
res=tables["residuals.csv"]
length(rows)==meta["records"]==length(rules["runs"]) &&
length(res)==meta["residual_count"] &&
maximum(x.normalized for x in res)==meta["max_normalized_residual"] || error("汇总不同")
count(x->x.model_pass, rows)==meta["model_pass"] &&
count(x->x.cost_complete, rows)==meta["cost_complete"] || error("状态计数不同")
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"] && Set(fig["run_ids"])==Set(x.run_id for x in rows) ||
    error("图源身份不同")
for (file, h) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==h || error("图源变化")
end
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_strategic.jl"))))==fig["script_sha256"] ||
    error("绘图脚本变化")
hashes=Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(base, file)
    filesize(path)<5*1024^2||error("公共文件超过5MiB")
    if endswith(file, ".toml")||endswith(file, ".csv")
        occursin(r"[A-Za-z]:[\\/]", read(path, String))&&error("公共见证含本机绝对路径")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("封存改变")
end
if "--publish" in ARGS
    # 仅复制到本地Documenter资产；没有远程部署或推送。
    target=joinpath(root, "docs", "src", "assets", "r5-strategic")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖不同的文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Strategy public witnesses and CSV independently verified; ",
    length(rows),
    " records; no solver rerun.",
)
