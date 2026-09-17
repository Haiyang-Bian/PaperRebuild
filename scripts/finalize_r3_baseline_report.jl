using TOML, SHA
length(ARGS)==3 ||
    error("usage: finalize_r3_baseline_report.jl FINAL_REPORT FIGURE_DIRECTORY DRAFT_REPORT")
root=normpath(joinpath(@__DIR__, ".."))
report, figures, draft=abspath.(ARGS)
function inside(path, relative)
    base=normpath(joinpath(root, relative))
    startswith(normpath(path), base*string(Base.Filesystem.path_separator)) ||
        error("路径超出预定目录：$path")
end
inside(report, "results/summaries/r3-baseline")
inside(draft, "results/summaries/r3-baseline")
inside(figures, relpath(report, root))
study=TOML.parsefile(joinpath(report, "study.toml"))
archive=joinpath(root, "results", "runs", study["batch"], "report-development")
mkpath(archive)
for name in ("historical-v3.csv", "historical-v3-stopping.csv")
    cp(joinpath(draft, name), joinpath(report, name))
end
pairings=filter(x->startswith(x, "pairing-")&&endswith(x, ".toml"), readdir(dirname(archive)))
length(pairings)==1 || error("须明确唯一配对凭据")
cp(joinpath(dirname(archive), only(pairings)), joinpath(report, "pairing.toml"))
cp(figures, joinpath(report, "figures"))
# 中间报告与失败绘图仍保存在本批被忽略的运行目录，避免混入正式网站。
for source in (draft, figures)
    target=joinpath(archive, basename(source))
    inside(source, "results/summaries/r3-baseline")
    inside(target, "results/runs/"*study["batch"])
    ispath(target) && error("归档目标已存在")
    mv(source, target)
end
hashes=Dict{String,String}()
for (dir, _, files) in walkdir(report), file in files
    path=joinpath(dir, file)
    hashes[replace(relpath(path, report), '\\'=>'/')]=open(sha256, path) |> bytes2hex
end
open(joinpath(report, "artifact-hashes.toml"), "w") do io
    TOML.print(io, Dict("schema"=>"r3-baseline-report-v1", "files"=>hashes); sorted = true)
end
destination=joinpath(root, "docs", "src", "assets", "r3-baseline", basename(report))
ispath(destination) && error("拒绝覆盖已发布文档副本")
mkpath(dirname(destination))
cp(report, destination)
println("Assembled ", length(hashes), " verified artifacts: ", destination)
