using CSV, TOML, SHA, CairoMakie
length(ARGS)==2 || error("usage: plot_r7_ports.jl REPORT NEW_FIGURES")
src, out=abspath.(ARGS)
ispath(out)&&error("不覆盖端口图件")
sources=[
    "summary.csv",
    "thermal.csv",
    "solver-pairs.csv",
    "island-bound.csv",
    "inputs.toml",
    "rule.toml",
]
registry=TOML.parsefile(joinpath(src, "files.toml"))["files"]
for p in sources
    bytes2hex(sha256(read(joinpath(src, p))))==registry[p] || error("图源哈希改变")
end
rows=collect(CSV.File(joinpath(src, "summary.csv")))
thermal=collect(CSV.File(joinpath(src, "thermal.csv")))
inputs=TOML.parsefile(joinpath(src, "inputs.toml"))
function original_loss(group)
    s=only(filter(s->s["group"]==group, inputs["sources"]))
    s["parent"]["solver_objective_MWh"]
end
function checked_loss(group)
    r=only(filter(r->r.record==group*"_fault1_highs", rows))
    r.adopted_pass || error("没有可绘制的已验证恢复候选")
    r.objective
end
fig=Figure(size = (1360, 980), fontsize = 17)
Label(
    fig[0, :],
    "F24 | Compatible ports change the resilience assessment (synthetic)",
    fontsize = 24,
    tellwidth = false,
)
a=Axis(
    fig[1, 1],
    title = "A  Source and load temperature-drop ranges",
    xlabel = "Temperature difference (K)",
    yticks = (
        [1, 2, 3],
        ["Original source envelope", "Original load envelope", "Compatible with temperature boxes"],
    ),
)
for (i, lo, hi, col) in [(1, 0, 80, :gray), (2, 0, 60, :gray), (3, 10, 50, :darkorange)]
    lines!(a, [lo, hi], [i, i], color = col, linewidth = 10)
end
xlims!(a, -4, 84);
ylims!(a, 0.5, 3.5)
b=Axis(
    fig[1, 2],
    title = "B  Hand case: disconnected electric line",
    xticks = ([1, 2], ["Original proxy", "Compatible ports"]),
    ylabel = "Expected electricity + heat unserved (MWh)",
)
ys=[original_loss("hand"), checked_loss("hand")]
barplot!(b, 1:2, ys, color = [:gray, :darkorange], width = 0.5)
ylims!(b, 0, 1)
for i in 1:2
    text!(b, i, ys[i]+0.025, text = string(round(ys[i]; digits = 4)), align = (:center, :bottom))
end
c=Axis(
    fig[2, 1],
    title = "C  Same inherited normal states; reoptimized recovery",
    xticks = ([1, 2], ["Reserve event 1", "Reserve event 2"]),
    ylabel = "Expected unserved energy (MWh)",
)
old=[original_loss("reserve_event_$i") for i in 1:2]
new=[checked_loss("reserve_event_$i") for i in 1:2]
barplot!(c, (1:2) .- 0.16, old, width = 0.3, color = :gray, label = "Original feasible witnesses")
scatter!(c, (1:2) .- 0.16, old, color = :black, markersize = 7)
barplot!(
    c,
    (1:2) .+ 0.16,
    new,
    width = 0.3,
    color = :darkorange,
    label = "Compatible-port optimal recovery",
)
hlines!(c, [0.4], color = :firebrick, linestyle = :dash, label = "Analytic heat-loss lower bound")
ylims!(c, 0, 0.7);
axislegend(c, position = :lt, labelsize = 13)
z=filter(r->r.kind=="planning"&&r.group=="zero_loss", rows)
f=filter(r->r.kind=="planning"&&r.group=="allow_full_heat", rows)
costs=[Float64(r.objective) for r in f if r.adopted_pass]
d=GridLayout();
fig[2, 2]=d
Label(
    d[1, 1],
    "D  Two separately declared planning requirements",
    fontsize = 18,
    font = :bold,
    tellwidth = false,
)
zero=count(r->r.status=="infeasible_certified", z)
ok=count(r->r.adopted_pass, f)
range=isempty(costs) ? "No accepted planning cost" :
      "Accepted normal cost: $(round(minimum(costs);digits=3)) to $(round(maximum(costs);digits=3)) USD"
Label(
    d[2, 1],
    "Zero unserved energy allowed\n$zero / $(length(z)) methods certify infeasibility",
    fontsize = 21,
    color = :firebrick,
    tellwidth = false,
)
Label(
    d[3, 1],
    "0.4 MWh event loss allowed (diagnostic)\n$ok / $(length(f)) methods find model-safe plans\n$range",
    fontsize = 19,
    tellwidth = false,
)
Label(
    d[4, 1],
    "The second requirement permits the entire heat load to be lost.\nIts cost is not a zero-loss resilience benefit.",
    fontsize = 15,
    tellwidth = false,
)
colsize!(fig.layout, 1, Relative(0.5));
colsize!(fig.layout, 2, Relative(0.5))
pass=count(r->r.same_dispatch_pass, thermal)
Label(
    fig[3, :],
    "Detailed heat reconstruction: $pass / $(length(thermal)) saved HiGHS candidates pass; this is a separate check.\nOriginal records retained. Models, run IDs, units and source values accompany this figure.",
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
save(joinpath(out, "F24-compatible-ports.png"), fig; px_per_unit = 1.5)
save(joinpath(out, "F24-compatible-ports.svg"), fig)
for p in sources
    cp(joinpath(src, p), joinpath(out, p))
end
files=Dict(
    p=>bytes2hex(sha256(read(joinpath(out, p)))) for
    p in vcat(sources, ["F24-compatible-ports.png", "F24-compatible-ports.svg"])
)
d=Dict(
    "schema"=>"r7-ports-figure-v1",
    "origin"=>"synthetic",
    "solver_called"=>false,
    "run_ids"=>vcat([r.run_id for r in rows], [r.run_id for r in thermal]),
    "units"=>["K", "MWh", "USD"],
    "source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "files"=>files,
    "size_px"=>[2040, 1470],
)
write(joinpath(out, "figure.toml"), sprint(io->TOML.print(io, d; sorted = true)))
println(
    "F24 drawn only from frozen source values, with conditional model and heat checks separate.",
)
