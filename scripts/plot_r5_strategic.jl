using CairoMakie, CSV, TOML, SHA
length(ARGS)==1||error("参数：已生成的策略报告目录")
dir=abspath(only(ARGS))
any(ispath(joinpath(dir, f)) for f in ("F04.png", "F14.png", "F19.png", "figure-config.toml")) &&
    error("不覆盖策略图表")
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
tr=collect(CSV.File(joinpath(dir, "trajectories.csv")))
bids=collect(CSV.File(joinpath(dir, "bids-awards.csv")))
settle=collect(CSV.File(joinpath(dir, "settlement-range.csv")))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
set_theme!(Theme(font = "DejaVu Sans", fontsize = 16))
f=Figure(size = (1850, 1000))
Label(
    f[0, 1],
    "Synthetic continuous bidding | " *
    meta["batch_id"] *
    "\nSeparate market KKT, internal physics and finite-support risk; absent candidates are not zero residual",
    tellwidth = false,
)
ax=Axis(
    f[1, 1],
    ylabel = "Residual / tolerance",
    yscale = log10,
    xticks = (
        1:length(summary),
        [replace(s.record_id, "competitive_"=>"", "-"=>"\n") for s in summary],
    ),
    xticklabelrotation = pi/3,
    xticklabelsize = 11,
)
for (label, match, color) in (
    ("market KKT", "/selected_market/", :steelblue),
    ("internal physics", "/scenarios/", :darkorange),
    ("risk certificates", "/transport_checks/", :purple),
)
    values=[
        begin
            a=filter(x->x.record_id==s.record_id&&occursin(match, x.scope), res)
            isempty(a) ? NaN : max(1e-14, maximum(x.normalized for x in a))
        end for s in summary
    ]
    scatter!(ax, 1:length(summary), values; label, color, markersize = 11)
end
for (i, s) in enumerate(summary)
    isnan(s.total_cost_USD)&&text!(
        ax,
        i,
        2.0;
        text = "no candidate",
        rotation = pi/2,
        fontsize = 11,
    )
end
hlines!(ax, [1.0]; color = :black, linestyle = :dash)
ylims!(ax, 1e-15, max(100.0, 10maximum(x.normalized for x in res)))
axislegend(ax; position = :lt)
save(joinpath(dir, "F04.png"), f)

g=Figure(size = (1600, 1080))
Label(
    g[0, 1:2],
    "Synthetic strategic mechanism | " *
    meta["batch_id"] *
    "\nOptimistic lower-level selection; finite support; fixed bid is not a universal price-taker benchmark",
    tellwidth = false,
)
names=["merit_fixed_bid-sos1", "merit_strategic-sos1"]
rr=[only(filter(s->s.record_id==n, summary)) for n in names]
a=Axis(
    g[1, 1],
    title = "Private cost versus energy resource proxy",
    ylabel = "Synthetic USD",
    xticks = (1:2, ["bid fixed at 100", "continuous bid"]),
)
barplot!(
    a,
    [0.83, 1.83],
    [s.total_cost_USD for s in rr];
    width = 0.3,
    color = :steelblue,
    label = "IES net cost",
)
barplot!(
    a,
    [1.17, 2.17],
    [s.nominal_energy_resource_proxy_USD for s in rr];
    width = 0.3,
    color = :darkorange,
    label = "all generation resource proxy",
)
axislegend(a; position = :rt)
bb=[only(filter(s->s.record_id==n, bids)) for n in names]
b=Axis(
    g[1, 2],
    title = "Energy bid and selected settlement price",
    ylabel = "Synthetic USD/MWh",
    xticks = (1:2, ["fixed bid", "strategic"]),
)
barplot!(
    b,
    [0.83, 1.83],
    [s.energy_bid for s in bb];
    width = 0.3,
    color = :steelblue,
    label = "bid",
)
barplot!(
    b,
    [1.17, 2.17],
    [s.energy_price for s in bb];
    width = 0.3,
    color = :darkorange,
    label = "price",
)
axislegend(b; position = :rt)
c=Axis(
    g[2, 1],
    title = "Purchase reduction in the analytic step-supply case",
    ylabel = "MW",
    xticks = (1:2, ["fixed bid", "strategic"]),
)
barplot!(c, 1:2, [s.P_DA_MW for s in bb]; color = :steelblue)
hline=0.142
hlines!(c, [hline]; linestyle = :dash, color = :black, label = "frozen total electric requirement")
axislegend(c; position = :lb)
d=Axis(
    g[2, 2],
    title = "Same bids AND same awards: settlement interval",
    ylabel = "Synthetic USD",
    xticks = (1:2, ["hand_hour", "wide_line"]),
)
for (i, id) in enumerate(("hand_hour", "wide_line"))
    vals=[
        only(filter(s->s.record_id==id&&s.side==side, settle)).payment_USD for
        side in ("minimum", "maximum")
    ]
    lines!(d, [i, i], vals; color = :purple, linewidth = 5)
    scatter!(d, [i, i], vals; color = :purple, markersize = 12)
    text!(
        d,
        i+0.06,
        sum(vals)/2;
        text = string(round(vals[1]; digits = 2), " to ", round(vals[2]; digits = 2)),
        fontsize = 12,
    )
