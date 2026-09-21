# F47只读已封存CSV；不加载模型、不求解、不修改原证据。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: EVIDENCE NEW_FIGURES")
evidence, out=abspath.(ARGS)
ispath(out) && error("不覆盖原图")
hashfile(p) = bytes2hex(sha256(read(p)))
artifacts=TOML.parsefile(joinpath(evidence, "artifacts.toml"))
index=TOML.parsefile(joinpath(evidence, "index.toml"))
index["schema"]=="r9-resilience-evidence-v1" || error("错误证据类型")
files=["summary.csv", "trajectories.csv", "residuals.csv", "capacity.csv", "devices.csv"]
for file in files
    hashfile(joinpath(evidence, file))==artifacts["files"][file] || error("图源改变")
end
summary=collect(CSV.File(joinpath(evidence, "summary.csv")))
trajectory=collect(CSV.File(joinpath(evidence, "trajectories.csv")))
residuals=collect(CSV.File(joinpath(evidence, "residuals.csv")))
capacity=collect(CSV.File(joinpath(evidence, "capacity.csv")))
rec=filter(x->x.stage!="normal", summary)
labels=[
    (startswith(r.stage, "aggregate-") ? "Aggregate" : "Detailed")*"\n"*split(
        r.stage,
        '-';
        limit = 2,
    )[2] for r in rec
]
colors=[startswith(r.stage, "aggregate-") ? :steelblue : :darkorange for r in rec]
fig=Figure(size = (1640, 1450), fontsize = 19)
Label(fig[0, 1:2], "F47 | 44 electric / 38 heat nodes | Declared substitute inputs", fontsize = 27)
ax=Axis(
    fig[1, 1];
    title = "Four-hour critical electricity not supplied",
    ylabel = "Unserved critical load (MWh)",
    xticks = (1:length(rec), labels),
    xticklabelsize = 13,
)
barplot!(ax, 1:length(rec), [r.critical_unserved_MWh for r in rec]; color = colors)
hlines!(
    ax,
    [2.0];
    color = :firebrick,
    linestyle = :dash,
    linewidth = 2,
    label = "Declared target: 2 MWh",
)
scatter!(
    ax,
    1:length(rec),
    [r.analytic_lower_MWh for r in rec];
    color = :black,
    marker = :hline,
    markersize = 26,
    label = "Generation-capacity lower bound",
)
ylims!(ax, 0, 13)
axislegend(ax; position = :lt, labelsize = 15)
bx=Axis(
    fig[1, 2];
    title = "Detailed fixed-flow restoration",
    xlabel = "Event start time (hour of day)",
    ylabel = "Critical electric power (MW)",
)
faults=["external_only", "single_1_2", "author_event1"]
palette=[:darkgreen, :purple, :darkorange]
for (fault, color) in zip(faults, palette)
    rows=filter(x->x.stage=="detailed-"*fault, trajectory)
    stairs!(
        bx,
        [r.time_h for r in rows],
        [r.critical_served_MW for r in rows];
        step = :post,
        color = color,
        linewidth = 3,
        label = fault,
    )
end
rows=filter(x->x.stage=="detailed-external_only", capacity)
stairs!(
    bx,
    [r.time_h for r in rows],
    [r.critical_MW for r in rows];
    step = :post,
    color = :black,
    linestyle = :dash,
    linewidth = 2,
    label = "Critical demand",
)
stairs!(
    bx,
    [r.time_h for r in rows],
    [r.generation_upper_MW for r in rows];
    step = :post,
    color = :gray,
    linestyle = :dot,
    linewidth = 2,
    label = "Generation upper bound",
)
axislegend(bx; position = :lb, labelsize = 15)
cx=Axis(
    fig[2, 1];
    title = "Independent residual / existing A1 threshold",
    ylabel = "Largest normalized residual (log scale)",
    yscale = log10,
    xticks = (1:length(summary), vcat(["Normal"], labels)),
    xticklabelsize = 13,
)
ratios=[maximum(r.maximum_normalized for r in residuals if r.stage==s.stage) for s in summary]
scatter!(cx, 1:length(summary), max.(ratios, 1e-15); color = vcat([:gray], colors), markersize = 15)
hlines!(cx, [1.0]; color = :firebrick, linestyle = :dash, linewidth = 2)
ylims!(cx, min(1e-7, minimum(max.(ratios, 1e-15))/3), 2)
dx=Axis(
    fig[2, 2];
    title = "Economic normal schedule; event inherits this state",
    xlabel = "Hour of day",
    ylabel = "Electric power (MW)",
)
normal=filter(r->r.stage=="normal", trajectory)
vspan!(dx, 10, 14; color = (:orange, 0.12))
stairs!(
    dx,
    [r.time_h for r in normal],
    [r.pcc_MW for r in normal];
    step = :post,
    color = :steelblue,
    linewidth = 2,
    label = "External import",
)
stairs!(
    dx,
    [r.time_h for r in normal],
    [r.generation_MW for r in normal];
    step = :post,
    color = :darkgreen,
    linewidth = 2,
    label = "Local generation",
)
axislegend(dx; position = :lt, labelsize = 15)
Label(
    fig[3, 1:2],
    "Aggregate and detailed cases have different flow-control domains. Ordinary electricity and heat shedding are not secondary objectives.\n$(count(s->s.model_pass,rec))/$(length(rec)) recovery candidates passed the adopted model checks; AC power flow, hydraulics and the 42-fault universe are not certified.",
    fontsize = 18,
    tellheight = true,
)
ids=[s.stage*" = "*s.run_id for s in summary]
Label(fig[4, 1:2], join(ids, "\n"); fontsize = 13, halign = :left, tellheight = true)
mkpath(out)
for ext in ("png", "svg", "pdf")
    save(joinpath(out, "F47-resilience-pilot."*ext), fig)
end
for file in files
    cp(joinpath(evidence, file), joinpath(out, file))
end
cp(@__FILE__, joinpath(out, "plot-source.jl"))
provenance=Dict(
    "schema"=>"r9-resilience-figure-v1",
    "origin"=>index["origin"],
    "figure"=>"F47",
    "evidence_manifest_sha256"=>hashfile(joinpath(evidence, "artifacts.toml")),
    "run_ids"=>[s.run_id for s in summary],
    "optimization_performed"=>false,
    "units"=>["MW", "MWh", "hour", "residual/tolerance"],
    "files"=>Dict(f=>hashfile(joinpath(out, f)) for f in readdir(out)),
)
open(io->TOML.print(io, provenance; sorted = true), joinpath(out, "figure-source.toml"), "w")
println("F47 saved from frozen values; no optimization.")
