using CairoMakie, CSV, TOML, SHA
length(ARGS)==1||error("参数：已有共同承诺报告目录")
dir=abspath(only(ARGS))
any(ispath(joinpath(dir, f)) for f in ("F04.png", "F19.png", "figure-config.toml"))&&error(
    "不覆盖共同承诺图表",
)
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
com=collect(CSV.File(joinpath(dir, "commitments.csv")))
traj=collect(CSV.File(joinpath(dir, "trajectories.csv")))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
set_theme!(Theme(font = "DejaVu Sans", fontsize = 16))
f=Figure(size = (1640, 880))
Label(
    f[0, 1],
    "Synthetic shared day-ahead commitments | "*meta["batch_id"]*"\nA1 / numerical KKT checks; no candidate is not zero residual",
    tellwidth = false,
)
ax=Axis(
    f[1, 1],
    ylabel = "Residual / tolerance",
    yscale = log10,
    xticks = (1:length(summary), [replace(z.record_id, "--"=>"\n") for z in summary]),
    xticklabelrotation = pi/3,
    xticklabelsize = 10,
)
for (label, groups, color, marker) in (
    (
        "physical / cost",
        ("first_stage", "electric", "heat", "comfort", "delivery", "auxiliary", "cost"),
        :steelblue,
        :circle,
    ),
    (
        "conditional KKT",
        (
            "conditional_sign",
            "conditional_complementarity",
            "conditional_stationarity",
            "conditional_objective",
            "conditional_gap",
        ),
        :purple,
        :rect,
    ),
    ("shared KKT", ("kkt",), :darkorange, :diamond),
)
    y=[
        begin
            rows=filter(z->z.record_id==s.record_id&&z.group in groups, res)
            isempty(rows) ? NaN : max(1e-14, maximum(z.normalized for z in rows))
        end for s in summary
    ]
    scatter!(ax, 1:length(summary), y; label, color, marker, markersize = 10)
end
for (i, s) in enumerate(summary)
    isnan(s.objective)&&text!(ax, i, 2.0; text = "no candidate", rotation = pi/2, fontsize = 10)
end
hlines!(ax, [1.0]; color = :black, linestyle = :dash)
ylims!(ax, 1e-15, max(100, 10maximum(z.normalized for z in res)))
axislegend(ax; position = :lt)
save(joinpath(dir, "F04.png"), f)
g=Figure(size = (1600, 1020))
Label(
    g[0, 1:2],
    "Synthetic fixed-price expected-cost benchmark | "*meta["batch_id"]*"\nShared quantities are chosen before the scenario; real-time schedules see its full trajectory",
    tellwidth = false,
)
names=["hand", "no_reserve", "no_call_only", "capacity_denominator"]
ax1=Axis(
    g[1, 1],
    title = "One-hour shared commitments (HiGHS)",
    ylabel = "Power (MW)",
    xticks = (1:4, ["all calls", "no reserve", "no-call only", "capacity budget"]),
)
for (i, key, color) in
    ((1, :P_DA_MW, :steelblue), (2, :R_up_MW, :darkorange), (3, :R_down_MW, :purple))
    vals=[getproperty(only(filter(z->z.record_id==name*"--highs", com)), key) for name in names]
    barplot!(ax1, (1:4) .+ (i-2)*0.23, vals; width = 0.21, label = string(key), color)
end
axislegend(ax1; position = :rt)
ax2=Axis(
    g[1, 2],
    title = "One-hour actual requested and delivered reserve",
    ylabel = "Power (MW); up positive",
    xticks = (1:3, ["no call", "up call", "down call"]),
)
rows=[
    only(filter(z->z.record_id=="hand--highs"&&z.scenario==s, traj)) for s in ("none", "up", "down")
]
barplot!(
    ax2,
    (1:3) .- 0.13,
    [z.request_MW for z in rows];
    width = 0.24,
    label = "requested",
    color = :steelblue,
)
barplot!(
    ax2,
    (1:3) .+ 0.13,
    [z.delivered_MW for z in rows];
    width = 0.24,
    label = "delivered",
    color = :darkorange,
)
axislegend(ax2; position = :rt)
ax3=Axis(
    g[2, 1],
    title = "Four-period actual import (HiGHS)",
    xlabel = "Period (1 h)",
    ylabel = "Power (MW)",
)
ax4=Axis(
    g[2, 2],
    title = "Four-period building temperature (HiGHS)",
    xlabel = "Period (1 h)",
    ylabel = "Temperature (K)",
)
for (sid, color) in (("none", :steelblue), ("up", :darkorange), ("down", :purple))
    rs=sort(filter(z->z.record_id=="four_period--highs"&&z.scenario==sid, traj); by = z->z.t)
    scatterlines!(ax3, [z.t for z in rs], [z.P_actual_MW for z in rs]; label = sid, color)
    scatterlines!(ax4, [z.t for z in rs], [z.building_1_K for z in rs]; label = sid, color)
end
axislegend(ax3; position = :rt)
axislegend(ax4; position = :rt)
save(joinpath(dir, "F19.png"), g)
fig=Dict(
    "schema"=>"r5-commitment-figures-v1",
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "run_ids"=>[z.run_id for z in summary],
    "sources"=>Dict(
        file=>bytes2hex(sha256(read(joinpath(dir, file)))) for file in
        ("comparison.csv", "residuals.csv", "commitments.csv", "trajectories.csv", "report.toml")
    ),
)
write(joinpath(dir, "figure-config.toml"), sprint(io->TOML.print(io, fig; sorted = true)))
println("Shared commitment F04/F19 written from saved values; no optimization.")
