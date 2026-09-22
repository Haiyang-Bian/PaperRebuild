# F48只读封存CSV，缺失/不可行方案不绘成零费用或零失供。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_preplan.jl EVIDENCE NEW_FIGURES")
evidence, out=abspath.(ARGS)
ispath(out) && error("不覆盖已有图表")
hashfile(p) = bytes2hex(sha256(read(p)))
art=TOML.parsefile(joinpath(evidence, "artifacts.toml"))
index=TOML.parsefile(joinpath(evidence, "index.toml"))
index["schema"]=="r9-preplan-evidence-v1" || error("图源版本错误")
sources=[
    "primary.csv",
    "summary.csv",
    "residuals.csv",
    "commitments.csv",
    "devices.csv",
    "initial-states.csv",
    "trajectories.csv",
    "capacity.csv",
    "witnesses.csv",
]
for file in sources
    hashfile(joinpath(evidence, file))==art["files"][file] || error("图源被改变")
end
primary=collect(CSV.File(joinpath(evidence, "primary.csv")))
summary=collect(CSV.File(joinpath(evidence, "summary.csv")))
residuals=collect(CSV.File(joinpath(evidence, "residuals.csv")))
commitment=collect(CSV.File(joinpath(evidence, "commitments.csv")))
modes=["economic", "penalty", "threshold"]
labels=["4A economic", "4B penalty", "4C threshold"]
colors=[:steelblue, :darkorange, :forestgreen]
finite(x) = x isa Real && isfinite(x)
fig=Figure(size = (1720, 1340), fontsize = 19)
Label(
    fig[0, 1:2],
    "F48 | Shared preplanning, selected 3 faults | Declared substitute inputs",
    fontsize = 25,
)
a=Axis(
    fig[1, 1],
    title = "Normal resource cost and modeled loss penalty",
    ylabel = "CNY per day / 1000",
    xticks = (1:3, labels),
)
values=Float64[]
for (i, mode) in enumerate(modes)
    r=only(filter(x->x.mode==mode, primary))
    if finite(r.normal_cost_CNY)
        barplot!(
            a,
            [i-0.16],
            [r.normal_cost_CNY/1000];
            width = 0.3,
            color = :steelblue,
            label = i==1 ? "Normal cost" : nothing,
        )
        barplot!(
            a,
            [i+0.16],
            [r.objective_CNY/1000];
            width = 0.3,
            color = :darkorange,
            label = i==1 ? "Optimization objective" : nothing,
        )
        append!(values, [r.normal_cost_CNY/1000, r.objective_CNY/1000])
    end
end
upper=maximum(values)*1.2
ylims!(a, 0, upper)
xlims!(a, 0.5, 3.5)
for (i, mode) in enumerate(modes)
    r=only(filter(x->x.mode==mode, primary))
    finite(r.normal_cost_CNY) || text!(
        a,
        i,
        0.2upper;
        text = "No accepted\nnormal plan",
        align = (:center, :center),
        fontsize = 17,
        color = :firebrick,
    )
end
axislegend(a; position = :lt, labelsize = 15)
b=Axis(
    fig[1, 2],
    title = "Worst independently optimized critical loss",
    ylabel = "Critical electricity not supplied (MWh)",
    xticks = (1:3, labels),
)
for (i, mode) in enumerate(modes),
    (j, kind, color) in ((1, "aggregate", :steelblue), (2, "detailed", :darkorange))

    rows=filter(r->r.mode==mode && startswith(r.stage, kind*"-"), summary)
    good=filter(r->r.model_pass && finite(r.critical_unserved_MWh), rows)
    if length(good)==3
        y=maximum(r.critical_unserved_MWh for r in good)
        barplot!(
            b,
            [i+(j==1 ? -0.16 : 0.16)],
            [y];
            width = 0.3,
            color,
            label = i==1 ? kind : nothing,
        )
    elseif j==1
        text!(
            b,
            i,
            4;
            text = "Unresolved",
            align = (:center, :center),
            color = :firebrick,
            fontsize = 17,
        )
    end