end
xlims!(d, 0.5, 2.8)
save(joinpath(dir, "F14.png"), g)

h=Figure(size = (1580, 1050))
record="competitive_future_e030_r005-sos1"
row=only(filter(s->s.record_id==record, summary))
Label(
    h[0, 1:2],
    "Saved four-period physical recourse | " *
    row.run_id *
    "\nSynthetic one-IES price model; fixed flow / linear electric network; no out-of-sample claim",
    tellwidth = false,
)
aa=Axis(h[1, 1], title = "Market awards", xlabel = "Period", ylabel = "MW")
ar=sort(filter(s->s.record_id==record, bids); by = x->x.t)
for (k, label) in ((:P_DA_MW, "purchase"), (:R_up_MW, "up reserve"), (:R_down_MW, "down reserve"))
    scatterlines!(aa, [x.t for x in ar], [getproperty(x, k) for x in ar]; label)
end
axislegend(aa; position = :rt)
ab=Axis(h[1, 2], title = "Indoor temperature", xlabel = "Period", ylabel = "K")
ac=Axis(h[2, 1], title = "Delivered heat", xlabel = "Period", ylabel = "MW")
ad=Axis(
    h[2, 2],
    title = "Reserve request and delivered adjustment",
    xlabel = "Period",
    ylabel = "MW",
)
sc=sort(unique(x.scenario for x in tr if x.record_id==record))
for (i, sid) in enumerate(sc)
    data=sort(filter(x->x.record_id==record&&x.scenario==sid, tr); by = x->x.t)
    scatterlines!(ab, [x.t for x in data], [x.room_K for x in data]; label = sid)
    scatterlines!(ac, [x.t for x in data], [x.heat_MW for x in data]; label = sid)
    lines!(
        ad,
        [x.t for x in data],
        [x.requested_MW for x in data];
        label = sid*" request",
        linestyle = :dash,
    )
    scatter!(
        ad,
        [x.t for x in data],
        [x.delivered_MW for x in data];
        label = sid*" actual",
        markersize = 10,
    )
end
axislegend(ab; position = :rt)
axislegend(ac; position = :rt)
axislegend(ad; position = :rt, labelsize = 12)
save(joinpath(dir, "F19.png"), h)
files=(
    "comparison.csv",
    "residuals.csv",
    "bids-awards.csv",
    "risk-scenarios.csv",
    "trajectories.csv",
    "settlement-range.csv",
)
fig=Dict(
    "schema"=>"r5-strategic-figures-v1",
    "origin"=>"synthetic",
    "batch_id"=>meta["batch_id"],
    "solver_reexecuted"=>false,
    "run_ids"=>[s.run_id for s in summary],
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "units"=>"MW, K, synthetic USD, USD/MWh; residuals normalized by original A1/KKT tolerance",
)
write(joinpath(dir, "figure-config.toml"), sprint(io->TOML.print(io, fig; sorted = true)))
println("F04/F14/F19 redrawn from saved data.")
