using CairoMakie, CSV

# 同初值v1/v2轨迹；空分支不造图例，近零费用使用可读坐标，不夸大舍入量级变化。
function plot_r3_pg_comparison(old, current, id, output)
    fig=Figure(size = (1100, 430))
    Label(fig[0, 1:2], "Synthetic v1/v2 | "*id)
    source=NamedTuple[]
    for (col, field, title) in (
        (1, "dispatch", "Feasible SP cost (currency)"),
        (2, "diagnostic", "Diagnostic merit (dimensionless)"),
    )
        ax=Axis(fig[1, col]; xlabel = "Outer iteration", ylabel = title)
        ordinates=Float64[]
        for (label, result) in (("v1", old), ("v2", current))
            rows=filter(x->x["mode"]==field, get(result, "iterations", Any[]))
            isempty(rows) && continue
            ys=[
                field=="dispatch" ? result["stages"][x["stage"]]["operating_cost"] : x["merit"] for
                x in rows
            ]
            append!(ordinates, ys)
            scatterlines!(ax, [x["iteration"] for x in rows], ys; label)
            append!(
                source,
                [
                    (; id, version = label, branch = field, iteration = x["iteration"], value = y)
                    for (x, y) in zip(rows, ys)
                ],
            )
        end
        if !isempty(ordinates)
            center=(minimum(ordinates)+maximum(ordinates))/2
            if maximum(ordinates)-minimum(ordinates)<1e-8*max(1, abs(center))
                pad=1e-6*max(1, abs(center))
                ylims!(ax, center-pad, center+pad)
            end
            axislegend(ax; position = :rt)
        end
    end
    save(joinpath(output, "F06-v1-v2.png"), fig)
    isempty(source) || CSV.write(joinpath(output, "F06-v1-v2-source.csv"), source)
end
