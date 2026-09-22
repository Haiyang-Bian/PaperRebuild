using CairoMakie, CSV, TOML, SHA
length(ARGS)==1 || error("参数：热相容性报告目录")
dir=only(ARGS)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
files=["comparison.csv", "states.csv", "mass-intervals.csv", "node-intervals.csv"]
summary, states, intervals, nodes=(collect(CSV.File(joinpath(dir, f))) for f in files)
append!(files, ["residuals-reference10.csv", "residuals-reference20.csv"])
outputs=["status.png", "F04.png", "F05.png", "mass-bounds.png", "figure-config.toml"]
any(ispath(joinpath(dir, f)) for f in outputs)&&error("不覆盖已有图")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
banner="Synthetic R4 | "*meta["batch_id"]
parents=unique(x.parent for x in summary)
bands=[x["id"] for x in meta["bands"]]
stage_order=["fixed_envelope", "fixed_mixing", "free_envelope", "free_mixing"]
labels=[
    "Fixed mass\nnecessary LP",
    "Fixed mass\nmixing",
    "Free mass\nnecessary LP",
    "Free mass\nmixing",
]
colors=[:firebrick, :slategray, :seagreen, :goldenrod]
fig=Figure(size = (1700, 1400))
Label(
    fig[0, 1:2],
    banner*"\nCompatibility with frozen controls, heat and reference losses",
    tellwidth = false,
)
for (j, band) in enumerate(bands)
    ax=Axis(
        fig[1, j],
        title = band,
        yticks = (1:length(parents), parents),
        xticks = (1:4, labels),
        yreversed = true,
        yticklabelsize = 12,
        xticklabelsize = 13,
    )
    for (i, parent) in enumerate(parents), (k, stage) in enumerate(stage_order)
        row=only(filter(x->x.parent==parent&&x.band==band&&x.stage==stage, summary))
        index=row.pass ? 3 :
              row.status=="solver_infeasible" ? 1 :
              row.status=="necessary_condition_infeasible" ? 2 : 4
        scatter!(ax, [k], [i]; marker = :rect, markersize = 20, color = colors[index])
    end
    xlims!(ax, 0.5, 4.5)
    ylims!(ax, 0.5, length(parents)+0.5)
end
Legend(
    fig[2, 1:2],
    [MarkerElement(color = c, marker = :rect, markersize = 14) for c in colors],
    [
        "Solver infeasible",
        "Skipped: necessary LP infeasible",
        "Independent pass",
        "Unresolved / failed candidate",
    ];
    orientation = :horizontal,
    tellwidth = false,
    labelsize = 13,
)
save(joinpath(dir, "status.png"), fig)

fig=Figure(size = (1450, 1100))
Label(
    fig[0, 1:2],
    banner*"\nDetailed temperature candidates: independent residuals / unchanged A1",
    tellwidth = false,
)
for (j, band) in enumerate(bands), (k, stage) in enumerate(("fixed_mixing", "free_mixing"))
    ax=Axis(
        fig[k, j],
        title = band*" / "*stage,
        xlabel = "Parent index (first appearance in comparison.csv)",
        ylabel = "Maximum residual / tolerance",
        yscale = log10,
    )
    rows=filter(x->x.band==band&&x.stage==stage&&x.independent_checked, summary)
    xx=[findfirst(==(x.parent), parents) for x in rows]
    yy=[max(1e-10, x.max_normalized_residual) for x in rows]
    scatter!(ax, xx, yy; color = :steelblue, markersize = 12)
    hlines!(ax, [1.0]; color = :crimson, linestyle = :dash)
    ylims!(ax, 1e-10, 2)
    xlims!(ax, 0.5, length(parents)+0.5)
end
Label(
    fig[3, 1:2],
    "No candidate = no residual point. Passing this check excludes hydraulics, dynamics and temperature-dependent losses.",
    tellwidth = false,
    fontsize = 13,
)
save(joinpath(dir, "F04.png"), fig)

# 在绘图前明确固定示例身份，不按费用或残差挑选最优候选。
example="import--fixed--exact"
band="reference10"
rr=filter(x->x.parent==example&&x.band==band&&x.stage=="free_mixing", states)
fig=Figure(size = (1250, 950))
Label(fig[0, 1:2], banner*"\n"*example*" / "*band*" / free_mixing", tellwidth = false)
palette=[:steelblue, :darkorange, :seagreen]
ax=Axis(
    fig[1, 1:2],
    xlabel = "Period",
    ylabel = "Pipe mass flow (kg/s)",
    title = "Same heat delivery and cost; old versus reconstructed mass",
)
for p in 1:2
    rows=sort(filter(x->x.variable=="m_pipe"&&x.entity==p, rr); by = x->x.t)
    scatterlines!(
        ax,
        [x.t for x in rows],
        [x.value for x in rows];
        color = palette[p],
        label = "Pipe $p reconstructed",
    )
    lines!(
        ax,
        [x.t for x in rows],
        [x.old_value for x in rows];
        color = palette[p],
        linestyle = :dash,
        label = "Pipe $p old",
    )
end
axislegend(ax; position = :rt, labelsize = 12)
for (col, variable, title, limits) in (
    (1, "τ_S", "Supply mixing temperature", (343.15, 363.15)),
    (2, "τ_R", "Return mixing temperature", (303.15, 323.15)),
)
    local ax=Axis(fig[2, col]; xlabel = "Period", ylabel = "Temperature (K)", title)
    for i in 1:3
        rows=sort(filter(x->x.variable==variable&&x.entity==i, rr); by = x->x.t)
        scatterlines!(
            ax,
            [x.t for x in rows],
            [x.value for x in rows];
            color = palette[i],
            label = "Node $i",
        )
    end
    hlines!(ax, collect(limits); color = :black, linestyle = :dash)
    ylims!(ax, limits[1]-1, limits[2]+1)
    axislegend(ax; position = :rt, labelsize = 11)
end
save(joinpath(dir, "F05.png"), fig)

fig=Figure(size = (1350, 650))
Label(
    fig[0, 1:2],
    banner*"\nOpen-trading necessary-condition contradictions (free mass)",
    tellwidth = false,
)
for (j, band) in enumerate(bands)
    local ax=Axis(
        fig[1, j],
        title = band,
        xlabel = "Constraint interval index",
        ylabel = "Positive inconsistency in mass bounds (kg/s)",
    )
    rows=filter(
        x->startswith(x.parent, "open--")&&x.band==band&&x.stage=="free_envelope"&&x.materially_empty,
        intervals,
    )
    nr=filter(
        x->startswith(x.parent, "open--")&&x.band==band&&x.stage=="free_envelope"&&x.materially_excludes_zero,
        nodes,
    )
    vals=vcat([x.gap_kg_s for x in rows], [x.gap_kg_s for x in nr])
    if isempty(vals)
        text!(
            ax,
            0.5,
            0.5;
            text = "No single-interval certificate.\nSee solver and coupled constraints.",
            space = :relative,
            align = (:center, :center),
        )
    else
        scatter!(ax, 1:length(vals), vals; color = :firebrick, markersize = 8)
    end
    hlines!(ax, [0.0]; color = :black)
end
save(joinpath(dir, "mass-bounds.png"), fig)
config=Dict(
    "batch_id"=>meta["batch_id"],
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "units"=>["kg/s", "K", "MW", "normalized residual", "USD_synthetic"],
    "illustration_parent"=>example,
    "illustration_band"=>band,
    "scope"=>"Fixed reference losses; reconstructed steady temperatures and mass; no pressure/dynamic certification.",
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("R4 heat figures generated from saved evidence only.")
