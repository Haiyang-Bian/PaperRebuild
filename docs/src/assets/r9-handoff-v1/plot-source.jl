# F49只读取封存的必要温区回放；不重新运行调度、IIS或优化。
using CairoMakie, CSV, TOML, SHA
# 图层只解码原字节。不要通过完整科研报告器间接加载JuMP或要求文档环境增加求解器。
module Evidence
using TOML, SHA
hashfile(p) = bytes2hex(sha256(read(p)))
files(dir) = Dict(
    replace(relpath(joinpath(d, f), dir), '\\' => '/') => hashfile(joinpath(d, f)) for
    (d, _, fs) in walkdir(dir) for f in fs
)
function check(dir)
    actual = files(dir)
    delete!(actual, "artifacts.toml")
    actual == TOML.parsefile(joinpath(dir, "artifacts.toml"))["files"] || error("图源字节改变")
end
function bytes(dir, hash)
    occursin(r"^[0-9a-f]{64}$", hash) || error("对象哈希非法")
    file = joinpath(dir, "objects", hash)
    value = if isfile(file)
        read(file)
    else
        row = TOML.parsefile(joinpath(dir, "object-chunks.toml"))["objects"][hash]
        joined = reduce(vcat, (bytes(dir, part) for part in row["parts"]))
        length(joined) == row["bytes"] || error("对象长度改变")
        joined
    end
    bytes2hex(sha256(value)) == hash || error("对象原字节改变")
    value
end
parseobject(dir, hash) = TOML.parse(String(bytes(dir, hash)))
end
length(ARGS) == 2 || error("usage: plot_r9_handoff.jl EVIDENCE NEW_FIGURES")
folder, out = abspath.(ARGS)
ispath(out) && error("不覆盖温区图表")
Evidence.check(folder)
objects = Evidence
index = TOML.parsefile(joinpath(folder, "parents.toml"))
result = objects.parseobject(
    folder,
    TOML.parsefile(joinpath(folder, "result-index.toml"))["result_sha256"],
)
pipe = result["conflict_proof"]["pipe"]
rows = NamedTuple[]
for label in ("baseline", "candidate")
    spec = objects.parseobject(folder, index[label]["spec.toml"])
    case = objects.parseobject(folder, index[label]["case.toml"])
    old = objects.parseobject(folder, index[label]["result.toml"])
    checkrows = result[label]["necessary_check"]["rows"]
    n = spec["substeps"]
    for k in 1:n
        shared(r) = r["pipe"] == pipe && r["side"] == "S" && r["scenario"] == 1 && r["substep"] == k
        outlet = only(filter(r -> shared(r) && haskey(r, "inlet_independent"), checkrows))
        spatial = only(filter(r -> shared(r) && r["relation"] == "R7-T4-spatial", checkrows))
        push!(
            rows,
            (
                label = label,
                parent_run_id = old["run_id"],
                pipe = pipe,
                substep = k,
                start_min = 60 * (k - 1) * case["dt_h"] / n,
                end_min = 60 * k * case["dt_h"] / n,
                outlet_low_K = outlet["lower_response_K"],
                outlet_high_K = outlet["upper_response_K"],
                inlet_independent = outlet["inlet_independent"],
                spatial_best_min_K = spatial["hot_state_min_K"],
                lower_bound_K = outlet["minimum_K"],
                tolerance_K = 1e-4,
            ),
        )
    end
end
fig = Figure(size = (1540, 930), fontsize = 20)
Label(fig[0, 1:2], "F49 | Inherited pipe temperature: average vs detailed limits", fontsize = 26)
Label(
    fig[1, 1:2],
    "Declared substitute inputs | Pipe $pipe supply | First normal period after event",
    fontsize = 20,
)
a = Axis(
    fig[2, 1],
    title = "Substep mean outlet (inlet-independent here)",
    xlabel = "Minutes after event",
    ylabel = "Temperature (K)",
)
b = Axis(
    fig[2, 2],
    title = "Coldest spatial point with hottest allowed inlet",
    xlabel = "Minutes after event",
    ylabel = "Temperature (K)",
)
colors = (:steelblue, :darkorange)
for (i, label) in enumerate(("baseline", "candidate"))
    r = filter(x -> x.label == label, rows)
    all(x -> x.inlet_independent && x.outlet_low_K == x.outlet_high_K, r) ||
        error("首时段入口影响不再退化，不能绘成确定出口")
    title = label == "baseline" ? "Original 4B state" : "CHP1-pinned state"
    x = vcat([z.start_min for z in r], last(r).end_min)
    y = vcat([z.outlet_low_K for z in r], last(r).outlet_low_K)
    stairs!(a, x, y; step = :post, color = colors[i], linewidth = 3, label = title)
    scatterlines!(
        b,
        [z.end_min for z in r],
        [z.spatial_best_min_K for z in r];
        color = colors[i],
        linewidth = 3,
        markersize = 10,
        label = title,
    )
end
limit = first(rows).lower_bound_K
for ax in (a, b)
    hlines!(
        ax,
        [limit];
        color = :firebrick,
        linestyle = :dash,
        linewidth = 2,
        label = "Lower limit",
    )
    hlines!(ax, [limit - 1e-4]; color = :firebrick, linestyle = :dot, linewidth = 1)
    axislegend(ax; position = :rt, labelsize = 16)
end
gap = result["conflict_proof"]["gap_K"]
candidate_rows = filter(r -> r.label == "candidate", rows)
candidate_mean =
    sum((r.end_min - r.start_min) * r.outlet_low_K for r in candidate_rows) /
    sum(r.end_min - r.start_min for r in candidate_rows)
Label(
    fig[3, 1:2],
    "Candidate period mean = $(round(candidate_mean, digits=6)) K; unavoidable local gap = $(round(gap, digits=6)) K\nNecessary thermal check only; no claim of full dispatch feasibility or variable-flow impossibility.",
    fontsize = 19,
)
ids = [
    label * ": " * first(filter(r -> r.label == label, rows)).parent_run_id for
    label in ("baseline", "candidate")
]
Label(fig[4, 1:2], join(ids, "\n"), fontsize = 14)
mkpath(out)
CSV.write(joinpath(out, "source.csv"), rows; newline = '\n')
save(joinpath(out, "F49-handoff-temperature.png"), fig)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config = Dict(
    "schema" => "r9-handoff-figure-v1",
    "figure" => "F49",
    "pipe" => pipe,
    "source_artifacts_sha256" => Evidence.hashfile(joinpath(folder, "artifacts.toml")),
    "units" => ["K", "min"],
    "synthetic_replacement_inputs" => true,
    "optimization_performed" => false,
    "run_ids" => unique(r.parent_run_id for r in rows),
)
open(io -> TOML.print(io, config; sorted = true), joinpath(out, "figure-config.toml"), "w")
open(
    io -> TOML.print(io, Dict("files" => Evidence.files(out)); sorted = true),
    joinpath(out, "artifacts.toml"),
    "w",
)
println("F49 written: ", relpath(out, dirname(@__DIR__)))