end
hlines!(
    b,
    [2.0];
    color = :firebrick,
    linestyle = :dash,
    linewidth = 2,
    label = "Declared target: 2 MWh",
)
xlims!(b, 0.5, 3.5)
ylims!(b, 0, 14)
axislegend(b; position = :rt, labelsize = 15)
c=Axis(
    fig[2, 1],
    title = "CHP event preparation (offset by method)",
    xlabel = "Hour of day",
    ylabel = "Commitment; vertical offset only",
    yticks = ([0, 1, 2, 3], ["4A off", "4A on", "4B off", "4B on"]),
)
vspan!(c, [10.0], [14.0]; color = (:gray, 0.14))
for (i, mode) in enumerate(modes), (device, style) in (("CHP1", :dash), ("CHP2", :solid))
    rows=sort(filter(r->r.mode==mode&&r.device==device, commitment); by = x->x.time_h)
    isempty(rows) && continue
    times=vcat([r.time_h for r in rows], 24.0)
    vals=vcat([r.commitment for r in rows], last(rows).commitment) .+ 2(i-1)
    stairs!(
        c,
        times,
        vals;
        step = :post,
        color = colors[i],
        linestyle = style,
        linewidth = 3,
        label = labels[i]*" "*device,
    )
end
axislegend(c; position = :rt, labelsize = 14)
d=Axis(
    fig[2, 2],
    title = "Maximum residual over saved stages",
    ylabel = "Residual / declared tolerance (log10)",
    yscale = log10,
    xticks = (1:3, labels),
)
maxratio=1.0
for (i, mode) in enumerate(modes),
    (scope, marker, color) in (
        ("adopted", :circle, :steelblue),
        ("exact_exchange", :xcross, :firebrick),
        ("pipe_reference", :utriangle, :forestgreen),
    )

    rows=filter(r->r.mode==mode&&r.scope==scope, residuals)
    isempty(rows) && continue
    v=max(1e-12, maximum(r.maximum_normalized for r in rows))
    global maxratio=max(maxratio, v)
    scatter!(d, [i], [v]; marker, color, markersize = 18, label = i==1 ? scope : nothing)
end
hlines!(d, [1.0]; linestyle = :dash, color = :black, label = "Acceptance boundary")
ylims!(d, 1e-12, maxratio*10)
xlims!(d, 0.5, 3.5)
text!(
    d,
    3.0,
    10.0;
    text = "No candidate",
    align = (:center, :center),
    fontsize = 17,
    color = :firebrick,
)
axislegend(d; position = :rb, labelsize = 14)
Label(
    fig[3, 1:2],
    "Aggregate recourse and detailed fixed-flow recourse have different controls. No full-fault or AC/dynamic certificate.",
    fontsize = 17,
)
Label(
    fig[4, 1:2],
    join([r.mode*": "*r.run_id for r in primary], "\n");
    fontsize = 14,
    halign = :left,
)
mkpath(out)
save(joinpath(out, "F48-preplan-comparison.png"), fig; px_per_unit = 1.4)
save(joinpath(out, "F48-preplan-comparison.svg"), fig)
for file in sources
    cp(joinpath(evidence, file), joinpath(out, file))
end
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "schema"=>"r9-preplan-figure-v1",
    "figure"=>"F48",
    "source_index_sha256"=>hashfile(joinpath(evidence, "index.toml")),
    "run_ids"=>[r.run_id for r in primary],
    "origin"=>index["origin"],
    "optimization_performed"=>false,
    "missing_values_plotted_as_zero"=>false,
    "residual_scope_preserved"=>true,
    "presentation_revision"=>2,
    "fixed_mode_axis_includes_missing_candidates"=>true,
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure.toml"), "w")
hashes=Dict(f=>hashfile(joinpath(out, f)) for f in readdir(out))
open(io->TOML.print(io, Dict("files"=>hashes); sorted = true), joinpath(out, "artifacts.toml"), "w")
println("F48 saved from frozen values.")
