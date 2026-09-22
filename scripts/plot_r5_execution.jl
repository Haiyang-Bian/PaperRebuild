using CairoMakie, CSV, TOML, SHA
length(ARGS)==1 || error("参数：已保存执行报告目录")
dir=abspath(only(ARGS))
any(ispath(joinpath(dir, f)) for f in ("F04.png", "F14.png", "F19.png", "figure-config.toml")) &&
    error("不覆盖执行图表")
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
awards=collect(CSV.File(joinpath(dir, "awards.csv")))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
set_theme!(Theme(font = "DejaVu Sans", fontsize = 16))
f=Figure(size = (1850, 1050))
Label(
    f[0, 1],
    "Synthetic execution and conditional delivery | " *
    meta["batch_id"] *
    "\nNo strategic reoptimization; uncertified or absent candidates retain their status",
    tellwidth = false,
)
ax=Axis(
    f[1, 1],
    ylabel = "Residual / unchanged tolerance",
    yscale = log10,
    xticks = (
        1:length(rows),
        [
            replace(
                r.record_id,
                "competitive_"=>"",
                "minimum_norm"=>"minnorm",
                "saved_"=>"",
                "-"=>"\n",
            ) for r in rows
        ],
    ),
    xticklabelrotation = pi/3,
    xticklabelsize = 10,
)
for (label, match, color) in (
    ("selection KKT", "/selection/", :steelblue),
    ("internal recourse", "/delivery/risk/", :darkorange),
    ("award equality", "fixed_awards", :purple),
)
    y=[
        begin
            a=filter(x->x.record_id==r.record_id&&occursin(match, x.scope), res)
            isempty(a) ? NaN : max(1e-14, maximum(x.normalized for x in a))
        end for r in rows
    ]
    scatter!(ax, 1:length(rows), y; label, color, markersize = 10)
end
for (i, r) in enumerate(rows)
    if !r.selection_pass || (!r.delivery_pass && r.delivery_status!="not_applicable")
        text!(
            ax,
            i,
            5.0;
            text = (!r.selection_pass ? "uncertified selection" : r.delivery_status),
            fontsize = 10,
            rotation = pi/2,
        )
    end
end
hlines!(ax, [1.0]; color = :black, linestyle = :dash)
ylims!(ax, 1e-15, max(1e3, maximum(x.normalized for x in res)*10))
axislegend(ax; position = :lt)
save(joinpath(dir, "F04.png"), f)

cases=[
    "competitive_hard_zero",
    "competitive_quarter",
    "competitive_thermal_e030_r005",
    "competitive_future_e030_r005",
    "merit_strategic",
    "merit_fixed_bid",
]
modes=["saved_selected", "saved_independent", "minimum_norm"]
labels=["old optimistic awards", "independent LP awards", "explicit min-norm awards"]
colors=[:steelblue, :darkorange, :purple]
g=Figure(size = (1550, 1180))
Label(
    g[0, 1:2],
    "Same prior bids, different executed awards | " *
    meta["batch_id"] *
    "\nSynthetic USD; conditional recourse cost is not a new strategic optimum",
    tellwidth = false,
)
for (i, c) in enumerate(cases)
    ax=Axis(
        g[(i+1)÷2, mod1(i, 2)],
        title = replace(c, "competitive_"=>""),
        ylabel = "Total IES cost (USD)",
        xticks = (1:3, ["old selected", "independent", "min-norm"]),
    )
    data=[only(filter(x->x.case==c&&x.mode==mode, rows)) for mode in modes]
    vals=[x.delivery_pass ? x.total_cost_USD : NaN for x in data]
    barplot!(ax, 1:3, vals; color = colors)
    for j in 1:3
        if isnan(vals[j])
            text!(
                ax,
                j,
                0.0;
                text = data[j].selection_pass ? "delivery failed" : "selection unverified",
                rotation = pi/2,
                fontsize = 11,
            )
        else
            text!(
                ax,
                j,
                vals[j];
                text = string(round(vals[j]; digits = 4)),
                align = (:center, :bottom),
                fontsize = 11,
            )
        end
    end
    ylims!(
        ax,
        min(-1.0, minimum(filter(isfinite, vals); init = 0.0)*1.25),
        max(3.0, maximum(filter(isfinite, vals); init = 0.0)*1.35),
    )
end
save(joinpath(dir, "F14.png"), g)

h=Figure(size = (1600, 1050))
Label(
    h[0, 1:2],
    "Market-selected commitments before internal delivery | " *
    meta["batch_id"] *
    "\nMW; market-optimal quantities need not be deliverable by the IES",
    tellwidth = false,
)
for (i, case) in enumerate(("merit_strategic", "merit_fixed_bid"))
    ax=Axis(
        h[1, i],
        title = replace(case, "_"=>" "),
        ylabel = "Purchase (MW)",
        xticks = (1:3, labels),
        xticklabelrotation = pi/9,
        xticklabelsize = 12,
    )
    vals=[
        begin
            a=filter(x->x.record_id==case*"-"*mode, awards)
            isempty(a) ? NaN : only(a).P_DA_MW
        end for mode in modes
    ]
    barplot!(ax, 1:3, vals; color = colors)
    hlines!(ax, [0.142]; color = :black, linestyle = :dash, label = "frozen net electric need")
    axislegend(ax; position = :rt)
end
for (i, key) in enumerate((:P_DA_MW, :R_down_MW))
    ax=Axis(
        h[2, i],
        title = i==1 ? "Four-period purchase" : "Four-period down reserve",
        xlabel = "Period",
        ylabel = "MW",
    )
    for (j, mode) in enumerate(modes)
        data=sort(filter(x->x.record_id=="competitive_future_e030_r005-"*mode, awards); by = x->x.t)
        isempty(data) && continue
        scatterlines!(
            ax,
            [x.t for x in data],
            [getproperty(x, key) for x in data];
            label = labels[j],
            color = colors[j],
        )
    end
    axislegend(ax; position = :rt, labelsize = 12)
end
save(joinpath(dir, "F19.png"), h)
files=("comparison.csv", "residuals.csv", "awards.csv", "trajectories.csv")
config=Dict(
    "schema"=>"r5-execution-figures-v1",
    "origin"=>"synthetic",
    "batch_id"=>meta["batch_id"],
    "solver_reexecuted"=>false,
    "run_ids"=>[r.run_id for r in rows],
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "units"=>"MW, K, synthetic USD, USD/MWh; unchanged normalized A1/KKT residuals",
)
write(joinpath(dir, "figure-config.toml"), sprint(io->TOML.print(io, config; sorted = true)))
println("F04/F14/F19 rendered solely from saved data.")
