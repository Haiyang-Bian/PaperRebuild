using CairoMakie, CSV, TOML, SHA
length(ARGS)==1||error("参数：已有风险报告目录")
dir=abspath(only(ARGS))
any(ispath(joinpath(dir, f)) for f in ("F04.png", "F15.png", "F19.png", "figure-config.toml"))&&error(
    "不覆盖风险图表",
)
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
com=collect(CSV.File(joinpath(dir, "commitments.csv")))
sc=collect(CSV.File(joinpath(dir, "scenarios.csv")))
tr=collect(CSV.File(joinpath(dir, "trajectories.csv")))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
set_theme!(Theme(font = "DejaVu Sans", fontsize = 16))
f=Figure(size = (1800, 900))
Label(
    f[0, 1],
    "Synthetic finite-support risk dispatch | "*meta["batch_id"]*"\nNumerical model and independent transport certificates; no candidate is not zero residual",
    tellwidth = false,
)
ax=Axis(
    f[1, 1],
    ylabel = "Residual / tolerance",
    yscale = log10,
    xticks = (1:length(summary), [replace(s.record_id, "--"=>"\n") for s in summary]),
    xticklabelrotation = pi/3,
    xticklabelsize = 10,
)
for (label, prefix, color) in (
    ("physical", "physical/", :steelblue),
    ("joint model", "joint/", :darkorange),
    ("transport certificates", "oracle_", :purple),
)
    vals=[
        begin
            rows=filter(r->r.record_id==s.record_id&&startswith(r.group, prefix), res)
            isempty(rows) ? NaN : max(1e-14, maximum(r.normalized for r in rows))
        end for s in summary
    ]
    scatter!(ax, 1:length(summary), vals; label, color, markersize = 10)
end
for (i, s) in enumerate(summary)
    isnan(s.objective)&&text!(ax, i, 2.0; text = "no candidate", rotation = pi/2, fontsize = 10)
end
hlines!(ax, [1.0]; linestyle = :dash, color = :black)
ylims!(ax, 1e-15, max(100, 10maximum(x.normalized for x in res)))
axislegend(ax; position = :lt)
save(joinpath(dir, "F04.png"), f)

g=Figure(size = (1560, 1060))
Label(
    g[0, 1:2],
    "Fixed-price synthetic DRO / joint comfort risk | "*meta["batch_id"]*"\nFinite support; nominal weights and physical boundaries frozen; no out-of-sample guarantee",
    tellwidth = false,
)
names=["hard_zero", "hard_r020", "hard_r100"]
rows=[only(filter(s->s.record_id==name*"--highs", summary)) for name in names]
a=Axis(
    g[1, 1],
    title = "Hard comfort: cost under probability ambiguity",
    xlabel = "Normalized transport radius",
    ylabel = "Worst net cost (synthetic USD)",
)
scatterlines!(
    a,
    [r.radius for r in rows],
    [r.objective for r in rows];
    color = :steelblue,
    markersize = 12,
)
b=Axis(
    g[1, 2],
    title = "Hard comfort: common commitments",
    xlabel = "Normalized transport radius",
    ylabel = "Power (MW)",
)
for (key, color) in ((:P_DA_MW, :steelblue), (:R_up_MW, :darkorange), (:R_down_MW, :purple))
    vals=[getproperty(only(filter(s->s.record_id==name*"--highs", com)), key) for name in names]
    scatterlines!(b, [r.radius for r in rows], vals; label = string(key), color)
end
axislegend(b; position = :rb)
names2=["thermal_hard", "thermal_e025_r000", "thermal_e025_r005", "thermal_e030_r005"]
rows2=[only(filter(s->s.record_id==name*"--highs", summary)) for name in names2]
c=Axis(
    g[2, 1],
    title = "Thermal case: declared epsilon / radius controls",
    ylabel = "Net cost (synthetic USD)",
    xticks = (1:4, ["eps=0\nrho=0", "eps=.25\nrho=0", "eps=.25\nrho=.05", "eps=.30\nrho=.05"]),
)
barplot!(c, 1:4, [r.objective for r in rows2]; color = [:gray, :steelblue, :orange, :purple])
d=Axis(
    g[2, 2],
    title = "Cost and risk have different worst weights",
    ylabel = "Probability",
    xticks = (1:3, ["no call", "up call", "down call"]),
)
group=[
    only(filter(r->r.record_id=="thermal_e030_r005--highs"&&r.scenario==sid, sc)) for
    sid in ("none", "up", "down")
]
for (i, key, color) in (
    (1, :probability, :gray),
    (2, :cost_worst_probability, :steelblue),
    (3, :risk_worst_probability, :orange),
)
    barplot!(
        d,
        (1:3) .+ (i-2)*0.24,
        [getproperty(r, key) for r in group];
        width = 0.22,
        label = string(key),
        color,
    )
