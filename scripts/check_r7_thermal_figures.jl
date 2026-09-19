using TOML, SHA, CSV
length(ARGS) in (2, 3) || error("usage: check_r7_thermal_figures.jl REPORT FIGURES [DOC_PNG]")
src, out=abspath.(ARGS[1:2]);
d=TOML.parsefile(joinpath(out, "figure.toml"))
d["origin"]=="synthetic"&&d["solver_called"]===false || error("图范围错误")
for (p, h) in d["files"]
    bytes2hex(sha256(read(joinpath(out, p))))==h || error("图文件篡改")
    endswith(p, ".csv")||p=="rule.toml" || continue
    read(joinpath(src, p))==read(joinpath(out, p)) || error("图源不是冻结原值")
end
Set(d["run_ids"])==Set(r.run_id for r in CSV.File(joinpath(src, "summary.csv"))) ||
    error("图运行ID不符")
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r7_thermal.jl"))))==d["source_sha256"] ||
    error("绘图源码改变")
length(ARGS)==3 &&
    read(ARGS[3])!=read(joinpath(out, "F23-thermal-delivery.png")) &&
    error("文档图与证据不符")
println("F23 source rows, hashes, run IDs and optional documentation copy checked.")
