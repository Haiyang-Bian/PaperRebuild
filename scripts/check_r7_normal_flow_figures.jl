using TOML, SHA, CSV
length(ARGS) in (2, 3) || error("usage: check_r7_normal_flow_figures.jl REPORT FIGURES [DOC_ASSET]")
report, figures=abspath.(ARGS[1:2]);
hashfile(p) = bytes2hex(sha256(read(p)))
cfg=TOML.parsefile(joinpath(figures, "figure-config.toml"))
for (p, h) in TOML.parsefile(joinpath(figures, "files.toml"))["files"]
    !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
        x->!(x in ("", ".", "..")),
        split(p, '/'),
    ) || error("图件路径错误")
    hashfile(joinpath(figures, p))==h || error("图件篡改")
end
for (p, h) in cfg["source_hashes"]
    hashfile(joinpath(report, p))==hashfile(joinpath(figures, p))==h || error("图源与原报告不一致")
end
Set(cfg["run_ids"])==Set(
    String.(getproperty.(collect(CSV.File(joinpath(report, "summary.csv"))), :run_id)),
) || error("图件运行ID缺失")
cfg["script_sha256"]==hashfile(joinpath(@__DIR__, "plot_r7_normal_flow.jl")) ||
    error("绘图源码变化")
length(ARGS)==3 &&
    hashfile(ARGS[3])!=hashfile(joinpath(figures, "F28-normal-flow.png")) &&
    error("文档副本变化")
println("F28 files, source tables, run IDs and optional document copy verified.")
