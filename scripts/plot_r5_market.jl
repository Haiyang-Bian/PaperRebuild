using CairoMakie, CSV, TOML, SHA
length(ARGS)==1 || error("参数：已有市场CSV的新绘图目录")
dir=only(ARGS)
outputs=["F04.png", "F14.png", "figure-config.toml"]
any(ispath(joinpath(dir, f)) for f in outputs) && error("不覆盖旧市场图")
meta=TOML.parsefile(joinpath(dir, "report.toml"))
files=["comparison.csv", "residuals.csv", "prices.csv", "dispatch.csv", "objective-components.csv"]
summary, residuals, prices, dispatch, components=(
    collect(CSV.File(joinpath(dir, f))) for f in files
)
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
banner="Synthetic fixed-bid market | "*meta["batch_id"]
labels=[replace(x.record_id, "--"=>"\n") for x in summary]
fig=Figure(size = (1600, 900))
Label(
    fig[0, 1],
    banner*"\nIndependent residuals / unchanged tolerance; no candidate = not tested",
    tellwidth = false,
)
ax=Axis(
    fig[1, 1],
    ylabel = "Residual / tolerance",
    xticks = (1:length(summary), labels),
    xticklabelrotation = pi/3,
    xticklabelsize = 11,
    yscale = log10,
)
for (scope, color, marker) in (
    ("primal", :steelblue, :circle),
    ("dual", :darkorange, :rect),
    ("cost", :darkgreen, :utriangle),
)
    values=[
        begin
            rows=filter(z->z.record_id==r.record_id&&z.scope==scope, residuals)
            isempty(rows) ? NaN : max(1e-12, maximum(z.normalized for z in rows))
        end for r in summary
    ]
    scatter!(ax, 1:length(summary), values; color, marker, markersize = 12, label = scope)
end
hlines!(ax, [1.0]; color = :black, linestyle = :dash)
for (i, r) in enumerate(summary)
    r.candidate && continue
    text!(
        ax,
        i,
        2.0;
        text = "no candidate",
        rotation = pi/2,
        align = (:left, :center),
        fontsize = 10,
    )
end
ylims!(ax, 1e-13, max(100.0, 10maximum((z.normalized for z in residuals); init = 1.0)))
xlims!(ax, 0.25, length(summary)+0.75)
axislegend(ax; position = :lt)
save(joinpath(dir, "F04.png"), fig)

# 在求解前已声明展示two_bus--highs及ramp_memory--highs，不挑选最有利求解器。
base="two_bus--highs"
ramp="ramp_memory--highs"
fig=Figure(size = (1560, 1100))
Label(
    fig[0, 1:3],
    banner*"\nEnergy / reserve clearing and bid objective; not IES operating profit or risk dispatch",
    tellwidth = false,
)
energy=Axis(fig[1, 1], title = "Two-bus energy", xlabel = "Period", ylabel = "MW", xticks = 1:4)
lmp=Axis(
    fig[1, 2],
    title = "Energy marginal prices",
    xlabel = "Period",
    ylabel = "Synthetic USD/MWh",
    xticks = 1:4,
)
reserve=Axis(
    fig[1, 3],
    title = "Reserve awards",
    xlabel = "Period",
    ylabel = "MW capacity",
    xticks = 1:4,
)
reserveprice=Axis(
    fig[2, 1],
    title = "Reserve capacity prices",
    xlabel = "Period",
    ylabel = "Synthetic USD/(MW*h)",
    xticks = 1:4,
)
objective=Axis(
    fig[2, 2],
    title = "Bid-objective components",
    ylabel = "Synthetic USD",
    xticks = (1:6, ["G energy", "G up", "G down", "IES utility", "IES up", "IES down"]),
    xticklabelrotation = pi/4,
    xticklabelsize = 11,
)
ramplmp=Axis(
    fig[2, 3],
    title = "Analytic ramp-memory case",
    xlabel = "Period",
    ylabel = "Synthetic USD/MWh",
    xticks = 1:2,
)
base_summary=only(filter(x->x.record_id==base, summary))
if base_summary.candidate
    for (kind, actor, color) in (
        ("generators", "G1", :steelblue),
        ("generators", "G2", :darkorange),
        ("ies", "IES1", :darkgreen),
    )
        rr=sort(filter(x->x.record_id==base&&x.kind==kind&&x.actor==actor, dispatch); by = x->x.t)
        isempty(rr) && continue
        scatterlines!(
            energy,
            [x.t for x in rr],
            [x.P_MW for x in rr];
            color,
            label = actor*(kind=="ies" ? " purchase" : ""),
        )
        scatterlines!(reserve, [x.t for x in rr], [x.up_MW for x in rr]; color, label = actor*" up")
        lines!(
            reserve,
            [x.t for x in rr],
            [x.down_MW for x in rr];
            color,
            linestyle = :dash,
            label = actor*" down",
        )
    end
    rr=filter(x->x.record_id==base, components)
    order=[
        "generators_energy",
        "generators_up",
        "generators_down",
        "ies_energy",
        "ies_up",
        "ies_down",
    ]
    values=[only(filter(x->x.component==key, rr)).amount_USD for key in order]
    barplot!(
        objective,
        1:6,
        values;
        color = [:steelblue, :steelblue, :steelblue, :darkgreen, :darkgreen, :darkgreen],
    )
    hlines!(objective, [0.0]; color = :black)
    axislegend(energy; position = :lt, labelsize = 10)
    axislegend(reserve; position = :rt, labelsize = 9)
else
    Label(fig[1, 1], "No base candidate; see saved status", tellwidth = false)
end
if base_summary.kkt_pass
    for (node, color) in ((1, :steelblue), (2, :darkorange))
        rr=sort(filter(x->x.record_id==base&&x.node==node, prices); by = x->x.t)
        scatterlines!(
            lmp,
            [x.t for x in rr],
            [x.LMP_USD_MWh for x in rr];
            color,
            label = "node $node",
        )
    end
    rr=sort(filter(x->x.record_id==base&&x.node==1, prices); by = x->x.t)
    scatterlines!(
        reserveprice,
        [x.t for x in rr],
        [x.up_price_USD_MW_h for x in rr];
        color = :steelblue,
        label = "up",
    )
    scatterlines!(
        reserveprice,
        [x.t for x in rr],
        [x.down_price_USD_MW_h for x in rr];
        color = :darkorange,
        label = "down",
    )
    axislegend(lmp; position = :lt, labelsize = 11)
    axislegend(reserveprice; position = :rt, labelsize = 11)
else
    Label(fig[1, 2], "Prices lack verified KKT", tellwidth = false)
end
if only(filter(x->x.record_id==ramp, summary)).kkt_pass
    rr=sort(filter(x->x.record_id==ramp, prices); by = x->x.t)
    scatterlines!(
        ramplmp,
        [x.t for x in rr],
        [x.LMP_USD_MWh for x in rr];
        color = :purple,
        markersize = 12,
    )
    hlines!(ramplmp, [0.0]; color = :black, linestyle = :dash)
else
    Label(fig[2, 3], "Ramp prices lack verified KKT", tellwidth = false)
end
save(joinpath(dir, "F14.png"), fig)
config=Dict(
    "batch_id"=>meta["batch_id"],
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "fixed_display_records"=>[base, ramp],
    "source_run_ids"=>[String(x.run_id) for x in summary],
    "scope"=>"F14 first part: fixed bids and reserve capacity awards; no realized reserve delivery, physical recourse or IES profit.",
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("Saved F04 and first-part F14 using existing market evidence only.")
