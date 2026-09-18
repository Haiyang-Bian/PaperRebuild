# 图仅从封存运行导出的数值绘制；不优化、不改变调度。
include("r4_setup.jl")
using CairoMakie, CSV
length(ARGS)==1 || error("参数：新批次报告目录")
dir=ARGS[1]
meta=TOML.parsefile(joinpath(dir, "report.toml"))
comparisons=collect(CSV.File(joinpath(dir, "comparison.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
contracts=collect(CSV.File(joinpath(dir, "contracts.csv")))
pairs=TOML.parsefile(joinpath(dir, "surplus.toml"))["pairs"]
any(isfile(joinpath(dir, f)) for f in ("F04.png", "F10.png", "F12.png")) &&
    error("不覆盖已有科学图")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 16))
title="Synthetic R4 | "*meta["batch"]*" | static heat energy model"
selected=filter(x->x.model_pass&&x.variant!="clarabel_enumeration", comparisons)
ratios=[
    maximum(
        x.residual/x.tolerance for
        x in residuals if x.run_id==r.run_id&&x.scope=="electric_original"
    ) for r in selected
]
fig=Figure(size = (1180, 650))
Label(fig[0, 1], title, fontsize = 17, tellwidth = false)
ax=Axis(
    fig[1, 1],
    title = "F04  Original electric equality: residual / A1",
    xscale = log10,
    xlabel = "Dimensionless; dashed line = unchanged A1 threshold",
    yticks = (1:length(selected), [r.case*" / "*r.variant for r in selected]),
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
save(joinpath(dir, "F04.png"), fig)
CSV.write(
    joinpath(dir, "F04-source.csv"),
    [(run_id = selected[i].run_id, ratio = ratios[i], threshold = 1.0) for i in eachindex(ratios)],
)

qualified=filter(p->p["eligible"], pairs)
isempty(qualified) && error("没有合格分歧点，不绘制收益柱")
fig=Figure(size = (1160, 680))
Label(
    fig[0, 1:2],
    title*"\nF12  Costs and utility gains; no bargaining",
    fontsize = 17,
    tellwidth = false,
)
labels=[p["case"] for p in qualified]
ax=Axis(
    fig[1, 1],
    title = "Same-input resource costs",
    ylabel = "Synthetic USD",
    xticks = (1:length(labels), labels),
)
positions=repeat(collect(1:length(labels)), inner = 2)
costs=reduce(vcat, [[p["independent_cost"], p["central_cost"]] for p in qualified])
groups=repeat([1, 2], length(labels))
barplot!(ax, positions, costs, dodge = groups, color = [:gray60, :steelblue][groups])
Legend(
    fig[2, 1],
    [PolyElement(color = :gray60), PolyElement(color = :steelblue)],
    ["Independent", "Central"],
    orientation = :horizontal,
)
ay=Axis(
    fig[1, 2],
    title = "Central utility minus independent utility",
    ylabel = "Synthetic USD",
    xticks = (1:length(labels), labels),
)
positions=repeat(collect(1:length(labels)), inner = 3)
gains=reduce(vcat, [[a["utility_gain"] for a in p["actors"]] for p in qualified])
groups=repeat([1, 2, 3], length(labels))
colors=[:darkorange, :steelblue, :seagreen]
barplot!(ay, positions, gains, dodge = groups, color = colors[groups])
hlines!(ay, [0], color = :black)
Legend(
    fig[2, 2],
    [PolyElement(color = c) for c in colors],
    ["DSO", "A", "B"],
    orientation = :horizontal,
)
Label(
    fig[3, 1:2],
    "Payments redistribute the saving; positive total does not guarantee individual participation.",
    tellwidth = false,
    fontsize = 15,
)
save(joinpath(dir, "F12.png"), fig)

fig=Figure(size = (1100, 760))
Label(
    fig[0, 1:2],
    title*"\nF10  Import-only flexible case: node injections",
    tellwidth = false,
    fontsize = 17,
)
for (col, carrier) in enumerate(("P", "H")), (row, actor) in enumerate(("A", "B"))
    axis=Axis(
        fig[row, col],
        title = actor*" / "*carrier,
        xlabel = "Hour",
        ylabel = "Net injection (MW)",
    )
    for (variant, color) in (("independent_exact", :gray40), ("central_exact", :steelblue))
        run="import_flexible--"*variant
        points=sort(
            filter(x->x.run_id==run&&x.actor==actor&&x.carrier==carrier, contracts),
            by = x->x.t,
        )
        isempty(points) && continue
        scatterlines!(
            axis,
            [x.t for x in points],
            [x.net_MW for x in points],
            color = color,
            label = variant,
        )
    end
    hlines!(axis, [0], color = :black, linestyle = :dash)
    axislegend(axis, position = :rb, labelsize = 12)
end
save(joinpath(dir, "F10.png"), fig)
sources=Dict(
    f=>bytes2hex(sha256(read(joinpath(dir, f)))) for
    f in ("comparison.csv", "residuals.csv", "contracts.csv", "surplus.toml")
)
write(
    joinpath(dir, "figure-config.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>meta["batch"],
            "origin"=>"synthetic",
            "bargaining"=>"not_performed",
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "source_sha256"=>sources,
            "figures"=>["F04", "F10", "F12"],
            "units"=>["residual/A1", "MW", "USD_synthetic"],
        ),
    ),
)
println("F04/F10/F12 generated from saved values.")
