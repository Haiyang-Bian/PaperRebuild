# F50只读取封存区域证书与原线路容量，不求解或改变原调度。
using CairoMakie, CSV, TOML, SHA

hashfile(p) = bytes2hex(sha256(read(p)))
files(dir) = Dict(
    replace(relpath(joinpath(d, f), dir), '\\' => '/') => hashfile(joinpath(d, f)) for
    (d, _, names) in walkdir(dir) for f in names
)
length(ARGS) == 2 || error("usage: plot_r9_electric_cut.jl EVIDENCE NEW_FIGURES")
folder, out = abspath.(ARGS)
ispath(out) && error("不覆盖已有F50图表")
actual = files(folder)
delete!(actual, "artifacts.toml")
actual == TOML.parsefile(joinpath(folder, "artifacts.toml"))["files"] || error("图源字节改变")
fault = "author_event1"
certificate = TOML.parsefile(joinpath(folder, "certificates.toml"))[fault]
rows = filter(r -> r.fault == fault, collect(CSV.File(joinpath(folder, "intervals.csv"))))
Set(r.scenario for r in rows) == Set([1]) || error("本图仅声明单一确定情景")
casehash = certificate["case_sha256"]
casepath = joinpath(folder, "objects", casehash)
hashfile(casepath) == casehash || error("原案例字节改变")
case = TOML.parsefile(casepath)
boundary = [
    (
        line = l,
        from = case["electric"]["lines"][l]["from"],
        to = case["electric"]["lines"][l]["to"],
        capacity_MW = case["electric"]["lines"][l]["P_max_MW"],
    ) for l in certificate["boundary_lines"]
]
isempty(certificate["internal_generator_ids"]) || error("图示的区域不再是无内部发电区域")
length(boundary) == 3 || error("图示的三入口条件改变")
runid = only(unique(r.parent_run_id for r in rows))
cap = only(unique(r.boundary_import_upper_MW for r in rows))
x = reduce(vcat, ([r.hour, r.hour + r.dt_h] for r in rows))
y = reduce(vcat, ([r.critical_MW, r.critical_MW] for r in rows))
fig = Figure(size = (1500, 870), fontsize = 20)
Label(fig[0, 1:2], "F50 | A necessary electric supply limit", fontsize = 28)
Label(
    fig[1, 1:2],
    "Synthetic replacement inputs | 21-node region | No internal generators | Event [10, 14) h",
    fontsize = 19,
)
a = Axis(
    fig[2, 1],
    title = "Three healthy boundary lines",
    xlabel = "Line ID (end nodes)",
    ylabel = "Active power capacity (MW)",
    xticks = (1:3, ["$(r.line)\n($(r.from)-$(r.to))" for r in boundary]),
)
barplot!(a, 1:3, [r.capacity_MW for r in boundary]; color = :teal, width = 0.55)
for (i, r) in enumerate(boundary)
    text!(
        a,
        i,
        r.capacity_MW + 0.12;
        text = string(round(r.capacity_MW; digits = 4)),
        align = (:center, :bottom),
        fontsize = 18,
    )
end
ylims!(a, 0, maximum(r.capacity_MW for r in boundary) * 1.35)
b = Axis(
    fig[2, 2],
    title = "Demand exceeds the most optimistic import",
    xlabel = "Hour of day",
    ylabel = "Active power (MW)",
)
band!(b, x, fill(cap, length(x)), y; color = (:darkorange, 0.3), label = "Unavoidable deficit")
lines!(b, x, y; color = :darkorange, linewidth = 3, label = "Critical demand in region")
lines!(
    b,
    [minimum(x), maximum(x)],
    [cap, cap];
    color = :teal,
    linewidth = 3,
    linestyle = :dash,
    label = "Import upper bound",
)
xlims!(b, minimum(x), maximum(x))
ylims!(b, 0, maximum(y) * 1.18)
Legend(fig[3, 2], b; orientation = :horizontal, nbanks = 2, labelsize = 16)
Label(
    fig[3, 1],
    "Total import capacity: $(round(cap; digits=6)) MW\nHealthy lines may carry power in either direction",
    fontsize = 17,
)
Label(
    fig[4, 1:2],
    "Four-hour critical energy loss >= $(round(certificate["loss_lower_MWh"]; digits=6)) MWh > $(certificate["loss_limit_MWh"]) MWh target\nNecessary bound only; this does not identify the full minimum loss or the author's line ratings.",
    fontsize = 20,
)
Label(fig[5, 1:2], "Parent run: $runid", fontsize = 15)
mkpath(out)
CSV.write(joinpath(out, "source.csv"), rows; newline = '\n')
CSV.write(joinpath(out, "boundary.csv"), boundary; newline = '\n')
save(joinpath(out, "F50-electric-cut.png"), fig)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config = Dict(
    "schema" => "r9-electric-cut-figure-v1",
    "figure" => "F50",
    "fault" => fault,
    "source_artifacts_sha256" => hashfile(joinpath(folder, "artifacts.toml")),
    "case_sha256" => casehash,
    "run_id" => runid,
    "nodes" => certificate["nodes"],
    "units" => ["MW", "MWh", "h"],
    "synthetic_replacement_inputs" => true,
    "optimization_performed" => false,
    "original_line_ratings_available" => false,
)
open(io -> TOML.print(io, config; sorted = true), joinpath(out, "figure-config.toml"), "w")
# 清单写入之前计算文件哈希，避免清单自引用。
hashes = files(out)
open(
    io -> TOML.print(io, Dict("files" => hashes); sorted = true),
    joinpath(out, "artifacts.toml"),
    "w",
)
println("F50 written: ", relpath(out, dirname(@__DIR__)))
