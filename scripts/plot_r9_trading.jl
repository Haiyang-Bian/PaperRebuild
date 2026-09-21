# F38仅使用已封存表，不求解、不改写原运行；不能把容量上界画成可实施调度。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_trading.jl SUMMARY NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("Do not overwrite figures")
hashfile(p) = bytes2hex(sha256(read(p)))
meta=TOML.parsefile(joinpath(report, "evidence.toml"))
for (rel, h) in meta["derived_files"]
    hashfile(joinpath(report, rel))==h || error("Figure input changed")
end
rows=collect(CSV.File(joinpath(report, "heat-cut.csv")))
fig=Figure(size = (1240, 830), fontsize = 19)
Label(
    fig[0, 1],
    "F38 | Synthetic 44/38-node trading input | Necessary capacity bounds",
    fontsize = 24,
)
a=Axis(fig[1, 1], title = "Heat nodes A = all except {5, 6, 23}", ylabel = "Thermal power (MW)")
t=[x.t for x in rows]
required=[x.minimum_demand_MW+x.internal_loss_MW for x in rows]
available=[x.maximum_supply_MW+x.maximum_import_MW for x in rows]
lines!(
    a,
    t,
    required;
    color = :darkorange,
    linewidth = 3,
    label = "Minimum demand + internal pipe losses",
)
lines!(
    a,
    t,
    available;
    color = :royalblue,
    linewidth = 3,
    label = "Maximum local supply + boundary import",
)
scatter!(a, [8], [required[8]]; color = :red, markersize = 12)
axislegend(a; position = :lb, labelsize = 16)
b=Axis(
    fig[2, 1],
    title = "Positive deficit proves these bounds are inconsistent",
    xlabel = "Hour index (1 h periods)",
    ylabel = "Required minus available (MW)",
)
values=[x.deficit_MW for x in rows]
barplot!(b, t, values; color = [v>0 ? :firebrick : :steelblue for v in values])
hlines!(b, [0.0]; color = :black, linestyle = :dash)
Label(
    fig[3, 1],
    "Hour 8 deficit = " *
    string(round(values[8]; digits = 9)) *
    " MW; lower rows are necessary bounds, not feasible schedules.",
    fontsize = 17,
)
Label(
    fig[4, 1],
    "Study: r9-trading-20260921-v2 | 4 methods infeasible | No coordination-benefit claim\n" *
    "Input SHA256: " *
    meta["input_sha256"],
    fontsize = 13,
)
mkpath(out)
save(joinpath(out, "F38-capacity.png"), fig)
save(joinpath(out, "F38-capacity.svg"), fig)
cp(joinpath(report, "heat-cut.csv"), joinpath(out, "heat-cut.csv"))
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "figure"=>"F38",
    "origin"=>"synthetic",
    "input_sha256"=>meta["input_sha256"],
    "study"=>"r9-trading-20260921-v2",
    "units"=>"MW; hour index; dt=1 h",
    "not_an_optimized_dispatch"=>true,
    "optimization_performed"=>false,
    "files"=>Dict(name=>hashfile(joinpath(out, name)) for name in readdir(out)),
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure.toml"), "w")
println("F38 generated from saved input bounds; no solve.")
