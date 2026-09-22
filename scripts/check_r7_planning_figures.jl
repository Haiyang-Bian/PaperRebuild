using TOML, SHA, CSV
length(ARGS) in (2, 3) || error("usage: check_r7_planning_figures.jl EVIDENCE FIGURES [DOC_PNG]")
evidence, figures=abspath.(ARGS[1:2])
meta=TOML.parsefile(joinpath(figures, "figure.toml"))
meta["schema"]=="r7-planning-figure-v1"&&meta["origin"]=="synthetic"&&meta["reoptimized"]===false ||
    error("图件范围错误")
expected=Set([
    "F21-finite-planning.png",
    "F21-finite-planning.svg",
    "summary.csv",
    "stages.csv",
    "battery.csv",
    "rule.toml",
])
Set(keys(meta["files"]))==expected&&Set(readdir(figures))==union(expected, Set(["figure.toml"])) ||
    error("图件清单错误")
for (p, h) in meta["files"]
    bytes2hex(sha256(read(joinpath(figures, p))))==h || error("图件被修改")
end
for p in ("summary.csv", "stages.csv", "battery.csv", "rule.toml")
    read(joinpath(figures, p))==read(joinpath(evidence, p)) || error("图源与原报告不同")
end
meta["source_rule_sha256"]==bytes2hex(sha256(read(joinpath(evidence, "rule.toml")))) ||
    error("图件输入身份错误")
meta["run_ids"]==[String(r.run_id) for r in CSV.File(joinpath(evidence, "summary.csv"))] || error("图件运行ID错误")
length(ARGS)==3&&read(ARGS[3])!=read(joinpath(figures, "F21-finite-planning.png"))&&error(
    "文档图不是同字节副本",
)
println("F21 figure, units, IDs, raw sources and optional documentation copy verified.")
