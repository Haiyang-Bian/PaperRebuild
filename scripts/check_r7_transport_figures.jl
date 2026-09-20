using CSV, TOML, SHA
length(ARGS) in (3, 4) ||
    error("usage: check_r7_transport_figures.jl REPORT RECHECK FIGURES [DOC_PNG]")
src, revised, out = abspath.(ARGS[1:3])
hashfile(p) = bytes2hex(sha256(read(p)))
d = TOML.parsefile(joinpath(out, "figure.toml"))
d["origin"] == "synthetic" && d["solver_called"] === false || error("图范围错误")
Set(readdir(out)) == union(Set(keys(d["files"])), Set(["figure.toml"])) || error("图文件集合改变")
for (p, h) in d["files"]
    hashfile(joinpath(out, p)) == h || error("图文件篡改")
    if p in ("recheck-summary.csv", "zero-branch.csv", "recheck.toml")
        original = p == "recheck-summary.csv" ? "summary.csv" : p
        read(joinpath(revised, original)) == read(joinpath(out, p)) || error("补证图源不是原值")
    elseif endswith(p, ".csv") || p in ("inputs.toml", "rule.toml")
        read(joinpath(src, p)) == read(joinpath(out, p)) || error("原报告图源不是原值")
    end
end
ids = [r.run_id for r in CSV.File(joinpath(src, "summary.csv"))]
ids == d["run_ids"] || error("图运行ID改变")
hashfile(joinpath(@__DIR__, "plot_r7_transport.jl")) == d["source_sha256"] || error("绘图源码改变")
length(ARGS) == 4 &&
    read(ARGS[4]) != read(joinpath(out, "F25-transport-redispatch.png")) &&
    error("文档图副本改变")
println(
    "F25 original values, separate correction, run IDs, plot source and documentation copy checked.",
)
