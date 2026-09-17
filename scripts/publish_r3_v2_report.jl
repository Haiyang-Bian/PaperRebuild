using TOML, CSV

# 只把已完成报告的精选图和图源复制到本地Documenter，不发布网站、不重新优化。
length(ARGS)==1 || error("usage: publish_r3_v2_report.jl SUMMARY_DIRECTORY")
source=abspath(only(ARGS))
isfile(joinpath(source, "figure-config.toml")) || error("报告尚未完整生成")
study=TOML.parsefile(joinpath(source, "study.toml"))
length(study["runs"])==32 || error("正式清单必须含32例")
destination=normpath(joinpath(@__DIR__, "..", "docs", "src", "assets", "r3-v2", basename(source)))
ispath(destination) && error("拒绝覆盖旧文档图源")
mkpath(destination)
for file in (
    "comparison.csv",
    "modes.csv",
    "five-initial-statistics.csv",
    "figure-config.toml",
    "evidence-hashes.toml",
    "packed-sources.toml",
    "frozen.toml",
    "config.toml",
    "study.toml",
    "render-review.toml",
    "dual-minimal-examples.toml",
)
    cp(joinpath(source, file), joinpath(destination, file))
end
cp(joinpath(source, "inputs"), joinpath(destination, "inputs"))
for name in ("single-source", "two-source"),
    suffix in ("-F08-modes.png", "-F09-dispatch.png", "-F09-source.csv")

    file=name*suffix
    cp(joinpath(source, file), joinpath(destination, file))
end
for id in ("single-delay-switch", "single-source-schpd", "two-source-schpd")
    mkdir(joinpath(destination, id))
    files=id=="single-delay-switch" ?
          [
        "F04-residuals.png",
        "F05-trajectories.png",
        "F06-iterations.png",
        "F04-source.csv.gz",
        "F05-source.csv",
        "F06-source.csv",
        "F06-trials.csv",
        "F06-local-trials.csv",
        "figure-config.toml",
    ] : ["F06-v1-v2.png", "F06-v1-v2-source.csv", "figure-config.toml"]
    for file in files
        cp(joinpath(source, id, file), joinpath(destination, id, file))
    end
end
println(destination)
for file in ("comparison.csv", "five-initial-statistics.csv", "modes.csv")
    println("TABLE ", file)
    show(stdout, MIME("text/plain"), collect(CSV.File(joinpath(source, file))))
    println()
end
