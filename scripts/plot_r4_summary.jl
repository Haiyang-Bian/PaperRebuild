# 批次残差图只读摘要CSV；没有数值解的运行保留在comparison.csv中。
include("r4_setup.jl")
using CairoMakie, CSV
length(ARGS)==1 || error("提供正式R4摘要目录")
dir=ARGS[1];
meta=TOML.parsefile(joinpath(dir, "report.toml"))
comparison=collect(CSV.File(joinpath(dir, "comparison.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
selected=filter(x->x.model_pass&&x.variant!="clarabel_enumeration", comparison)
ratios=[
    maximum(
        x.residual/x.tolerance for
        x in residuals if x.run_id==r.run_id&&x.scope=="electric_original"
    ) for r in selected
]
labels=[r.case*" / "*replace(r.variant, "central_"=>"") for r in selected]
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
f=Figure(size = (1100, 700))
Label(
    f[0, 1],
    "Synthetic R4 | "*meta["batch"]*" | SOCP and original equality checks",
    tellwidth = false,
    fontsize = 17,
)
ax=Axis(
    f[1, 1],
    title = "F04  Original electric equality residuals",
    xlabel = "Max residual / unchanged A1 threshold",
    xscale = log10,
    yticks = (1:length(labels), labels),
)
barplot!(
    ax,
    1:length(ratios),
    max.(ratios, 1e-12);
    direction = :x,
    fillto = 1e-12,
    color = [r>1 ? :firebrick : :seagreen for r in ratios],
)
vlines!(ax, [1.0], color = :black, linestyle = :dash)
out=joinpath(dir, "F04-study.png")
isfile(out) && error("不覆盖已有图")
save(out, f)
CSV.write(
    joinpath(dir, "F04-study.csv"),
    [
        (run_id = selected[i].run_id, ratio = ratios[i], threshold = 1.0, pass = ratios[i]<=1) for
        i in eachindex(ratios)
    ],
)
write(
    joinpath(dir, "F04-study-config.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>meta["batch"],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "units"=>"dimensionless residual/A1",
            "scope"=>"electric_original",
            "no_solution_runs"=>"see comparison.csv",
            "origin"=>"synthetic",
            "source_sha256"=>bytes2hex(sha256(read(joinpath(dir, "residuals.csv")))),
        ),
    ),
)
println(out)
