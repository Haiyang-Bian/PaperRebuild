using PaperRebuild, CairoMakie, CSV, TOML, SHA

function PaperRebuild.plot_r2_run(
    dir::AbstractString;
    reference = nothing,
    output = joinpath(dir, "figures"),
)
    loaded = read_r2_run(dir)
    haskey(loaded.result, "values") || error("无解运行不能绘制轨迹")
    ispath(output) && error("拒绝覆盖旧图；指定新output目录")
    mkdir(output)
    report = validate_r2_solution(loaded.case, loaded.result)
    CSV.write(joinpath(output, "F04-source.csv"), report.rows)
    fig = Figure(size = (1300, 820), fontsize = 15)
    Label(fig[0, 1:2], "Synthetic R2 | "*loaded.metadata["run_id"], fontsize = 19)
    for (col, scope) in enumerate(("model", "physics"))
        rows = filter(r -> r.scope == scope, report.rows)
        equations = unique(r.equation for r in rows)
        ax = Axis(
            fig[1, col],
            title = scope == "model" ? "Adopted model constraints" :
                    "Unrelaxed / reference relations",
            xlabel = "Equation group (see CSV for node and time)",
            ylabel = "Residual / A1 tolerance",
            yscale = log10,
            xticks = (1:length(equations), equations),
            xticklabelrotation = pi/2,
        )
        for (i, eq) in enumerate(equations)
            values = [max(r.residual/r.tolerance, 1e-12) for r in rows if r.equation == eq]
            scatter!(
                ax,
                fill(i, length(values)),
                values;
                color = maximum(values)>1 ? :firebrick : :steelblue,
                markersize = 7,
            )
        end
        hlines!(ax, [1.0]; color = :black, linestyle = :dash, label = "A1 limit")
        ylims!(ax, 1e-12, max(10.0, maximum(max(r.residual/r.tolerance, 1e-12) for r in rows)*3))
    end
    Label(
        fig[2, 1:2],
        "Each point: one equation, node/pipe and time. Model feasibility and physical checks are separate.",
        fontsize = 14,
    )
    save(joinpath(output, "F04-residuals.svg"), fig)
    save(joinpath(output, "F04-residuals.png"), fig)
    detail = Figure(size = (1350, 1080), fontsize = 14)
    Label(
        detail[0, 1:4],
        "Synthetic R2 | "*loaded.metadata["run_id"]*" | equation / entity / time",
        fontsize = 18,
    )
    for (panel, scope) in enumerate(("model", "physics"))
        rows = filter(r -> r.scope == scope, report.rows)
        keys = unique((r.equation, r.entity) for r in rows)
        sort!(
            keys;
            by = key ->
                -maximum(r.residual/r.tolerance for r in rows if (r.equation, r.entity) == key),
        )
        keys = keys[1:min(28, length(keys))]
        times = sort(unique(r.t for r in rows))
        matrix = fill(NaN, length(times), length(keys))
        for (j, key) in enumerate(keys), (i, t) in enumerate(times)
            values =
                [r.residual/r.tolerance for r in rows if (r.equation, r.entity) == key && r.t == t]
            isempty(values) || (matrix[i, j] = log10(max(maximum(values), 1e-12)))
        end
        col = 2panel-1
        ax = Axis(
            detail[1, col],
            title = scope*" — largest 28 equation/entity groups",
            xlabel = "Time index (0 = initial / aggregate)",
            yticks = (1:length(keys), [eq*" / "*entity for (eq, entity) in keys]),
            xticks = (1:length(times), string.(times)),
        )
        hm = heatmap!(
            ax,
            1:length(times),
            1:length(keys),
            matrix;
            colormap = [:steelblue, :white, :firebrick],
            colorrange = (-6.0, 6.0),
            nan_color = :lightgray,
        )
        Colorbar(detail[1, col+1], hm; label = "log10(residual / A1); failure > 0")
    end
    Label(
        detail[2, 1:4],
        "Color clipped at ±6; exact values and all groups in F04-source.csv. Grey / blank = no constraint at that index.",
        fontsize = 13,
    )
    save(joinpath(output, "F04-detail.svg"), detail)
    save(joinpath(output, "F04-detail.png"), detail)
    config = Dict{String,Any}(
        "origin"=>"synthetic",
        "run_id"=>loaded.metadata["run_id"],
        "solution_sha256"=>loaded.metadata["solution_sha256"],
        "julia"=>string(VERSION),
        "CairoMakie"=>string(pkgversion(CairoMakie)),
        "source"=>"saved numerical solution; no solve",
        "F04_floor_ratio"=>1e-12,
        "F04_threshold_ratio"=>1.0,
        "F04_detail_groups_per_scope"=>28,
        "F04_detail_log10_color_range"=>[-6.0, 6.0],
    )
    if !isnothing(reference)
        comparison = compare_r2_runs(reference, dir)
        comparison.status == "compared" || error("参考运行无解")
        CSV.write(joinpath(output, "F05-source.csv"), comparison.rows)
        a = read_r2_run(reference)
        config["reference_run_id"] = a.metadata["run_id"]
        config["reference_solution_sha256"] = a.metadata["solution_sha256"]
        compfig = Figure(size = (1450, 1000), fontsize = 15)
        Label(compfig[0, 1:2], "Synthetic R2 comparison | "*loaded.case.data["id"], fontsize = 20)
        for (r, quantity) in enumerate(("tau_S_mix", "tau_R_mix", "H_port"))
            unit = quantity == "H_port" ? "MW" : "K"
            axis = Axis(compfig[r, 1], title = quantity, xlabel = "Time (h)", ylabel = unit)
            erroraxis = Axis(
                compfig[r, 2],
                title = "Candidate - reference",
                xlabel = "Time (h)",
                ylabel = unit,
            )
            for j in eachindex(loaded.case.data["heat"]["nodes"])
                color = [:steelblue, :darkorange, :seagreen, :purple][mod1(j, 4)]
                rows = filter(x -> x.quantity == quantity && x.node == j, comparison.rows)
                time = [x.t*loaded.case.data["dt_h"] for x in rows]
                lines!(
                    axis,
                    time,
                    [x.reference for x in rows];
                    label = "ref node $j",
                    linewidth = 2,
                    color,
                )
                lines!(
                    axis,
                    time,
                    [x.candidate for x in rows];
                    label = "candidate node $j",
                    linestyle = :dash,
                    linewidth = 2,
                    color,
                )
                scatterlines!(
                    erroraxis,
                    time,
                    [x.difference for x in rows];
                    label = "node $j",
                    color,
                )
            end
            r == 1 && Legend(compfig[1:3, 3], axis; labelsize = 11)
        end
        Label(
            compfig[4, 1:2],
            "Reference: "*a.metadata["run_id"]*"\nCandidate: "*loaded.metadata["run_id"]*"\nDifferent-model differences are not optimality gaps.",
            fontsize = 13,
        )
        save(joinpath(output, "F05-comparison.svg"), compfig)
        save(joinpath(output, "F05-comparison.png"), compfig)
    end
    open(io -> TOML.print(io, config; sorted = true), joinpath(output, "figure-config.toml"), "w")
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("usage: plot_r2.jl RUN_DIR [REFERENCE_DIR]")
    println(plot_r2_run(ARGS[1]; reference = length(ARGS)>1 ? ARGS[2] : nothing))
end
