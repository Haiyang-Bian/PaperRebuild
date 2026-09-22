# F51只读独立重验报告；3B/C相同操作只画一份，不启动优化。
using CairoMakie, CSV, TOML, SHA

hashfile(p) = bytes2hex(sha256(read(p)))
files(dir) = Dict(
    replace(relpath(joinpath(d, f), dir), '\\'=>'/')=>hashfile(joinpath(d, f)) for
    (d, _, names) in walkdir(dir) for f in names
)
length(ARGS)==2 || error("usage: plot_r9_evaluation.jl REPORT NEW_FIGURES")
folder, out=abspath.(ARGS)
ispath(out) && error("不覆盖已有F51图表")
actual=files(folder)
delete!(actual, "artifacts.toml")
actual==TOML.parsefile(joinpath(folder, "artifacts.toml"))["files"] || error("图源字节改变")
summary=TOML.parsefile(joinpath(folder, "summary.toml"))
summary["schema"]=="r9-heldout-report-v2" && summary["currency"]=="CNY" || error("图源版本/币种")
summary["distinct_operations"]==1 || error("本图声明一个独立操作")
owner=only(keys(summary["operations"]))
s=summary["operations"][owner]
rows=collect(CSV.File(joinpath(folder, "daily.csv")))
all(r->r.owner==owner, rows) && length(rows)==s["n"] || error("日记录数量/身份")
risk=s["risk"]
complete=filter(r->r.cost_complete, rows)
isempty(complete) && error("没有费用完整日，不能绘制费用曲线")
operation=summary["slots"][owner]["operation_sha256"]
aliases=sort([k for (k, v) in summary["slots"] if get(v, "compute_owner", nothing)==owner])
fig=Figure(size = (1600, 1040), fontsize = 20)
Label(fig[0, 1:2], "F51 | Held-out comfort, cost and numerical checks", fontsize = 29)
Label(
    fig[1, 1:2],
    "Synthetic inputs | $(s["saved_day_records"]) / $(s["n"]) frozen days evaluated | $(join(aliases," / ")) share ONE operation | Complete future known",
    fontsize = 19,
)
a=Axis(
    fig[2, 1],
    title = "Comfort violations: one-sided 95% bounds",
    xlabel = "Whole-day violation probability (%)",
    yticks = ([1], ["One frozen\noperation"]),
)
lo, hi=100risk["lower"], 100risk["upper"]
lines!(a, [lo, hi], [1, 1]; color = :teal, linewidth = 6)
scatter!(a, [100risk["known_violation_fraction"]], [1]; color = :teal, markersize = 16)
vlines!(a, [100risk["epsilon"]]; color = :darkorange, linestyle = :dash, linewidth = 3)
text!(a, 100risk["epsilon"], 1.24; text = "5% target", align = (:left, :bottom), fontsize = 18)
xlims!(a, -0.25, max(6.25, hi*1.08))
ylims!(a, 0.65, 1.5)
Label(
    fig[3, 1],
    "Pass $(risk["passed"]) | Violation $(risk["violations"]) | Unknown $(risk["unknown"])\nUpper bound: $(round(hi;digits=4))% | $(risk["status"])",
    fontsize = 18,
)
b=Axis(
    fig[2, 2],
    title = "Net operating cost on evaluated days",
    xlabel = "CNY per complete day",
    ylabel = "Empirical cumulative fraction",
)
costs=sort([r.net_cost_CNY for r in complete])
stairs!(
    b,
    costs,
    collect(1:length(costs)) ./ length(costs);
    color = :steelblue,
    linewidth = 3,
    step = :post,
)
vlines!(b, [sum(costs)/length(costs)]; color = :darkorange, linestyle = :dash, linewidth = 2)
ylims!(b, 0, 1.02)
Label(
    fig[3, 2],
    "Cost-complete days: $(length(costs)) / $(s["n"]) | Dashed line: mean\nNo comparison with the unavailable 3A candidate",
    fontsize = 18,
)
c=Axis(
    fig[4, 1],
    title = "Independent model and LP/KKT residuals",
    xlabel = "Frozen test-day index",
    ylabel = "Maximum residual / acceptance tolerance",
    yscale = log10,
)
floorvalue=1e-14
for (key, color, label) in (
    (:physical_max_normalized, :teal, "Adopted physical model"),
    (:lp_kkt_max_normalized, :purple, "LP primal / dual / complementarity"),
)
    idx=findall(r->isfinite(getproperty(r, key)), rows)
    scatter!(
        c,
        idx,
        [max(floorvalue, getproperty(rows[i], key)) for i in idx];
        color = (color, 0.6),
        markersize = 4,
        label,
    )
end
hlines!(
    c,
    [1.0];
    color = :darkorange,
    linestyle = :dash,
    linewidth = 2,
    label = "Acceptance threshold",
)
yvals=vcat([r.physical_max_normalized for r in rows], [r.lp_kkt_max_normalized for r in rows])
finite=filter(isfinite, yvals)
ylims!(c, floorvalue/2, max(2.0, maximum(finite; init = 0.0)*1.5))
Legend(fig[5, 1], c; orientation = :horizontal, nbanks = 2, labelsize = 15)
d=Axis(
    fig[4, 2],
    title = "Actual reserve calls are near zero",
    xlabel = "Frozen test-day index",
    ylabel = "Called energy (10^-12 MWh/day)",
)
energy_scale=1e-12
idx=findall(r->isfinite(r.called_energy_MWh), rows)
scatter!(
    d,
    idx,
    [rows[i].called_energy_MWh/energy_scale for i in idx];
    color = (:steelblue, 0.55),
    markersize = 5,
)
ylims!(d, 0, max(1.0, maximum(rows[i].called_energy_MWh/energy_scale for i in idx)*1.1))
Label(
    fig[5, 2],
    "Comfort reliability does not establish material reserve-service value.\nNo original AC-flow or online-control certification.",
    fontsize = 17,
)
Label(
    fig[6, 1:2],
    "Operation $(first(operation,16)) | Frozen input $(first(summary["freeze_sha256"],16))\nResidual display floor: 1e-14 (display only). Full values and run IDs remain in source.csv.",
    fontsize = 16,
)
colsize!(fig.layout, 1, Relative(0.5))
colsize!(fig.layout, 2, Relative(0.5))
mkpath(out)
cp(joinpath(folder, "daily.csv"), joinpath(out, "source.csv"))
cp(joinpath(folder, "summary.toml"), joinpath(out, "summary.toml"))
save(joinpath(out, "F51-heldout-evaluation.png"), fig)
save(joinpath(out, "F51-heldout-evaluation.svg"), fig)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "schema"=>"r9-heldout-figure-v1",
    "figure"=>"F51",
    "source_artifacts_sha256"=>hashfile(joinpath(folder, "artifacts.toml")),
    "freeze_sha256"=>summary["freeze_sha256"],
    "operation_sha256"=>operation,
    "aliases"=>aliases,
    "distinct_operations"=>1,
    "run_ids"=>[String(r.run_id) for r in rows if !ismissing(r.run_id)],
    "units"=>["CNY/day", "MWh/day", "probability", "normalized residual"],
    "energy_display_scale_MWh"=>energy_scale,
    "residual_display_floor"=>floorvalue,
    "synthetic_replacement_inputs"=>true,
    "optimization_performed"=>false,
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure-config.toml"), "w")
hashes=files(out)
open(io->TOML.print(io, Dict("files"=>hashes); sorted = true), joinpath(out, "artifacts.toml"), "w")
println("F51 written from saved values: ", relpath(out, dirname(@__DIR__)))
