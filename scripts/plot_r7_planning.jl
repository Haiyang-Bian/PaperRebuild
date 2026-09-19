using CSV, CairoMakie, TOML, SHA

length(ARGS)==2 || error("usage: plot_r7_planning.jl EVIDENCE NEW_OUTPUT")
evidence, out=abspath.(ARGS)
ispath(out)&&error("不覆盖已有图件")
hashes=TOML.parsefile(joinpath(evidence, "files.toml"))["files"]
for p in ("summary.csv", "stages.csv", "battery.csv", "rule.toml")
    bytes2hex(sha256(read(joinpath(evidence, p))))==hashes[p] || error("图源哈希错误")
end
rule=TOML.parsefile(joinpath(evidence, "rule.toml"))
rule["origin"]=="synthetic"||error("来源标签错误")
stages=CSV.File(joinpath(evidence, "stages.csv"));
battery=CSV.File(joinpath(evidence, "battery.csv"));
summary=CSV.File(joinpath(evidence, "summary.csv"))
fig=Figure(size = (1200, 850), fontsize = 16)
Label(fig[0, :], "F21 | Anticipatory reserve under finite faults (synthetic)", fontsize = 23)
ax=Axis(
    fig[1, 1:2],
    xlabel = "Outer master iteration",
    ylabel = "Normal operating cost (USD)",
    xticks = [1, 2],
)
rows=filter(r->r.record=="reserve_finite_fault_ccg"&&!ismissing(r.normal_cost_USD), collect(stages))
scatterlines!(
    ax,
    [r.iteration for r in rows],
    [r.normal_cost_USD for r in rows],
    linewidth = 3,
    markersize = 12,
    label = "Finite-fault C&CG",
)
hlines!(
    ax,
    [rule["analytical_rule"]["robust_cost_USD"]],
    color = :darkorange,
    linestyle = :dash,
    label = "Analytic bound / extensive reference",
)
axislegend(ax, position = :rb)
legend_handles=Any[]
for w in 1:2
    a=Axis(
        fig[2, w],
        title = "Normal scenario $w",
        xlabel = "Boundary time (h)",
        ylabel = "Battery energy (MWh)",
        xticks = 0:4,
    )
    for (record, label, color) in (
        ("reserve_normal", "Economic only", :gray),
        ("reserve_finite_fault_ccg", "Safe plan", :steelblue),
    )
        rr=filter(r->r.record==record&&r.scenario==w, collect(battery))
        sort!(rr; by = r->r.time_h)
        handle=lines!(
            a,
            [r.time_h for r in rr],
            [r.energy_MWh for r in rr],
            linewidth = 3,
            label = label,
            color = color,
        )
        w==1&&push!(legend_handles, handle)
    end
    handle=vlines!(a, [1, 2], linestyle = :dot, color = :firebrick, label = "Possible event start")
    w==1&&push!(legend_handles, handle)
end
Legend(
    fig[3, :],
    legend_handles,
    ["Economic only", "Safe plan", "Possible event start"],
    orientation = :horizontal,
)
Label(
    fig[4, :],
    "Legacy case: both planning routes infeasible (committed CHP in an isolated island).\nRecovery uses the adopted two-tank model; no detailed disaster heat or AC-grid certification.",
    fontsize = 16,
    tellwidth = false,
)
ids=[String(r.run_id) for r in summary]
Label(
    fig[5, :],
    "Saved run IDs: "*join([last(split(x, '-')) for x in ids], ", ")*"\nFull IDs, units, input rules and source hashes accompany this figure.",
    fontsize = 12,
    tellwidth = false,
)
mkpath(out)
for p in ("summary.csv", "stages.csv", "battery.csv", "rule.toml")
    cp(joinpath(evidence, p), joinpath(out, p))
end
save(joinpath(out, "F21-finite-planning.png"), fig)
save(joinpath(out, "F21-finite-planning.svg"), fig)
config=Dict(
    "schema"=>"r7-planning-figure-v1",
    "origin"=>"synthetic",
    "figure"=>"F21",
    "run_ids"=>ids,
    "source_rule_sha256"=>hashes["rule.toml"],
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "reoptimized"=>false,
    "files"=>Dict(p=>bytes2hex(sha256(read(joinpath(out, p)))) for p in readdir(out)),
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure.toml"), "w")
println("F21 drawn only from saved synthetic values.")
