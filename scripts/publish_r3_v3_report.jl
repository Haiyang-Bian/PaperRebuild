using TOML, SHA

# 本地Documenter材料整理，不上传网站；正式摘要保持完整，网页仅复制精选图。
length(ARGS)==1 || error("usage: publish_r3_v3_report.jl SUMMARY_DIRECTORY")
source=abspath(only(ARGS))
TOML.parsefile(joinpath(source, "statistics.toml"))["runs"]==30 || error("正式报告不完整")
isfile(joinpath(source, "packed-sources.toml")) || error("先完成全量残差压缩重读")
destination=normpath(joinpath(@__DIR__, "..", "docs", "src", "assets", "r3-v3", basename(source)))
ispath(destination) && error("拒绝覆盖已发布文档图源")
mkpath(destination)
for file in (
    "comparison.csv",
    "five-initial-statistics.csv",
    "ablations.csv",
    "statistics.toml",
    "figure-config.toml",
    "provenance.toml",
    "packed-sources.toml",
    "frozen.toml",
    "study.toml",
    "render-review.toml",
    "candidate-bank.csv",
    "final-attempts.csv",
    "stationarity-probes.csv",
    "mode-embedding.toml",
    "fixed-flow-tail-audit.csv",
    "reference-recheck.toml",
    "strict-dispatch-audit.csv",
)
    cp(joinpath(source, file), joinpath(destination, file))
end
for id in
    ("two-source-schpd", "two-source-VF_CT-pg", "single-delay-switch", "single-loose-electric")
    mkdir(joinpath(destination, id))
    for file in readdir(joinpath(source, id))
        endswith(file, ".svg") && continue
        file=="F04-source.csv" && continue
        cp(joinpath(source, id, file), joinpath(destination, id, file))
    end
end
for name in ("audit", "audit-addendum-v1")
    cp(joinpath(dirname(source), name), joinpath(destination, name))
end
files=Dict{String,String}()
for (dir, _, names) in walkdir(destination), name in names
    path=joinpath(dir, name)
    files[replace(relpath(path, destination), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
open(
    io->TOML.print(io, Dict("sha256"=>files, "origin"=>"synthetic"); sorted = true),
    joinpath(destination, "asset-hashes.toml"),
    "w",
)
println(destination)
