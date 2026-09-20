using CairoMakie, CSV, TOML, SHA
length(ARGS)==3 || error("usage: plot_r9_pv.jl REPORT ATTRIBUTION NEW_FIGURES")
report, attribution, out=abspath.(ARGS)
ispath(out) && error("不覆盖图件")
manifest=TOML.parsefile(joinpath(report, "report.toml"))
hashfile(p) = bytes2hex(sha256(read(p)))
for (p, h) in manifest["files"]
    hashfile(joinpath(report, p))==h || error("报告文件改变")
end
summary=collect(CSV.File(joinpath(report, "summary.csv")))
traces=collect(CSV.File(joinpath(report, "trajectories.csv")))
am=TOML.parsefile(joinpath(attribution, "manifest.toml"))
for (p, h) in am["files"]
    hashfile(joinpath(attribution, p))==h || error("归因文件改变")
end
arows=collect(CSV.File(joinpath(attribution, "attribution.csv")))
energy_pass=Dict(r.id=>r.periodic_energy_pass for r in arows)
fig=Figure(size = (1550, 1000), fontsize = 19)
Label(
    fig[0, 1:2],
    "F34 | 44 electrical / 38 thermal nodes | 24 h synthetic replacement",
    fontsize = 25,
)
labels=[replace(r.id, "_"=>"\n"; count = 2) for r in summary]
ax=Axis(
    fig[1, 1],
    title = "Saved candidate cost (see physical flags)",
    ylabel = "CNY/day",
    xticks = (1:length(summary), labels),
    xticklabelsize = 12,
)
for (i, r) in enumerate(summary)
    ismissing(r.cost_CNY) && continue
    scatter!(
        ax,
        [i],
        [r.cost_CNY],
        color = r.physical_pass && get(energy_pass, r.id, false) ? :seagreen : :darkorange,
        markersize = 15,
    )
end
axpv=Axis(fig[1, 2], title = "PV availability and dispatch", xlabel = "Hour end", ylabel = "MW")
axheat=Axis(
    fig[2, 1],
    title = "Heat production and common load",
    xlabel = "Hour end",
    ylabel = "MW",
)
axtemp=Axis(fig[2, 2], title = "Source supply temperature", xlabel = "Hour end", ylabel = "K")
selected=["cf_ct_clarabel_socp", "cf_vt_clarabel_socp"]
for (i, id) in enumerate(selected)
    x=[r for r in traces if r.run_id==id]
    isempty(x) && continue
    colour=i==1 ? :royalblue : :darkorange
    mode=i==1 ? "CF-CT" : "CF-VT"
    if i==1
        lines!(
            axpv,
            getproperty.(x, :t),
            getproperty.(x, :pv_available_MW),
            color = :gray,
            linestyle = :dash,
            label = "Available",
        )
        lines!(
            axheat,
            getproperty.(x, :t),
            getproperty.(x, :heat_load_MW),
            color = :gray,
            linestyle = :dash,
            label = "Heat load",
        )
    end
    lines!(axpv, getproperty.(x, :t), getproperty.(x, :pv_used_MW), color = colour, label = mode)
    lines!(
        axheat,
        getproperty.(x, :t),
        getproperty.(x, :heat_source_MW),
        color = colour,
        label = mode,
    )
    lines!(
        axtemp,
        getproperty.(x, :t),
        getproperty.(x, :source1_K),
        color = colour,
        label = mode*" H1",
    )
    lines!(
        axtemp,
        getproperty.(x, :t),
        getproperty.(x, :source15_K),
        color = colour,
        linestyle = :dash,
        label = mode*" H15",
    )
end
for a in (axpv, axheat, axtemp)
    axislegend(a; position = :lb, labelsize = 13)
end
Label(
    fig[3, 1:2],
    "Common frozen CF-CT memory | Source: "*basename(report)*"\nCF-VT passes per-row A1 but fails the extra daily energy check (0.000216 MWh); cost benefit remains provisional",
    fontsize = 15,
)
mkpath(out)
for name in ("summary.csv", "trajectories.csv")
    cp(joinpath(report, name), joinpath(out, name))
end
cp(@__FILE__, joinpath(out, "plot_r9_pv.jl"))
cp(joinpath(attribution, "attribution.csv"), joinpath(out, "attribution.csv"))
save(joinpath(out, "F34-r9-pv.png"), fig; px_per_unit = 1)
save(joinpath(out, "F34-r9-pv.svg"), fig)
files=[
    "summary.csv",
    "trajectories.csv",
    "attribution.csv",
    "plot_r9_pv.jl",
    "F34-r9-pv.png",
    "F34-r9-pv.svg",
]
open(joinpath(out, "figure-config.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r9-pv-figure-v1",
            "origin"=>"synthetic",
            "figure"=>"F34",
            "width_px"=>1550,
            "height_px"=>1000,
            "report_sha256"=>hashfile(joinpath(report, "report.toml")),
            "attribution_manifest_sha256"=>hashfile(joinpath(attribution, "manifest.toml")),
            "selected_runs"=>selected,
            "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in files),
        );
        sorted = true,
    )
end
