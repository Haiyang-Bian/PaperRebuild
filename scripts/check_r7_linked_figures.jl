using CSV, TOML, SHA
length(ARGS) in (2, 3) || error("usage: check_r7_linked_figures.jl REPORT FIGURES [DOC_PNG]")
src, out=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
d=TOML.parsefile(joinpath(out, "figure.toml"))
d["origin"]=="synthetic" && d["solver_called"]===false || error("图件范围错误")
Set(readdir(out))==union(Set(keys(d["files"])), Set(["figure.toml"])) || error("图件文件集合改变")
for (p, h) in d["files"]
    hashfile(joinpath(out, p))==h || error("图件内容改变")
    endswith(p, ".csv")||p=="rule.toml" || continue
    read(joinpath(out, p))==read(joinpath(src, p)) || error("图源不是原保存值")
end
d["run_ids"]==String.([r.run_id for r in CSV.File(joinpath(src, "summary.csv"))]) || error("运行ID改变")
d["report_manifest_sha256"]==hashfile(joinpath(src, "files.toml")) || error("报告身份改变")
d["source_sha256"]==hashfile(joinpath(@__DIR__, "plot_r7_linked.jl")) || error("绘图源码改变")
length(ARGS)==3 &&
    read(ARGS[3])!=read(joinpath(out, "F27-linked-planning.png")) &&
    error("文档图副本改变")
println("F27 raw tables, run IDs, source, units and documentation copy checked.")
