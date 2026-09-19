using CSV, CairoMakie, TOML, SHA

length(ARGS)==2||error("usage: plot_r7_inner.jl SAVED_EVIDENCE NEW_DIR")
src, out=abspath.(ARGS)
ispath(out)&&error("不覆盖已有图件")
hashes=TOML.parsefile(joinpath(src, "files.toml"))["files"]
for p in ("stages.csv", "summary.csv", "rule.toml")
    bytes2hex(sha256(read(joinpath(src, p))))==hashes[p]||error("图源哈希改变")
end
rows=collect(CSV.File(joinpath(src, "stages.csv")))
fig=Figure(size = (1320, 920), fontsize = 16)
Label(
    fig[0, :],
    "F22 | Worst-fault search with verified recourse (synthetic)",
    fontsize = 23,
    tellwidth = false,
)
names=["inner-tie-two-hour", "inner-tie-bottleneck", "inner-tie-two-fault"]
titles=[
    "Single fault\nNormal capacity",
    "Single fault\nLine limit 0.3 MW",
    "Two faults\nInfeasible CHP island",
]
top=fig[1, :]=GridLayout()
for (col, (name, title)) in enumerate(zip(names, titles))
    rr=filter(r->r.case==name, rows)
    ax=Axis(
        top[1, col],
        title = title,
        xlabel = "Inner master iteration",
        ylabel = col==1 ? "Loss (MWh)" : "",
        xticks = 1:length(rr),
    )
    scatterlines!(
        ax,
        [r.iteration for r in rr],
        [r.restricted_value_MWh for r in rr],
        color = :darkorange,
        linewidth = 3,
        markersize = 9,
        label = "Restricted objective (capped)",
    )
    lo=filter(r->isfinite(r.lower_bound_MWh), rr)
    hi=filter(r->isfinite(r.upper_bound_MWh), rr)
    isempty(lo)||scatterlines!(
        ax,
        [r.iteration for r in lo],
        [r.lower_bound_MWh for r in lo],
        color = :steelblue,
        linewidth = 3,
        markersize = 10,
        label = "Full-recourse lower bound",
    )
    isempty(hi)||scatter!(
        ax,
        [r.iteration for r in hi],
        [r.upper_bound_MWh for r in hi],
        color = :seagreen,
        marker = :diamond,
        markersize = 18,
        label = "Finite upper bound",
    )
    hlines!(ax, [rr[1].cap_MWh], color = :gray, linestyle = :dot, label = "Certification cap C")
    ylims!(ax, -0.12, rr[1].cap_MWh+0.15)
    col==3&&text!(
        ax,
        1.1,
        0.6;
        text = "No feasible recovery\nWorst loss = infinity",
        fontsize = 14,
        color = :firebrick,
    )
end
for col in 1:3
    colsize!(top, col, Relative(1/3))
end
Legend(
    fig[2, :],
    [
        LineElement(color = :darkorange, linewidth = 3),
        LineElement(color = :steelblue, linewidth = 3),
        MarkerElement(color = :seagreen, marker = :diamond, markersize = 14),
        LineElement(color = :gray, linestyle = :dot),
    ],
    ["Restricted objective (capped)", "Verified lower bound", "Finite upper bound", "Cap C"],
    orientation = :horizontal,
    tellwidth = false,
)
ax=Axis(
    fig[3, :],
    title = "Original worst-loss bounds: infinity is recorded, never plotted as the cap",
    xlabel = "Inner master iteration",
    ylabel = "Bound status",
    xticks = 1:4,
    yticks = (1:3, ["normal capacity", "line bottleneck", "two faults"]),
)
for (k, name) in enumerate(names)
    for r in filter(r->r.case==name, rows)
        label=isinf(r.lower_bound_MWh) ? "infeasible" :
              isfinite(r.upper_bound_MWh) ? "bounds closed" : "upper unresolved"
        color=isinf(r.lower_bound_MWh) ? :firebrick :
              isfinite(r.upper_bound_MWh) ? :seagreen : :gray
        scatter!(ax, [r.iteration], [k], color = color, markersize = 16)
        text!(
            ax,
            r.iteration,
            k+0.14,
            text = label,
            align = (:center, :bottom),
            fontsize = 12,
            color = color,
        )
    end
end
xlims!(ax, 0.5, 4.5);
ylims!(ax, 0.65, 3.6)
ids=unique(String(r.run_id) for r in rows)
Label(
    fig[4, :],
    "Three nodes, three lines, two hours; every case checked against all faults and valid topology LPs.\nAdopted linear electric grid and two-tank heat model; no AC-grid or detailed disaster heat certification.",
    fontsize = 14,
    tellwidth = false,
)
Label(
    fig[5, :],
    "Saved run IDs: "*join([last(split(id, '-')) for id in ids], ", ")*" | Full IDs, units and input rules accompany the figure.",
    fontsize = 12,
    tellwidth = false,
)
mkpath(out)
for p in ("stages.csv", "summary.csv", "rule.toml")
    cp(joinpath(src, p), joinpath(out, p))
end
save(joinpath(out, "F22-inner-faults.png"), fig)
save(joinpath(out, "F22-inner-faults.svg"), fig)
meta=Dict(
    "schema"=>"r7-inner-figure-v1",
    "origin"=>"synthetic",
    "reoptimized"=>false,
    "run_ids"=>ids,
    "source_manifest_sha256"=>bytes2hex(sha256(read(joinpath(src, "files.toml")))),
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "files"=>Dict(p=>bytes2hex(sha256(read(joinpath(out, p)))) for p in readdir(out)),
)
open(io->TOML.print(io, meta; sorted = true), joinpath(out, "figure.toml"), "w")
println("F22 plotted from saved values without optimization.")
