# 把已经核查的公开合成微型结果整理到摘要/文档；不求解、不推送。
using PaperRebuild, TOML, SHA

length(ARGS) == 1 || error("用法：scripts/prepare_r1_summary.jl <已绘图的运行目录>")
dir = ARGS[1]
saved = read_r1_run(dir)
report = validate_r1_solution(saved.case, saved.result)
saved.result["status"] == "solver_optimal" && report.relaxed_pass && report.original_branch_pass ||
    error("该运行未通过本批门槛")
root = normpath(joinpath(@__DIR__, ".."))
target = joinpath(root, "results", "summaries", "r1-first-batch", saved.metadata["run_id"])
ispath(target) && error("摘要运行已存在，拒绝覆盖")
mkpath(target)
for file in (
    "case.toml",
    "metadata.toml",
    "solution.toml",
    "validation.toml",
    "residuals.csv",
    "timeseries.csv",
    "states.csv",
)
    cp(joinpath(dir, file), joinpath(target, file))
end
cp(joinpath(dir, "figures"), joinpath(target, "figures"))
assets = joinpath(root, "docs", "src", "assets", "r1", saved.metadata["run_id"])
mkpath(assets)
for file in readdir(joinpath(dir, "figures"))
    endswith(file, ".svg") || continue
    cp(joinpath(dir, "figures", file), joinpath(assets, file))
end
println("Prepared reviewed synthetic summary: ", relpath(target, root))
