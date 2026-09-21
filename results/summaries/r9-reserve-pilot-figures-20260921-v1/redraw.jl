# 图表仅使用已核验的公开表格；不重新求解、不将训练结果称为样本外保证。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_reserve.jl EVIDENCE NEW_FIGURES")
input, out=abspath.(ARGS)
ispath(out) && error("Preserve previous figures")
hashfile(p) = bytes2hex(sha256(read(p)))
hashes=TOML.parsefile(joinpath(input, "artifact-hashes.toml"))["files"]
files=["summary.csv", "trajectories.csv", "scenarios.csv", "residuals.csv", "support.csv"]
string_columns=Dict(
    "summary.csv"=>[:method,:scheme,:run_id,:case_sha256,:status],
    "trajectories.csv"=>[:method,:run_id],
    "scenarios.csv"=>[:method,:run_id,:scenario],
    "residuals.csv"=>[:method,:run_id,:group,:worst_id],
    "support.csv"=>[:method,:scenario],
)
for name in files
    hashfile(joinpath(input, name))==hashes[name] || error("Figure source changed")
end
data=Dict(
    name=>collect(
        CSV.File(
            joinpath(input, name);
            types = Dict(k=>String for k in string_columns[name]),
        ),
    ) for name in files
)
s=data["summary.csv"]
colors=[:steelblue, :darkorange, :seagreen]
schemes=["3A", "3B", "3C"]
order=[only(filter(r->r.scheme==scheme, s)) for scheme in schemes]
scope=all(r.pilot for r in order) ? "4-point development pilot" : "100-scenario formal run"
f=Figure(size = (1280, 1080), fontsize = 17)
Label(f[0, 1], "F41 | Synthetic 44/38 nodes, 24 h | "*scope, fontsize = 24)
a=Axis(
    f[1, 1],
    ylabel = "Cost (CNY/day)",
    title = "Empirical cost and each model's own worst-distribution objective",
    xticks = (1:3, schemes),
)
for (i, r) in enumerate(order)
    if isfinite(r.empirical_cost_CNY)
        barplot!(
            a,
            [i-0.16],
            [r.empirical_cost_CNY];
            width = 0.3,
            color = colors[i],
            label = i==1 ? "Common empirical weights" : nothing,
        )
        barplot!(
            a,
            [i+0.16],
            [r.worst_cost_CNY];
            width = 0.3,
            color = (colors[i], 0.35),
            label = i==1 ? "Own worst distribution" : nothing,
        )
    else
        text!(
            a,
            i,
            0.0;
            text = "No certified\ncost",
            align = (:center, :bottom),
            color = :firebrick,
        )
    end
end
any(isfinite(r.empirical_cost_CNY) for r in order) && axislegend(a; position = :lb, labelsize = 14)
for (row, key, label) in
    ((2, :R_up_MW, "Upward reserve (MW)"), (3, :R_down_MW, "Downward reserve (MW)"))
    ax=Axis(f[row, 1], xlabel = "Hour", ylabel = label, xticks = 1:3:24)
    for (i, r) in enumerate(order)
        tr=filter(x->x.method==r.method, data["trajectories.csv"])
        isempty(tr) || lines!(
            ax,
            [x.t for x in tr],
            [getproperty(x, key) for x in tr];
            color = colors[i],
            label = r.scheme,
        )
    end
    if isempty(data["trajectories.csv"])
        text!(ax, .5, .5;space=:relative,text="No saved dispatch candidate",align=(:center,:center))
    else
        axislegend(ax; position = :rt, labelsize = 14)
    end
end
Label(
    f[4, 1],
    "Complete-trajectory recourse; finite support only. No out-of-sample or AC/hydraulic guarantee.",
    fontsize = 15,
)
g=Figure(size = (1280, 1100), fontsize = 17)
Label(g[0, 1], "F42 | "*scope*" | Comfort risk and residuals", fontsize = 24)
b=Axis(
    g[1, 1],
    xlabel = "Frozen representative index",
    ylabel = "Worst probability of one event",
    title = "Each representative violating alone; this is a support-geometry diagnostic",
)
for (i, r) in enumerate(order)
    q=filter(x->x.method==r.method, data["support.csv"])
    lines!(b, 1:length(q), [x.worst_single_event for x in q]; color = colors[i], label = r.scheme)
end
hlines!(b, [0.05]; color = :black, linestyle = :dash, label = "3B/3C epsilon = 0.05")
axislegend(b; position = :rt, labelsize = 14)
c=Axis(
    g[2, 1],
    xlabel = "Scheme",
    ylabel = "Training joint comfort event probability",
    xticks = (1:3, schemes),
)
for (i, r) in enumerate(order)
    isfinite(r.worst_event_probability) || continue
    scatter!(
        c,
        [i-0.1],
        [r.empirical_event_probability];
        color = colors[i],
        marker = :circle,
        markersize = 14,
    )
    scatter!(
        c,
        [i+0.1],
        [r.worst_event_probability];
        color = colors[i],
        marker = :rect,
        markersize = 14,
    )
end
hlines!(c, [0.05]; color = :black, linestyle = :dash)
ylims!(c, -0.005, 0.07)
any(isfinite(r.worst_event_probability) for r in order) || text!(c,.5,.5;space=:relative,text="No certified risk candidate",align=(:center,:center))
groups=sort(unique(x.group for x in data["residuals.csv"]))
d=Axis(
    g[3, 1],
    ylabel = "Maximum residual / A1 threshold",
    yscale = log10,
    xticks = (1:length(groups), groups),
    xticklabelrotation = pi/4,
)
for (i, r) in enumerate(order)
    rr=filter(x->x.method==r.method, data["residuals.csv"])
    isempty(rr) || scatter!(
        d,
        [findfirst(==(x.group), groups) for x in rr],
        [max(1e-12, x.maximum_normalized) for x in rr];
        color = colors[i],
        label = r.scheme,
        markersize = 9,
    )
end
hlines!(d, [1.0]; color = :firebrick, linestyle = :dash)
isempty(groups) && text!(d,.5,.5;space=:relative,text="No primal witness; residuals are unavailable",align=(:center,:center))
Label(
    g[4, 1],
    "Zero residuals plotted at 1e-12. Circles: empirical events; squares: worst-distribution events.",
    fontsize = 14,
)
mkpath(out)
for (name, fig) in (("F41-reserve-commitments", f), ("F42-reserve-risk-residuals", g))
    save(joinpath(out, name*".png"), fig)
    save(joinpath(out, name*".pdf"), fig)
end
meta=Dict(
    "schema"=>"r9-reserve-figure-v1",
    "origin"=>"synthetic",
    "currency"=>"CNY",
    "source_evidence_sha256"=>hashfile(joinpath(input, "artifact-hashes.toml")),
    "source_tables"=>Dict(k=>hashes[k] for k in files),
    "run_ids"=>[r.run_id for r in order],
    "script_sha256"=>hashfile(@__FILE__),
    "optimization_performed"=>false,
)
open(io->TOML.print(io, meta; sorted = true), joinpath(out, "figure-source.toml"), "w")
cp(@__FILE__, joinpath(out, "redraw.jl"))
println("F41/F42 rendered solely from saved tables.")
