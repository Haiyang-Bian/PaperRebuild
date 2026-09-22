# F39/F40仅读取封存结果；没有候选的位置不画零费用柱。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_network.jl SUMMARY NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("Do not overwrite figures")
hashfile(p) = bytes2hex(sha256(read(p)))
meta=TOML.parsefile(joinpath(report, "evidence.toml"))
for (rel, h) in meta["derived_files"]
    hashfile(joinpath(report, rel))==h || error("Figure source changed")
end
summary=collect(CSV.File(joinpath(report, "summary.csv"); types = Dict(:method=>String)))
tops=collect(
    CSV.File(joinpath(report, "topologies.csv"); types = Dict(:method=>String, :side=>String)),
)
traces=collect(CSV.File(joinpath(report, "trajectories.csv"); types = Dict(:method=>String)))
groups=[("legacy", "fixed"), ("legacy", "joint"), ("equipment", "fixed"), ("equipment", "joint")]
central=filter(x->x.operation=="central", summary)
fig=Figure(size = (1280, 1050), fontsize = 18)
Label(fig[0, 1], "F39 | Synthetic 44/38-node trading | Access design and topology", fontsize = 24)
a=Axis(
    fig[1, 1],
    ylabel = "Validated candidate cost (CNY)",
    title = "Central dispatch; separate SOCP and original electrical equations",
    xticks = (1:4, ["Legacy / fixed", "Legacy / joint", "Equipment / fixed", "Equipment / joint"]),
)
for (el, offset, color) in (("socp", -0.16, :steelblue), ("exact", 0.16, :darkorange))
    x=Float64[]
    y=Float64[]
    for (i, (design, policy)) in enumerate(groups)
        r=only(filter(q->q.design==design&&q.policy==policy&&q.electric==el, central))
        if r.adopted_physical_pass
            push!(x, i+offset)
            push!(y, r.system_cost_CNY)
        end
    end
    barplot!(
        a,
        x,
        y;
        width = 0.3,
        color,
        label = el=="socp" ? "SOCP candidate passes original checks" :
                "Original-equation candidate",
    )
end
maxcost=maximum((x.system_cost_CNY for x in central if x.adopted_physical_pass); init = 1.0)
for (i, (design, policy)) in enumerate(groups)
    candidates=filter(x->x.design==design&&x.policy==policy&&x.adopted_physical_pass, central)
    isempty(candidates) && text!(
        a,
        i,
        0.35maxcost;
        text = "No accepted\nschedule",
        align = (:center, :center),
        color = :firebrick,
        fontsize = 17,
    )
end
axislegend(a; position = :lt, labelsize = 14)
xlims!(a,0.5,4.5)
b=Axis(
    fig[2, 1],
    title = "Every frozen method; gray means no network candidate",
    xticks = (1:4, ["Model", "Original grid", "Heat envelope", "Ledger"]),
    yticks = (
        1:16,
        [
            replace(x.method, "independent"=>"AG0", "central"=>"CENT", "equipment"=>"new") for
            x in summary
        ],
    ),
    yreversed = true,
    yticklabelsize = 12,
)
z=zeros(4, 16)
for (j, r) in enumerate(summary),
    (i, key) in enumerate((:model_pass, :electric_original_pass, :heat_pass, :ledger_pass))

    z[i, j]=r.has_candidate ? (getproperty(r, key) ? 1 : 0) : -1
end
heatmap!(b, 1:4, 1:16, z; colormap = [:lightgray, :firebrick, :seagreen], colorrange = (-1, 1))
c=Axis(
    fig[3, 1],
    ylabel = "Maximum residual / A1 tolerance",
    yscale = log10,
    title = "Independent original-value checks (only saved candidates)",
    xticks = (
        1:length(central),
        [replace(x.method, "central-"=>"", "equipment"=>"new") for x in central],
    ),
    xticklabelrotation = 0.2,
    xticklabelsize = 11,
)
for (key, color, label) in (
    (:max_model_normalized_residual, :steelblue, "Adopted model"),
    (:max_original_normalized_residual, :darkorange, "Original grid equality"),
)
    idx=findall(x->x.has_candidate, central)
    scatter!(
        c,
        idx,
        [max(1e-12, getproperty(central[i], key)) for i in idx];
        color,
        markersize = 11,
        label,
    )
