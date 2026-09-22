# 仅读取保存报告，图中误差均为原值；不启动优化器。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_numerics.jl REPORT NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("不覆盖图件")
hashfile(p) = bytes2hex(sha256(read(p)))
m=TOML.parsefile(joinpath(report, "report.toml"))
for (p, h) in m["files"]
    hashfile(joinpath(report, p))==h || error("图源被修改")
end
rows=collect(CSV.File(joinpath(report, "summary.csv")))
traces=collect(CSV.File(joinpath(report, "trajectories.csv")))
groups=Dict{Tuple{String,String},Float64}()
for p in sort([p for p in keys(m["files"]) if startswith(p, "residuals-")])
    for r in CSV.File(joinpath(report, p); types = Dict(:entity=>String))
        key=(String(r.run_id), String(r.scope))
        groups[key]=max(get(groups, key, 0.0), r.residual/r.tolerance)
    end
end
ratios=[
    (run_id = k[1], scope = k[2], maximum_ratio = v) for (k, v) in sort(collect(groups); by = first)
]
fig=Figure(size = (1600, 1050), fontsize = 18)
Label(
    fig[0, 1:2],
    "F35 | Reference-anchored fixed-flow models | Synthetic 44/38 nodes, 24 h",
    fontsize = 24,
)
labels=[r.mode*"\n"*r.solver*(r.physical_model ? "\noriginal grid" : "\nSOCP") for r in rows]
ax=Axis(
    fig[1, 1],
    title = "Daily operating cost (saved values)",
    ylabel = "CNY/day",
    xticks = (1:6, labels),
    xticklabelsize = 12,
)
scatter!(
    ax,
    1:6,
    getproperty.(rows, :cost_CNY);
    color = [:royalblue, :darkorange, :royalblue, :darkorange, :royalblue, :darkorange],
    markersize = 16,
)
ar=Axis(
    fig[1, 2],
    title = "Independent maximum residual / acceptance limit",
    ylabel = "Dimensionless (log scale)",
    yscale = log10,
    xticks = (1:6, labels),
    xticklabelsize = 12,
)
for (scope, colour, offset) in (("model", :royalblue, -0.12), ("physics", :darkorange, 0.12))
    vals=[max(1e-14, get(groups, (String(r.run_id), scope), 0.0)) for r in rows]
    scatter!(ar, (1:6) .+ offset, vals; color = colour, markersize = 11, label = scope)
end
hlines!(ar, [1.0]; color = :firebrick, linestyle = :dash, label = "Acceptance limit")
axislegend(ar; position = :lb, labelsize = 13)
at=Axis(fig[2, 1], title = "Source supply temperatures", xlabel = "Hour end", ylabel = "K")
ah=Axis(fig[2, 2], title = "Heat production and PV dispatch", xlabel = "Hour end", ylabel = "MW")
selected=["cf_ct_clarabel_socp", "cf_vt_clarabel_socp"]
for (i, id) in enumerate(selected)
    x=[r for r in traces if r.run_id==id]
    colour=i==1 ? :royalblue : :darkorange
    mode=i==1 ? "CF-CT" : "CF-VT"
    lines!(
        at,
        getproperty.(x, :t),
        getproperty.(x, :source_1_K);
        color = colour,
        label = mode*" H1",
    )
    lines!(
        at,
        getproperty.(x, :t),
        getproperty.(x, :source_15_K);
        color = colour,
        linestyle = :dash,
        label = mode*" H15",
    )
    lines!(
        ah,
        getproperty.(x, :t),
        getproperty.(x, :source_heat_MW);
        color = colour,
        label = mode*" heat",
    )
    lines!(
        ah,
        getproperty.(x, :t),
        getproperty.(x, :pv_MW);
        color = colour,
        linestyle = :dot,
        label = mode*" PV",
    )
end
axislegend(at; position = :lb, labelsize = 13)
axislegend(ah; position = :lt, labelsize = 13)
Label(
    fig[3, 1:2],
    "All six pass saved-value A1, terminal and daily heat accounting | Full 16-dimensional terminal basis\nPV fully used in both modes; no curtailment benefit established | Source: "*basename(
        report,
    ),
    fontsize = 15,
)
mkpath(out)
for p in ("summary.csv", "trajectories.csv")
    cp(joinpath(report, p), joinpath(out, p))
end
CSV.write(joinpath(out, "residual-maxima.csv"), ratios)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
save(joinpath(out, "F35-r9-numerics.png"), fig; px_per_unit = 1)
save(joinpath(out, "F35-r9-numerics.svg"), fig)
files=Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out))
open(joinpath(out, "figure-config.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r9-numerics-figure-v1",
            "origin"=>"synthetic",
            "figure"=>"F35",
            "report_sha256"=>hashfile(joinpath(report, "report.toml")),
            "selected_runs"=>selected,
            "residual_plot_floor"=>1e-14,
            "width_px"=>1600,
            "height_px"=>1050,
            "files"=>files,
        );
        sorted = true,
    )
end
