using CSV, TOML, SHA, CairoMakie
length(ARGS) == 3 || error("usage: plot_r7_transport.jl REPORT RECHECK NEW_FIGURES")
src, revised, out = abspath.(ARGS)
ispath(out) && error("不覆盖逐管调度图")
hashfile(p) = bytes2hex(sha256(read(p)))
meta = TOML.parsefile(joinpath(revised, "recheck.toml"))
meta["original_report_sha256"] == hashfile(joinpath(src, "files.toml")) ||
    error("补证并非来自此原报告")
sources = Dict(
    "summary.csv" => (src, "summary.csv"),
    "transport-witness.csv" => (src, "transport-witness.csv"),
    "solver-pairs.csv" => (src, "solver-pairs.csv"),
    "inputs.toml" => (src, "inputs.toml"),
    "rule.toml" => (src, "rule.toml"),
    "recheck-summary.csv" => (revised, "summary.csv"),
    "zero-branch.csv" => (revised, "zero-branch.csv"),
    "recheck.toml" => (revised, "recheck.toml"),
)
for (_, (dir, file)) in sources
    registry = TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    hashfile(joinpath(dir, file)) == registry[file] || error("图源哈希改变")
end
rows = collect(CSV.File(joinpath(src, "summary.csv")))
witness = collect(CSV.File(joinpath(src, "transport-witness.csv")))
checks = collect(CSV.File(joinpath(revised, "summary.csv")))
groups = ["hand", "reserve_event_1", "reserve_event_2"]
names = ["Hand case", "Reserve event 1", "Reserve event 2"]
function selected(group, flow, solver = "HiGHS", n = 16)
    r = only(
        filter(
            x ->
                x.group == group &&
                x.flow == flow &&
                x.fault == 0 &&
                x.solver == solver &&
                x.substeps == n,
            rows,
        ),
    )
    c = only(filter(x -> x.record == r.record, checks))
    c.corrected_model_pass || error("目标图缺少通过采用模型的原值")
    r, c
end
fig = Figure(size = (1460, 1060), fontsize = 17)
Label(
    fig[0, :],
    "F25 | Transport-aware recovery at prescribed flow (synthetic)",
    fontsize = 24,
    tellwidth = false,
)
a = Axis(
    fig[1, 1],
    title = "A  Original flow: first-step heat delivery bound",
    xticks = (1:3, names),
    ylabel = "Delivered heat power (MW)",
)
upper = [
    only(filter(x -> x.group == g && x.kind == "load" && x.step == 1 && x.scenario == 1, witness)).maximum_MW for g in groups
]
barplot!(a, 1:3, upper, color = :darkorange, width = 0.5)
hlines!(a, [0.4], color = :firebrick, linestyle = :dash, label = "Original delivery target: 0.4 MW")
ylims!(a, 0, 0.49)
for i in 1:3
    text!(
        a,
        i,
        upper[i] - 0.025,
        text = string(round(upper[i]; digits = 6)),
        align = (:center, :top),
        color = :white,
    )
end
axislegend(a; position = :ct, labelsize = 14)
b = Axis(
    fig[1, 2],
    title = "B  Healthy internal line: joint redispatch",
    xticks = (1:3, names),
    ylabel = "Electricity + heat unserved (MWh)",
)
flows = ["parent", "reference", "zero"]
colors = [:darkorange, :steelblue, :gray65]
labels = ["Inherited flow", "Predeclared reference flow", "Zero flow"]
for k in 1:3
    ys = [selected(g, flows[k])[1].loss_MWh for g in groups]
    xs = (1:3) .+ (k - 2) * 0.23
    barplot!(b, xs, ys; width = 0.21, color = colors[k], label = labels[k])
    scatter!(b, xs, ys; color = colors[k], markersize = 7)
end
ylims!(b, -0.025, 1.06)
axislegend(b; position = :rt, labelsize = 13)
c = Axis(
    fig[2, 1],
    title = "C  Hand case: thermal substep refinement",
    xticks = (1:3, ["1", "4", "16"]),
    xlabel = "Thermal substeps per original time step",
    ylabel = "Electricity + heat unserved (MWh)",
)
for (k, flow) in enumerate(flows[1:2])
    ys = [selected("hand", flow, "HiGHS", n)[1].loss_MWh for n in (1, 4, 16)]
    lines!(c, 1:3, ys; color = colors[k], linewidth = 3, label = labels[k])
    scatter!(c, 1:3, ys; color = colors[k], markersize = 10)
end
ylims!(c, -0.008, 0.070)
axislegend(c; position = :ct, labelsize = 14)
d = Axis(
    fig[2, 2],
    title = "D  Same loss target, different battery controls",
    xticks = (1:3, names),
    ylabel = "Maximum simultaneous charge / discharge (MW)",
)
for (k, solver) in enumerate(("HiGHS", "Gurobi", "Clarabel"))
    ys = [selected(g, "reference", solver)[2].simultaneous_charge_discharge_MW for g in groups]
    xs = (1:3) .+ (k - 2) * 0.23
    barplot!(d, xs, ys; width = 0.21, color = (:steelblue, :seagreen, :purple)[k], label = solver)
    scatter!(d, xs, ys; color = (:steelblue, :seagreen, :purple)[k], markersize = 7)
end
ylims!(d, -0.008, 0.27)
axislegend(d; position = :lt, labelsize = 14)
colsize!(fig.layout, 1, Relative(0.5))
colsize!(fig.layout, 2, Relative(0.5))
Label(
    fig[3, :],
    "All values are saved results; no reoptimization. Healthy internal line still has the original PCC disconnection.\nFixed-flow bounds are conditional; 12 positive-flow / disconnected-line runs remain infeasible.\nThree historical validation failures are separately rechecked; their battery simultaneity and missing bounds remain.",
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
save(joinpath(out, "F25-transport-redispatch.png"), fig; px_per_unit = 1.5)
save(joinpath(out, "F25-transport-redispatch.svg"), fig)
for (dest, (dir, file)) in sources
    cp(joinpath(dir, file), joinpath(out, dest))
end
files = Dict(
    p => hashfile(joinpath(out, p)) for p in vcat(
        collect(keys(sources)),
        ["F25-transport-redispatch.png", "F25-transport-redispatch.svg"],
    )
)
config = Dict(
    "schema" => "r7-transport-figure-v1",
    "origin" => "synthetic",
    "solver_called" => false,
    "run_ids" => [r.run_id for r in rows],
    "units" => ["MW", "MWh", "thermal substeps"],
    "source_sha256" => hashfile(@__FILE__),
    "files" => files,
    "size_px" => [2190, 1590],
    "scope" => "prescribed flow; adopted substep heat dynamics; original and corrected validation distinct",
)
write(joinpath(out, "figure.toml"), sprint(io -> TOML.print(io, config; sorted = true)))
println("F25 saved from immutable original values and separate verification correction.")
