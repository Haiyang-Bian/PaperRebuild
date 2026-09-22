include("r5_strategic_benders_report_tables.jl")
include("r5_strategic_benders_study_rules.jl")
include("r5_risk_artifact_paths.jl")
args = filter(x->!startswith(x, "--"), ARGS)
length(args) == 1 || error("参数：策略分解报告目录 [--seal] [--publish]")
dir = abspath(only(args))
root = normpath(joinpath(@__DIR__, ".."))
config = joinpath(root, "configs", "r5", "strategic-benders", "study.toml")
input = r5_sb_study_inputs(config)
rules = input.rules
meta = TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"] == "r5-strategic-benders-report-v1" &&
meta["origin"] == "synthetic" &&
!meta["solver_reexecuted"] &&
meta["config_sha256"] == bytes2hex(sha256(read(config))) &&
meta["source_sha256"] == rules["science_sha256"] || error("策略分解报告身份变化")
for (f, h) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, f)))) == h || error("报告生成器改变：$f")
end
tables = Dict{String,Vector{NamedTuple}}()
references = Dict{String,Any}()
for (file, ref) in rules["references"]
    path = joinpath(dir, "references", file)
    bytes2hex(sha256(read(path))) == ref["witness_sha256"] || error("公开参考改变")
    references[file] = TOML.parsefile(path)
end
for e in rules["runs"]
    w = r5_sb_read_witness(joinpath(dir, "witnesses", e["id"]))
    c, r = w.case, w.result
    w.parent_result_sha256 == meta["raw_result_sha256"][e["id"]] || error("父结果身份变化")
    c.sha256 == input.cases[e["case"]].sha256 || error("公开输入变化")
    r["source_hashes_at_solve"] == meta["source_sha256"] &&
    r["budget_sec"] == rules["budget_sec"] || error("来源或预算不同")
    r["spec"] == PaperRebuild.r5_benders_spec(r5_sb_study_spec(rules, e)) ||
        error("公开算法规则不同")
    for (file, rows) in r5_sb_report_tables(c, r, e, references[e["case"]])
        append!(get!(tables, file, NamedTuple[]), rows)
    end
    println("Replayed ", e["id"])
    flush(stdout)
end
for (file, rows) in tables
    io = IOBuffer()
    CSV.write(io, rows)
    take!(io) == read(joinpath(dir, file)) || error("CSV独立重算不一致：$file")
end
for (k, v) in r5_sb_report_counts(tables)
    meta[k] == v || error("报告计数变化：$k")
end
fig = TOML.parsefile(joinpath(dir, "figure-config.toml"))
fig["origin"] == "synthetic" &&
!fig["solver_reexecuted"] &&
Set(fig["run_ids"]) == Set(x.run_id for x in tables["comparison.csv"]) || error("图源身份不同")
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_strategic_benders.jl")))) ==
fig["script_sha256"] || error("绘图脚本改变")
for (f, h) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, f)))) == h || error("图源改变")
end
hashes = Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file == "artifact-hashes.toml" && continue
    p = joinpath(base, file)
    islink(p) && error("公开证据不允许链接")
    filesize(p) < 5*1024^2 || error("公开文件超过5MiB")
    (endswith(file, ".toml") || endswith(file, ".csv")) &&
        r5_risk_has_host_path(read(p, String)) &&
        error("公开文件包含本机路径")
    hashes[replace(relpath(p, dir), '\\'=>'/')] = bytes2hex(sha256(read(p)))
end
seal = joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal) && error("不覆盖策略分解封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"] == hashes || error("封存变化")
end
if "--publish" in ARGS
    target = joinpath(root, "docs", "src", "assets", "r5-strategic-benders")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src = joinpath(dir, split(rel, '/')...)
        dst = joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src) == read(dst) || error("不覆盖已有文档证据")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "All strategy Benders public witnesses and CSV replayed without solving: ",
    r5_sb_report_counts(tables),
)
