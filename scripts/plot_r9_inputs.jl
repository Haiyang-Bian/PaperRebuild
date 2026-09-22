using CairoMakie, CSV, TOML, SHA
include("r9_source_report.jl")
length(ARGS)==2 || error("usage: plot_r9_inputs.jl REPORT NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("不得覆盖已有拓扑图")
R9SourceReport.check_report(report)
g=TOML.parsefile(joinpath(report, "topology.toml"))
d=TOML.parsefile(joinpath(report, "inputs.toml"))

# 仅用根的深度与子树叶序布局；不使用地图距离或假定真实输运方向。
function tree_positions(block)
    n, root=block["nodes"], block["root"]
    children=[Int[] for _ in 1:n]
    for (i, j) in block["edges"]
        push!(children[i], j)
    end
    x, y=zeros(n), zeros(n)
    leaf=Ref(0)
    function visit(i, depth)
        x[i]=depth
        if isempty(children[i])
            leaf[]+=1
            y[i]=leaf[]
        else
            foreach(j->visit(j, depth+1), children[i])
            y[i]=sum(y[j] for j in children[i])/length(children[i])
        end
    end
    visit(root, 0)
    x, y
end

nodes, edges=NamedTuple[], NamedTuple[]
fig=Figure(size = (2100, 1120), fontsize = 19)
Label(fig[0, 1:2], "F33 | Chapter 7 source connectivity", fontsize = 30)
Label(
    fig[1, 1:2],
    "Original node IDs | layout is schematic; lengths, impedances, temperatures and flows are NOT inferred",
    fontsize = 19,
)
for (column, side) in enumerate(("electric", "heat"))
    block=g[side]
    x, y=tree_positions(block)
    prefix=side=="electric" ? "E" : "H"
    title=side=="electric" ? "44 electrical nodes / 43 base edges" :
          "38 heating nodes / 37 base pipe pairs"
    ax=Axis(fig[2, column], title = title, xticksvisible = false, yticksvisible = false)
    hidedecorations!(ax)
    hidespines!(ax)
    for (i, j) in block["edges"]
        upstream=side=="electric" && [i, j] in block["upstream_feeders"]
        lines!(
            ax,
            [x[i], x[j]],
            [y[i], y[j]];
            color = upstream ? :darkorange : :steelblue,
            linewidth = 2.3,
        )
        push!(
            edges,
            (network = side, from = i, to = j, status = upstream ? "upstream_feeder" : "base"),
        )
    end
    for (i, j) in d["trading"]["new_$(side)_ties"]
        lines!(ax, [x[i], x[j]], [y[i], y[j]]; color = :seagreen, linestyle = :dash, linewidth = 2)
        push!(edges, (network = side, from = i, to = j, status = "trading_tie"))
    end
    special=side=="electric" ? [1, 20, 44] : [1, 15]
    for i in 1:block["nodes"]
        scatter!(
            ax,
            [x[i]],
            [y[i]];
            color = i in special ? :moccasin : :lightsteelblue,
            markersize = 36,
        )
        text!(ax, x[i], y[i]; text = prefix*string(i), align = (:center, :center), fontsize = 13)
        push!(nodes, (network = side, node = i, x = x[i], y = y[i], layout_unit = "schematic"))
    end
    xlims!(ax, -0.7, maximum(x)+0.7)
    ylims!(ax, 0, maximum(y)+1)
end
Legend(
    fig[3, 1:2],
    [
        LineElement(color = :steelblue, linewidth = 3),
        LineElement(color = :darkorange, linewidth = 3),
        LineElement(color = :seagreen, linestyle = :dash, linewidth = 3),
    ],
    [
        "Base connection",
        "Upstream feeder (transformer parameters missing)",
        "Chapter 7.3 added tie",
    ],
    orientation = :horizontal,
    framevisible = false,
)
Label(
    fig[4, 1:2],
    "Source: thesis Fig. 7-2 (PDF 127), Fig. 7-6 (PDF 133); factual transcription, not an optimization result",
    fontsize = 18,
)
mkpath(out)
CSV.write(joinpath(out, "nodes.csv"), nodes)
CSV.write(joinpath(out, "edges.csv"), edges)
save(joinpath(out, "F33-r9-topology.png"), fig; px_per_unit = 1)
save(joinpath(out, "F33-r9-topology.svg"), fig)
write(joinpath(out, "plot_r9_inputs.jl"), read(@__FILE__))
config=Dict(
    "schema"=>"r9-source-figure-v1",
    "figure"=>"F33",
    "optimization_performed"=>false,
    "report_manifest_sha256"=>R9SourceReport.hashfile(joinpath(report, "manifest.toml")),
    "coordinates"=>"deterministic rooted-tree layout; not physical length or flow direction",
    "files"=>Dict(
        name=>R9SourceReport.hashfile(joinpath(out, name)) for name in (
            "nodes.csv",
            "edges.csv",
            "F33-r9-topology.png",
            "F33-r9-topology.svg",
            "plot_r9_inputs.jl",
        )
    ),
)
open(joinpath(out, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("F33: 82 original nodes, 80 base edges and 6 trading ties; no optimization.")
