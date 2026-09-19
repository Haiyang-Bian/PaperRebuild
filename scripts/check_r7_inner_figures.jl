using TOML, SHA, CSV
length(ARGS) in (2, 3)||error("usage: check_r7_inner_figures.jl EVIDENCE FIGURES [DOC_PNG]")
evidence, figures=abspath.(ARGS[1:2])
m=TOML.parsefile(joinpath(figures, "figure.toml"))
m["origin"]=="synthetic"&&m["reoptimized"]===false&&m["schema"]=="r7-inner-figure-v1"||error(
    "图范围错误",
)
expected=Set([
    "stages.csv",
    "summary.csv",
    "rule.toml",
    "F22-inner-faults.png",
    "F22-inner-faults.svg",
])
Set(keys(m["files"]))==expected&&Set(readdir(figures))==union(expected, Set(["figure.toml"]))||error(
    "图文件集合错误",
)
for (p, h) in m["files"]
    bytes2hex(sha256(read(joinpath(figures, p))))==h||error("图件改变")
end
for p in ("stages.csv", "summary.csv", "rule.toml")
    read(joinpath(figures, p))==read(joinpath(evidence, p))||error("图源不同")
end
rows=CSV.File(joinpath(evidence, "stages.csv"))
collect(unique(String(r.run_id) for r in rows))==m["run_ids"]||error("图运行身份错误")
m["source_manifest_sha256"]==bytes2hex(sha256(read(joinpath(evidence, "files.toml"))))||error(
    "证据身份错误",
)
length(ARGS)==3&&read(ARGS[3])!=read(joinpath(figures, "F22-inner-faults.png"))&&error("文档图不同")
println("F22 raw values, source hashes, run IDs and optional documentation copy verified.")
