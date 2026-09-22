# F37仅读取封存表；失败候选不计作合格调度，互补性与物理A1分别显示。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_fixed.jl ARCHIVE NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("Do not overwrite figures")
hashfile(p) = bytes2hex(sha256(read(p)))
for (p, h) in TOML.parsefile(joinpath(report, "artifact-hashes.toml"))["files"]
    hashfile(joinpath(report, p))==h || error("Figure input changed")
end
rows=collect(CSV.File(joinpath(report, "summary.csv")))
ratios=collect(CSV.File(joinpath(report, "ratios.csv")))
traces=collect(CSV.File(joinpath(report, "trajectories.csv")))
diag=collect(CSV.File(joinpath(report, "diagnostics.csv")))
labels=["literal\nClarabel", "literal\nGurobi", "band\nClarabel", "band\nGurobi"]
colours=[:royalblue, :darkorange, :seagreen, :purple]
fig=Figure(size = (1580, 1040), fontsize = 18)
Label(fig[0, 1:2], "F37 | Fixed VF-VT flow | Synthetic 44/38 nodes, 24 h", fontsize = 25)
ar=Axis(
    fig[1, 1],
    title = "Independent residual / declared limit",
    ylabel = "Dimensionless (log scale)",
    yscale = log10,
    xticks = (1:4, labels),
)
for (i, r) in enumerate(rows), (j, scope) in enumerate(("physical", "periodic", "adopted_terminal"))
    rr=only(x for x in ratios if x.run_id==r.run_id && x.scope==scope)
    rr.rows>0 || continue
    scatter!(
        ar,
        [i+(j-2)*0.13],
        [max(rr.max_ratio, 1e-8)];
        color = colours[i],
        marker = (:circle, :rect, :diamond)[j],
        markersize = 14,
    )
end
hlines!(ar, [1.0]; color = :red, linestyle = :dash)
ylims!(ar, 1e-8, 1e3)
Legend(
    fig[3, 1:2],
    [MarkerElement(marker = m, color = :grey, markersize = 14) for m in (:circle, :rect, :diamond)],
    ["Original physical equations", "Periodic state (original A1)", "Declared band (1e-10 K)"];
    tellwidth = false,
    orientation = :horizontal,
)
ak=Axis(
    fig[1, 2],
    title = "KKT complementarity / unchanged 1e-6 limit",
    ylabel = "Dimensionless (log scale)",
    yscale = log10,
    xticks = (1:4, labels),
)
for (i, r) in enumerate(rows)
    scatter!(ak, [i], [max(r.kkt_complementarity/1e-6, 1e-8)]; color = colours[i], markersize = 17)
end
hlines!(ak, [1.0]; color = :red, linestyle = :dash)
ylims!(ak, 0.1, 2e6)
# 第二行使用两个热源的同口径源温；费用不作为未通过模型的可实施收益。
sources=sort(unique(x.node for x in traces))
for (j, node) in enumerate(sources)
    ax=Axis(
        fig[2, j],
        title = "Source at heat node $node",
        xlabel = "Hour",
        ylabel = "Supply temperature (K)",
    )
    for (i, r) in enumerate(rows)
        tr=sort([x for x in traces if x.run_id==r.run_id && x.node==node]; by = x->x.t)
        lines!(
            ax,
            [x.t for x in tr],
            [x.source_temperature_K for x in tr];
            color = colours[i],
            linestyle = i<=2 ? :solid : :dash,
            label = replace(labels[i], '\n'=>' '),
        )
    end
    j==1 && axislegend(ax; position = :lb, labelsize = 13)
end
change=only(x.value for x in diag if x.metric=="source_projection_max_change")
Label(
    fig[4, 1:2],
    "Exact-kernel projection changed a known feasible source control by " *
    string(round(change; digits = 3)) *
    " K: diagnostic only. All four KKT checks failed.",
    fontsize = 18,
)
Label(
    fig[5, 1:2],
    "Run IDs: " *
    join([r.run_id for r in rows], ", ") *
    "\n" *
    "Band points fail the declared 1e-10 K terminal check; original A1 is unchanged. No PG run.",
    fontsize = 14,
)
mkpath(out)
save(joinpath(out, "F37-fixed-flow.png"), fig)
save(joinpath(out, "F37-fixed-flow.svg"), fig)
for name in ("summary.csv", "ratios.csv", "trajectories.csv", "diagnostics.csv")
    cp(joinpath(report, name), joinpath(out, name))
end
cp(@__FILE__, joinpath(out, "plot-source.jl"))
figure_files=Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out))
open(joinpath(out, "figure.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r9-fixed-figure-v1",
            "origin"=>"synthetic",
            "figure"=>"F37",
            "solver_run"=>false,
            "width"=>1580,
            "height"=>1040,
            "source_index_sha256"=>hashfile(joinpath(report, "index.toml")),
            "files"=>figure_files,
        );
        sorted = true,
    )
end
println("F37 generated from saved values; no optimization.")
