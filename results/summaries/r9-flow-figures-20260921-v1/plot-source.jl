# F36读取已核验原值表；缺失模式留空，不优化、不伪装PG收敛。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_flow_reference.jl REPORT NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("Do not overwrite figures")
hashfile(p) = bytes2hex(sha256(read(p)))
for (p, h) in TOML.parsefile(joinpath(report, "artifact-hashes.toml"))["files"]
    hashfile(joinpath(report, p))==h || error("Figure input changed")
end
rows=collect(CSV.File(joinpath(report, "summary.csv")))
formal=[r for r in rows if r.group=="formal"]
traces=collect(CSV.File(joinpath(report, "trajectories.csv")))
ratios=collect(CSV.File(joinpath(report, "ratios.csv")))
colours=[:royalblue, :grey, :darkorange, :seagreen]
fig=Figure(size = (1650, 1080), fontsize = 19)
Label(
    fig[0, 1:2],
    "F36 | Four-mode direct local reference | Synthetic 44/38 nodes, 24 h",
    fontsize = 24,
)
ac=Axis(
    fig[1, 1],
    title = "Periodic accepted candidates (no global bound)",
    ylabel = "Operating cost (CNY/day)",
    xticks = (1:4, [replace(r.mode, "_"=>"-") for r in formal]),
)
for (i, r) in enumerate(formal)
    if r.periodic_comparison_eligible
        scatter!(ac, [i], [r.cost_CNY]; color = colours[i], markersize = 18)
        text!(
            ac,
            i,
            r.cost_CNY;
            text = string(round(r.cost_CNY; digits = 2)),
            offset = (0, 14),
            align = (:center, :bottom),
            fontsize = 15,
        )
    else
        text!(
            ac,
            i,
            491000;
            text = "No candidate\n(iteration limit)",
            align = (:center, :center),
            fontsize = 15,
        )
    end
end
xlims!(ac, 0.5, 4.5)
ylims!(ac, 489000, 507000)
ar=Axis(
    fig[1, 2],
    title = "Independent residual / A1 limit",
    ylabel = "Dimensionless (log scale)",
    yscale = log10,
    xticks = (1:4, [replace(r.mode, "_"=>"-") for r in formal]),
)
for (i, r) in enumerate(formal)
    rs=[x.max_ratio for x in ratios if x.run_id==r.run_id]
    isempty(rs) || scatter!(
        ar,
        [i],
        [max(maximum(rs), r.energy_ratio, 1e-14)];
        color = colours[i],
        markersize = 16,
    )
end
hlines!(ar, [1.0]; color = :firebrick, linestyle = :dash)
af=Axis(
    fig[2, 1],
    title = "Pipe 1 mass flow (saved direct candidates)",
    xlabel = "Hour end",
    ylabel = "kg/s",
)
at=Axis(fig[2, 2], title = "Source 1 supply temperature", xlabel = "Hour end", ylabel = "K")
for (i, r) in enumerate(formal)
    r.periodic_comparison_eligible || continue
    values=[x for x in traces if x.run_id==r.run_id]
    lines!(
        af,
        [x.t for x in values],
        [x.flow_1_kg_s for x in values];
        color = colours[i],
        label = r.mode,
    )
    lines!(
        at,
        [x.t for x in values],
        [x.source_1_K for x in values];
        color = colours[i],
        label = r.mode,
    )
end
axislegend(af; position = :lt, labelsize = 14)
axislegend(at; position = :lb, labelsize = 14)
free=only(r for r in rows if occursin("terminal-free", r.run_id))
Label(
    fig[3, 1:2],
    "Temperature-terminal-free diagnostic: memory change = $(round(free.memory_change_MWh;digits=3)) MWh; excluded from periodic comparison.\nAll accepted modes use 83.16 MWh PV. Native NLP iterations are not projected-gradient iterations.",
    fontsize = 16,
)
mkpath(out)
for name in ("summary.csv", "trajectories.csv", "ratios.csv", "memory.csv", "iterations.csv")
    cp(joinpath(report, name), joinpath(out, name))
end
save(joinpath(out, "F36-flow-reference.png"), fig)
save(joinpath(out, "F36-flow-reference.pdf"), fig)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "figure_id"=>"F36",
    "origin"=>"synthetic",
    "run_ids"=>[r.run_id for r in formal],
    "input_index_sha256"=>hashfile(joinpath(report, "index.toml")),
    "optimization_performed"=>false,
    "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out)),
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure.toml"), "w")
println("F36 redrawn from saved values; no optimization")