end
hlines!(c, [1.0]; color = :red, linestyle = :dash, label = "A1 threshold")
axislegend(c; position = :lt, labelsize = 12)
xlims!(c,0.5,length(central)+0.5)
Label(
    fig[4, 1],
    "Study: " *
    meta["study"] *
    " | Synthetic parameters; steady heat envelope; no bargaining\n" *
    "Topology is compared within a design. No feasible AG0 cost is invented. Candidate cost is not a global proof.",
    fontsize = 13,
)
mkpath(out)
save(joinpath(out, "F39-cost-and-validation.png"), fig)
save(joinpath(out, "F39-cost-and-validation.svg"), fig)

fig2=Figure(size = (1280, 1080), fontsize = 18)
Label(fig2[0, 1], "F40 | Synthetic input | Physical candidate topology and energy", fontsize = 24)
ids=["equipment-fixed-central-exact", "equipment-joint-central-exact"]
for (col, id) in enumerate(ids)
    r=only(filter(x->x.method==id, summary))
    a=Axis(
        fig2[1, col],
        title = replace(id, "equipment-"=>""),
        xlabel = "Hour index",
        ylabel = "Switchable edge / valve",
        yticklabelsize = 12,
    )
    rows=filter(x->x.method==id, tops)
    if r.adopted_physical_pass
        # 全部有动作或初始为常开的边；固定对照读取同一候选图的联络边。
        pairs=unique((x.side, x.edge, x.from, x.to) for x in rows if x.action>0.5||x.initial==0)
        isempty(pairs) && (pairs=unique((x.side, x.edge, x.from, x.to) for x in rows))
        values=zeros(24, length(pairs))
        for (j, (side, edge, _, _)) in enumerate(pairs), t in 1:24
            values[t, j]=only(
                x for x in rows if x.side==side&&x.edge==edge&&x.t==(side=="heat" ? 1 : t)
            ).on
        end
        a.yticks=(
            1:length(pairs),
            [uppercase(side[1:1])*" "*string(i)*"–"*string(j) for (side, _, i, j) in pairs],
        )
        heatmap!(
            a,
            1:24,
            1:length(pairs),
            values;
            colormap = [:lightgray, :seagreen],
            colorrange = (0, 1),
        )
    else
        text!(a, 0.5, 0.5; text = "No physically accepted candidate", align = (:center, :center))
    end
end
e=Axis(
    fig2[2, 1:2],
    xlabel = "Hour index",
    ylabel = "Grid import (MW)",
    title = "Same loads and resources",
)
h=Axis(
    fig2[3, 1:2],
    xlabel = "Hour index",
    ylabel = "Reference heat loss (MW)",
    title = "Active-pipe reference losses; no dynamic warm-up model",
)
for (id, color, label) in
    zip(ids, (:steelblue, :darkorange), ("Fixed topology", "Joint reconfiguration"))
    r=only(filter(x->x.method==id, summary))
    r.adopted_physical_pass || continue
    rows=sort(filter(x->x.method==id, traces); by = x->x.t)
    lines!(e, [x.t for x in rows], [x.P_grid_MW for x in rows]; color, label, linewidth = 2.5)
    lines!(h, [x.t for x in rows], [x.heat_loss_MW for x in rows]; color, label, linewidth = 2.5)
end
axislegend(e; position = :lt, labelsize = 14)
axislegend(h; position = :lt, labelsize = 14)
Label(
    fig2[4, 1:2],
    "Study: " *
    meta["study"] *
    " | Green: closed/open valve; gray: disconnected\n" *
    "Electrical switches are hourly; thermal valves are daily. Final topology is free. These are saved candidates.",
    fontsize = 13,
)
save(joinpath(out, "F40-topology-and-energy.png"), fig2)
save(joinpath(out, "F40-topology-and-energy.svg"), fig2)
for name in ("summary.csv", "topologies.csv", "trajectories.csv")
    cp(joinpath(report, name), joinpath(out, name))
end
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "figures"=>["F39", "F40"],
    "origin"=>"synthetic",
    "study"=>meta["study"],
    "study_manifest_sha256"=>meta["study_manifest_sha256"],
    "optimization_performed"=>false,
    "units"=>"CNY, MW, hour index, binary status; normalized A1 residual",
    "files"=>Dict(name=>hashfile(joinpath(out, name)) for name in readdir(out)),
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure.toml"), "w")
println("F39/F40 read saved candidates; no optimization.")
