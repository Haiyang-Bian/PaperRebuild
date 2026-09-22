# 固定物理调度，只绘制已有分配与补偿；不会再次求解或改写父运行。
include("r4_setup.jl")
using CairoMakie, CSV
length(ARGS)==1 || error("参数：未绘图的新报告目录")
dir=only(ARGS)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
rows=collect(CSV.File(joinpath(dir, "allocations.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
any(isfile(joinpath(dir, f)) for f in ("F12.png", "F04.png", "figure-config.toml")) &&
    error("不覆盖已有图表")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 16))
colors=[:gray55, :steelblue, :darkorange]
fig=Figure(size = (1160, 700))
Label(
    fig[0, 1:2],
    "Synthetic R4 | "*meta["batch"]*"\nF12  Participation gains on unchanged physical dispatch",
    fontsize = 17,
    tellwidth = false,
)
for (col, name) in enumerate(("import_flexible", "import_fixed"))
    axis=Axis(
        fig[1, col],
        title = name,
        ylabel = "Utility gain vs AG0 (synthetic USD)",
        xticks = (1:3, ["DSO", "A", "B"]),
    )
    capacity=filter(r->r.case==name&&r.rule=="capacity_load_v1", rows)
    equal=filter(r->r.case==name&&r.rule=="equal_v1", rows)
    values=reduce(vcat, [[capacity[i].previous_gain, capacity[i].gain, equal[i].gain] for i in 1:3])
    groups=repeat([1, 2, 3], 3)
    barplot!(axis, repeat(collect(1:3), inner = 3), values; dodge = groups, color = colors[groups])
    hlines!(axis, [0], color = :black)
end
Legend(
    fig[2, 1:2],
    [PolyElement(color = c) for c in colors],
    ["Old retail settlement", "Capacity + peak-load weights", "Equal weights"],
    orientation = :horizontal,
)
Label(
    fig[3, 1:2],
    "Unrestricted, budget-balanced transfers | Same cost and dispatch | Not TSPA or coalition stability",
    tellwidth = false,
    fontsize = 15,
)
save(joinpath(dir, "F12.png"), fig)

ids=unique(r.run_id for r in residuals)
ratios=[
    maximum(
        r.tolerance>0 ? r.residual/r.tolerance : r.pass ? 0.0 : Inf for
        r in residuals if r.run_id==id
    ) for id in ids
]
fig=Figure(size = (1180, 480))
Label(fig[0, 1], "Synthetic R4 | "*meta["batch"], fontsize = 17, tellwidth = false)
ax=Axis(
    fig[1, 1],
    title = "F04  Allocation checks: largest residual / threshold",
    xscale = log10,
    xlabel = "Dimensionless; physical parent checks remain separate",
    yticks = (1:length(ids), ids),
)
barplot!(ax, 1:length(ids), max.(ratios, 1e-14); direction = :x, fillto = 1e-14, color = :seagreen)
vlines!(ax, [1.0], color = :black, linestyle = :dash)
save(joinpath(dir, "F04.png"), fig)
CSV.write(
    joinpath(dir, "F04-source.csv"),
    [(run_id = ids[i], ratio = ratios[i], threshold = 1.0) for i in eachindex(ids)],
)
write(
    joinpath(dir, "figure-config.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>meta["batch"],
            "origin"=>"synthetic",
            "source_sha256"=>Dict(
                f=>bytes2hex(sha256(read(joinpath(dir, f)))) for
                f in ("allocations.csv", "residuals.csv")
            ),
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "figures"=>["F04", "F12"],
            "units"=>["dimensionless", "USD_synthetic"],
            "scope"=>"allocation checks; physical dispatch unchanged",
        ),
    ),
)
println("F04/F12 redrawn from saved allocation data.")
