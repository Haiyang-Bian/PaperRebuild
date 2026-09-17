# 正式摘要验收：清单、来源、无本机路径，以及冻结输入/脚本/图源哈希。
include("r4_setup.jl")
using CSV
dir=isempty(ARGS) ? joinpath("results", "summaries", "r4-first-batch") : first(ARGS)
seal="--seal" in ARGS
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
length(rows)==19 || error("正式证据应含18个主运行和1个同模型对照")
study=TOML.parsefile("configs/r4/study.toml")
frozen=Dict(x["name"]=>x["sha256"] for x in study["case"])
for r in rows
    r.input_sha256==frozen[r.case] || error("摘要输入未冻结")
    isabspath(r.path) && error("公开摘要含本机路径")
end
TOML.parsefile(joinpath(dir, "solver-comparison.toml"))["pass"] || error("同模型A2未通过")
for (file, script) in (
    ("report.toml", "scripts/report_r4.jl"),
    ("figures/figure-config.toml", "scripts/plot_r4.jl"),
    ("F04-study-config.toml", "scripts/plot_r4_summary.jl"),
)
    TOML.parsefile(joinpath(dir, file))["script_sha256"]==bytes2hex(sha256(read(script))) ||
        error("图表/报告脚本版本已变: "*script)
end
hashes=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml" && continue
    path=joinpath(folder, file)
    rel=replace(relpath(path, dir), '\\'=>'/')
    stat(path).size<=5*1024^2 || error("单文件过大")
    if endswith(file, ".toml") || endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) &&
            error("公开证据包含本机绝对路径: "*rel)
    end
    hashes[rel]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if seal
    isfile(manifest) && error("不重写已有封存哈希")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(manifest)["sha256"]==hashes || error("摘要文件清单/哈希改变")
end
println("R4 artifacts: 19 records, frozen sources, A2, portable paths, hashes checked.")
