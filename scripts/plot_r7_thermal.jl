using CSV, CairoMakie, TOML, SHA
length(ARGS)==2 || error("usage: plot_r7_thermal.jl FROZEN_REPORT NEW_DIR")
src, out=abspath.(ARGS)
ispath(out)&&error("不覆盖已有热图件")
sources=(
    "summary.csv",
    "trajectory.csv",
    "profiles.csv",
    "port-audit.csv",
    "solver-comparison.csv",
    "rule.toml",
)
registry=TOML.parsefile(joinpath(src, "files.toml"))["files"]
for p in sources
    bytes2hex(sha256(read(joinpath(src, p))))==registry[p] || error("图源哈希改变")
end
summary=collect(CSV.File(joinpath(src, "summary.csv")))
profiles=collect(CSV.File(joinpath(src, "profiles.csv")))
trajectory=collect(CSV.File(joinpath(src, "trajectory.csv")))
ports=collect(CSV.File(joinpath(src, "port-audit.csv")))
fig=Figure(size = (1360, 1000), fontsize = 17)
Label(
    fig[0, :],
    "F23 | Stored heat is not always deliverable heat (synthetic)",
    fontsize = 25,
    tellwidth = false,
)
colors=(:firebrick, :steelblue)
groups=("hot_outlet", "cold_outlet")
labels=("Hot water near outlet", "Cold water near outlet")
a=Axis(
    fig[1, 1],
    title = "A  Equal inventory; different spatial states",
    xlabel = "Supply-pipe mass coordinate (kg)",
    ylabel = "Initial temperature (K)",
)
for (group, color, label) in zip(groups, colors, labels)
    ps=filter(p->p.group==group&&p.side=="S", profiles)
    xs=Float64[]
    ys=Float64[]
    for p in ps
        append!(xs, [p.mass_start_kg, p.mass_end_kg])
        append!(ys, [p.temperature_K, p.temperature_K])
    end
    lines!(a, xs, ys; color, linewidth = 4, label)
end
hlines!(a, [343.15], color = :gray, linestyle = :dot, linewidth = 2, label = "Both mean = 343.15 K")
ylims!(a, 328, 363);
axislegend(a, position = :ct, labelsize = 13)
b=Axis(
    fig[1, 2],
    title = "B  Heat delivered in the first 0.25 h",
    xticks = ([1, 2], ["Hot outlet", "Cold outlet"]),
    ylabel = "Delivered energy (MWh)",
)
delivered=Float64[]
for group in groups
    row=only(filter(r->r.record==group*"_n16_curtail_heat", summary))
    row.thermal_pass || error("图示候选未通过")
    push!(delivered, (8/15)*0.25-row.heat_unserved_MWh)
end
barplot!(b, 1:2, delivered, color = collect(colors), width = 0.5)
hlines!(b, [(8/15)*0.25], color = :gray, linestyle = :dash, label = "Planned demand")
ylims!(b, 0, 0.175);
axislegend(b, position = :lt, labelsize = 13)
for i in 1:2
    text!(
        b,
        i,
        delivered[i]+0.004,
        text = string(round(delivered[i]; digits = 4)),
        align = (:center, :bottom),
        fontsize = 15,
    )
end
c=Axis(
    fig[2, 1],
    title = "C  Detailed transport, 16 substeps",
    xlabel = "Elapsed time (h)",
    ylabel = "Mean supply outlet (K)",
)
for (group, color, label) in zip(groups, colors, labels)
    rr=filter(r->r.record==group*"_n16_curtail_heat"&&r.side=="S"&&r.time_h>0, trajectory)
    scatterlines!(
        c,
        [r.time_h for r in rr],
        [r.outlet_mean_K for r in rr];
        color,
        linewidth = 3,
        markersize = 6,
        label,
    )
end
ylims!(c, 328, 358);
axislegend(c, position = :rc, labelsize = 13)
d=Axis(
    fig[2, 2],
    title = "D  Fixed source control violates a necessary bound",
    xticks = (1:3, ["Old hand case", "Reserve event 1", "Reserve event 2"]),
    ylabel = "Source heating power (MW)",
)
names=("recovery-hand", "nested_witness_1", "nested_witness_2")
planned=Float64[];
required=Float64[]
for name in names
    rr=filter(r->r.group==name&&r.node==1&&r.time==1, ports)
    push!(planned, first(rr).source_MW)
    push!(required, first(rr).source_min_MW)
end
barplot!(d, (1:3) .- 0.17, planned, width = 0.3, color = :gray, label = "Original source power")
barplot!(
    d,
    (1:3) .+ 0.17,
    required,
    width = 0.3,
    color = :darkorange,
    label = "Minimum compatible power",
)
ylims!(d, 0, 0.09);
axislegend(d, position = :lt, labelsize = 13)
for i in 1:3
    scatter!(d, [i-0.17], [planned[i]], color = :black, markersize = 7)
end
colsize!(fig.layout, 1, Relative(0.5));
colsize!(fig.layout, 2, Relative(0.5))
Label(
    fig[3, :],
    "Same flows and device outputs retained. Conditional heat reconstruction; no hydraulic or AC certificate.\n1 / 4 / 16 substeps agree in these cases. Run IDs and raw values accompany the figure.",
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
save(joinpath(out, "F23-thermal-delivery.png"), fig; px_per_unit = 1.5)
save(joinpath(out, "F23-thermal-delivery.svg"), fig)
for p in sources
    cp(joinpath(src, p), joinpath(out, p))
end
files=Dict(
    p=>bytes2hex(sha256(read(joinpath(out, p)))) for
    p in vcat(collect(sources), ["F23-thermal-delivery.png", "F23-thermal-delivery.svg"])
)
metadata=Dict(
    "schema"=>"r7-thermal-figure-v1",
    "origin"=>"synthetic",
    "run_ids"=>[r.run_id for r in summary],
    "source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "files"=>files,
    "solver_called"=>false,
    "units"=>["K", "kg", "MW", "MWh", "h"],
    "size_px"=>[2040, 1500],
)
write(joinpath(out, "figure.toml"), sprint(io->TOML.print(io, metadata; sorted = true)))
println("F23 drawn only from frozen values.")
