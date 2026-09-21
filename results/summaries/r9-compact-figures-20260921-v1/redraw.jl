# 仅由配对报告CSV重绘，不启动任何优化器。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: COMPARISON NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("Preserve previous figure")
hashfile(p) = bytes2hex(sha256(read(p)))
m=TOML.parsefile(joinpath(report, "comparison-source.toml"))
m["schema"]=="r9-compact-comparison-v1" && !m["optimization_performed"] || error("Report scope")
for (p, h) in m["files"]
    hashfile(joinpath(report, p))==h || error("Figure source changed")
end
rows=collect(CSV.File(joinpath(report, "summary.csv")))
residuals=collect(CSV.File(joinpath(report, "residuals.csv")))
times=collect(CSV.File(joinpath(report, "timings.csv")))
labels=[r.scheme*"\n"*(r.representation=="original" ? "original" : "compact") for r in rows]
colors=[r.representation=="original" ? :steelblue : :darkorange for r in rows]
fig=Figure(size = (1500, 1600), fontsize = 18)
Label(
    fig[0, 1:2],
    "F46 | Synthetic 100-scenario risk models | Same input, seed and 600 s budget",
    fontsize = 24,
)
ax=Axis(
    fig[1, 1],
    xticks = (1:6, labels),
    ylabel = "Cost (CNY/day)",
    title = "Verified candidate and valid solver lower bound",
)
for (i, r) in enumerate(rows)
    r.checked && scatter!(ax, [i], [r.cost_CNY]; color = colors[i], markersize = 15)
    r.valid_bound &&
        scatter!(ax, [i], [r.lower_CNY]; color = colors[i], marker = :dtriangle, markersize = 15)
    r.checked && r.valid_bound && lines!(ax, [i, i], [r.lower_CNY, r.cost_CNY]; color = colors[i])
end
Legend(
    fig[1, 2],
    [
        MarkerElement(color = :black, marker = :circle),
        MarkerElement(color = :black, marker = :dtriangle),
        PolyElement(color = :steelblue),
        PolyElement(color = :darkorange),
    ],
    [
        "Independent model/risk/cost pass",
        "Valid solver lower bound",
        "Original representation",
        "Equivalent compact representation",
    ],
    "Missing marker = no verified candidate/bound";
    framevisible = false,
)
ax2=Axis(
    fig[2, 1],
    xticks = (1:6, labels),
    ylabel = "Complete process (s)",
    title = "Loading, model, optimization and validation",
)
barplot!(ax2, 1:6, [r.elapsed_sec for r in rows]; color = colors)
hlines!(ax2, [600]; color = :firebrick, linestyle = :dash)
ax3=Axis(
    fig[2, 2],
    xticks = (1:6, labels),
    ylabel = "Actual PV energy (MWh/day)",
    title = "Empirical expected use in returned candidate",
)
ax4=Axis(
    fig[3, 1],
    xticks = (1:6, labels),
    ylabel = "Maximum absolute reserve (MW)",
    title = "Reserve commitments; no candidate = no bar",
)
for (i, r) in enumerate(rows)
    r.has_candidate || continue
    barplot!(ax3, [i], [r.PV_empirical_energy_MWh]; color = colors[i])
    barplot!(ax4, [i], [r.reserve_peak_MW]; color = colors[i])
end
present=filter(r->r.has_candidate, rows)
if !isempty(present) && maximum(r.reserve_peak_MW for r in present)<=1e-9
    ylims!(ax4, 0, 0.01)
end
ax5=Axis(
    fig[3, 2],
    xticks = (1:6, labels),
    ylabel = "Maximum residual / A1 tolerance",
    yscale = log10,
    title = "Original constraints, not reformulated rows",
)
for (i, r) in enumerate(rows)
    xs=filter(x->x.scheme==r.scheme && x.representation==r.representation, residuals)
    isempty(xs) && continue
    scatter!(
        ax5,
        [i],
        [max(1e-12, maximum(x.normalized for x in xs))];
        color = colors[i],
        markersize = 15,
    )
end
hlines!(ax5, [1]; color = :firebrick, linestyle = :dash)
xlims!(ax5, 0.5, 6.5)
ax6=Axis(
    fig[4, 1:2],
    xticks = (1:4, ["Build", "Map + audit", "Native start", "Optimize"]),
    ylabel = "Recorded stage (s)",
    title = "Selected recorded stages; not a disjoint full-time partition",
)
stages=["build_sec", "mapping_and_audit_sec", "native_start_sec", "optimization_sec"]
for (i, r) in enumerate(rows)
    xs=filter(x->x.scheme==r.scheme && x.representation==r.representation, times)
    xvals=Float64[]
    yvals=Float64[]
    for (j, stage) in enumerate(stages)
        t=filter(x->x.stage==stage, xs)
        isempty(t) && continue
        push!(xvals, j+(i-3.5)*0.11)
        push!(yvals, only(t).seconds)
    end
    isempty(xvals) || barplot!(ax6, xvals, yvals; width = 0.1, color = colors[i])
end
Label(
    fig[5, 1:2],
    "Representation and log observation changed. No held-out or author same-input claim. Zero-height candidate bars retain raw values in CSV.",
    fontsize = 14,
)
Label(
    fig[6, 1:2],
    join([r.scheme*" / "*r.representation*" / "*r.status*" / "*r.run_id for r in rows], "\n"),
    fontsize = 11,
)
mkpath(out)
for ext in ("png", "pdf")
    save(joinpath(out, "F46-compact-comparison."*ext), fig)
end
for p in ("summary.csv", "timings.csv", "commitments.csv", "residuals.csv")
    cp(joinpath(report, p), joinpath(out, p))
end
cp(@__FILE__, joinpath(out, "redraw.jl"))
meta=Dict(
    "schema"=>"r9-compact-figure-v1",
    "origin"=>"synthetic",
    "optimization_performed"=>false,
    "report_sha256"=>hashfile(joinpath(report, "comparison-source.toml")),
    "run_ids"=>[r.run_id for r in rows],
    "units"=>["CNY/day", "s", "MW", "MWh/day", "residual/tolerance"],
    "residual_display_floor"=>1e-12,
    "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out)),
)
open(io->TOML.print(io, meta; sorted = true), joinpath(out, "figure-source.toml"), "w")
println("F46 drawn from saved values; no optimization.")