end
axislegend(d; position = :rt, labelsize = 12)
save(joinpath(dir, "F15.png"), g)

h=Figure(size = (1520, 980))
Label(
    h[0, 1:2],
    "Synthetic comfort and delivery | "*meta["batch_id"]*"\nThermal hand case has a free terminal room state; four-period case restores room temperature only",
    tellwidth = false,
)
a=Axis(
    h[1, 1],
    title = "One-hour thermal case: actual room temperature",
    ylabel = "Temperature (K)",
    xticks = (1:3, ["no call", "up call", "down call"]),
)
for (i, name, color) in (
    (1, "thermal_hard", :gray),
    (2, "thermal_e025_r000", :steelblue),
    (3, "thermal_e025_r005", :orange),
    (4, "thermal_e030_r005", :purple),
)
    vals=[
        only(filter(r->r.record_id==name*"--highs"&&r.scenario==sid, tr)).room_K for
        sid in ("none", "up", "down")
    ]
    scatter!(a, (1:3) .+ (i-2.5)*0.12, vals; label = name, color, markersize = 12)
end
hlines!(a, [293.15]; color = :black, linestyle = :dash)
axislegend(a; position = :lt, labelsize = 11)
b=Axis(
    h[1, 2],
    title = "Worst joint violation: actual policy and limit",
    ylabel = "Probability",
    xticks = (1:4, ["hard", "eps=.25\nrho=0", "eps=.25\nrho=.05", "eps=.30\nrho=.05"]),
)
barplot!(b, 1:4, [r.actual_risk for r in rows2]; color = :steelblue, label = "actual joint event")
scatter!(
    b,
    1:4,
    [r.epsilon for r in rows2];
    color = :red,
    marker = :hline,
    markersize = 25,
    label = "risk limit",
)
axislegend(b; position = :lt)
c=Axis(
    h[2, 1],
    title = "Four-period policy: building temperature",
    xlabel = "Time (h)",
    ylabel = "Temperature (K)",
)
d=Axis(
    h[2, 2],
    title = "Four-period policy: requested / delivered reserve",
    xlabel = "Time (h)",
    ylabel = "Power (MW)",
)
for (sid, color) in (("none", :gray), ("up", :darkorange), ("down", :purple))
    rr=sort(filter(r->r.record_id=="future_e030_r005--highs"&&r.scenario==sid, tr); by = r->r.t)
    isempty(rr)&&continue
    tt=[r.t*r.dt_h for r in rr]
    scatterlines!(c, tt, [r.room_K for r in rr]; color, label = sid)
    lines!(d, tt, [r.request_MW for r in rr]; color, linestyle = :dash, label = sid*" request")
    scatter!(d, tt, [r.delivered_MW for r in rr]; color, markersize = 9, label = sid*" delivered")
end
hlines!(c, [292.15, 294.15]; color = :black, linestyle = :dash)
axislegend(c; position = :rb);
axislegend(d; position = :rb, labelsize = 11)
save(joinpath(dir, "F19.png"), h)
sources=Dict(
    file=>bytes2hex(sha256(read(joinpath(dir, file)))) for file in (
        "comparison.csv",
        "residuals.csv",
        "commitments.csv",
        "scenarios.csv",
        "trajectories.csv",
        "report.toml",
    )
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r5-risk-figures-v1",
            "origin"=>"synthetic",
            "batch_id"=>meta["batch_id"],
            "solver_reexecuted"=>false,
            "run_ids"=>[r.run_id for r in summary],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "sources"=>sources,
            "figures"=>["F04.png", "F15.png", "F19.png"],
        );
        sorted = true,
    )
end
println("F04/F15/F19 rendered from saved risk evidence; no optimization.")
