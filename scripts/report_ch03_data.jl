# 将已人工审阅的结构检查和CC BY图源发布到可追踪摘要，不复制原始工作簿。
using SHA, TOML
length(ARGS) == 1 || error("用法：scripts/report_ch03_data.jl <已审阅运行目录>")
root = normpath(joinpath(@__DIR__, ".."))
dir = abspath(ARGS[1])
report = TOML.parsefile(joinpath(dir, "validation.toml"))
report["status"] == "preliminary_checks_passed_with_open_issues" || error("该运行未完成初检")
for (relative, expected) in report["output_sha256"]
    path = normpath(joinpath(dir, relative))
    first(splitpath(relpath(path, dir))) == ".." && error("路径越界")
    bytes2hex(sha256(read(path))) == expected || error("摘要输入已变更")
end
target = joinpath(root, "results", "summaries", "ch03-data", report["run_id"])
ispath(target) && error("摘要已存在，不覆盖")
mkpath(target)
for name in ("validation.toml", "source-differences.csv")
    cp(joinpath(dir, name), joinpath(target, name))
end
cp(joinpath(dir, "figures"), joinpath(target, "figures"))
assets = joinpath(root, "docs", "src", "assets", "ch03")
mkpath(assets)
asset = joinpath(assets, "public-load-profiles.svg")
isfile(asset) && error("文档图已存在，请先审阅再显式更新引用")
cp(joinpath(dir, "figures", "public-load-profiles.svg"), asset)
println("Reviewed summary: ", replace(relpath(target, root), '\\' => '/'))
