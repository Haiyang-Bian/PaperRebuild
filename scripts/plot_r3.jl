using PaperRebuild, CairoMakie, CSV, TOML, SHA

# 图形仅依赖保存的数值和独立验证器，不加载Gurobi或重建优化模型。
function PaperRebuild.plot_r3_run(dir::AbstractString; output = joinpath(dir, "figures"))
    loaded = read_r3_run(dir)
    c, result, reports = loaded.case, loaded.result, loaded.validation.stages
    ispath(output) && error("拒绝覆盖旧图，请指定新输出目录")
    mkdir(output)
    stages, runid = result["stages"], loaded.metadata["run_id"]
    residuals = NamedTuple[]
    for (i, report) in enumerate(reports)
        append!(residuals, [merge((stage = i, name = stages[i]["stage"]), r) for r in report.rows])
    end
    isempty(residuals) || CSV.write(joinpath(output, "F04-source.csv"), residuals)
    fig = Figure(size = (1400, 850), fontsize = 15)
    Label(fig[0, 1:2], "Synthetic R3 | "*runid, fontsize = 17)
    for (col, scope) in enumerate(("model", "physics"))
        ax = Axis(
            fig[1, col];
            title = scope=="model" ? "Adopted stage constraints" : "Unrelaxed physical relations",
            xlabel = "Workflow stage (not algorithm iteration)",
            ylabel = "Residual / A1 tolerance",
            yscale = log10,
            xticks = (1:length(stages), [s["stage"] for s in stages]),
            xticklabelrotation = pi/3,
        )
        for i in eachindex(stages)
            rows=filter(r->r.stage==i && r.scope==scope, residuals)
            isempty(rows) && continue
            scatter!(
                ax,
                fill(i, length(rows)),
                [max(r.residual/r.tolerance, 1e-12) for r in rows];
                color = [r.pass ? :steelblue : :firebrick for r in rows],
                markersize = 7,
            )
        end
        hlines!(ax, [1.0]; color = :black, linestyle = :dash)
        xlims!(ax, 0.5, max(1.5, length(stages)+0.5))
        ratios=[r.residual/r.tolerance for r in residuals if r.scope==scope]
        ylims!(ax, 1e-12, max(10.0, 3maximum(ratios; init = 1.0)))
    end
    Label(
        fig[2, 1:2],
        "Threshold = 1; dots are equation/entity/time checks. No dots = no numerical solution.\nDiagnostic stages are never executable dispatches; raw violations remain in CSV.",
        fontsize = 13,
    )
    save(joinpath(output, "F04-stages.svg"), fig)
    save(joinpath(output, "F04-stages.png"), fig)
    if !isempty(residuals)
        groups=unique((r.scope, r.equation, r.entity) for r in residuals)
        sort!(
            groups;
            by = k->-maximum(
                r.residual/r.tolerance for r in residuals if (r.scope, r.equation, r.entity)==k
            ),
        )
        groups=groups[1:min(24, length(groups))]
        times=sort(unique(r.t for r in residuals))
        cells=[(i, t) for i in eachindex(stages) for t in times]
        values=fill(NaN, length(cells), length(groups))
        for (x, (i, t)) in enumerate(cells), (y, k) in enumerate(groups)
            matches=[
                r.residual/r.tolerance for
                r in residuals if r.stage==i && r.t==t && (r.scope, r.equation, r.entity)==k
            ]
            isempty(matches) || (values[x, y]=log10(max(maximum(matches), 1e-12)))
        end
        detail=Figure(size = (1450, 1050), fontsize = 14)
        Label(detail[0, 1:2], "Synthetic R3 | "*runid, fontsize = 17)
        ax=Axis(
            detail[1, 1];
            title = "Largest 24 equation/entity groups across all stages",
            xlabel = "Stage : time index (0 = aggregate)",
            xticks = (1:length(cells), ["$i:$t" for (i, t) in cells]),
            xticklabelrotation = pi/2,
            yticks = (1:length(groups), [join(k, " / ") for k in groups]),
        )
        hm=heatmap!(
            ax,
            1:length(cells),
            1:length(groups),
            values;
            colormap = [:steelblue, :white, :firebrick],
            colorrange = (-6, 6),
            nan_color = :lightgray,
        )
        Colorbar(detail[1, 2], hm; label = "log10(residual / A1); failure > 0")
        Label(
            detail[2, 1:2],
            "Color clipped at ±6; all groups, original units and thresholds in F04-source.csv. Grey = no numerical row.",
            fontsize = 13,
        )
        save(joinpath(output, "F04-detail.svg"), detail)
        save(joinpath(output, "F04-detail.png"), detail)
    end
    trajectories=NamedTuple[]
    for (i, s) in enumerate(stages)
        haskey(s, "values") || continue
        v=s["values"]
        for key in ("m_pipe", "tau_S_out", "tau_R_out", "H_port"),
            j in eachindex(v[key]),
            t in 1:c.data["T"]

            unit=key=="m_pipe" ? "kg/s" : key=="H_port" ? "MW" : "K"
            push!(
                trajectories,
                (
                    stage = i,
                    name = s["stage"],
                    quantity = key,
                    entity = j,
                    t,
                    time_h = t*c.data["dt_h"],
                    value = v[key][j][t],
                    unit,
                ),
            )
        end
        for side in ("S", "R"), p in eachindex(c.data["heat"]["pipes"]), t in 1:c.data["T"]
            replay=PaperRebuild.r3_mass_replay(c, v, p, t, side)
            push!(
                trajectories,
                (
                    stage = i,
                    name = s["stage"],
                    quantity = "replay_"*side,
                    entity = p,
                    t,
                    time_h = t*c.data["dt_h"],
                    value = replay.out,
                    unit = "K",
                ),
            )
        end
    end
    if haskey(result, "initial_flow")
        for p in eachindex(result["initial_flow"]), t in 1:c.data["T"]
            push!(
                trajectories,
                (
                    stage = 0,
                    name = "input_flow",
                    quantity = "m_pipe",
                    entity = p,
                    t,
                    time_h = t*c.data["dt_h"],
                    value = result["initial_flow"][p][t],
                    unit = "kg/s",
                ),
            )
        end
    end
    if !isempty(trajectories)
        CSV.write(joinpath(output, "F05-source.csv"), trajectories)
        available=findall(s->haskey(s, "values"), stages)
        firststage=isempty(available) ? 0 : first(available)
        laststage=result["final_stage"]>0 ? result["final_stage"] :
                  isempty(available) ? 0 : last(available)
        fig=Figure(size = (1350, 1250), fontsize = 14)
        Label(fig[0, 1:2], "Synthetic R3 | "*runid, fontsize = 17)
        palette=[:steelblue, :darkorange, :seagreen, :purple]
        for (row, key) in enumerate(("m_pipe", "tau_S_out", "tau_R_out", "H_port"))
            unit=key=="m_pipe" ? "kg/s" : key=="H_port" ? "MW" : "K"
            for (col, i) in enumerate((firststage, laststage))
                name=i==0 ? "input only" : stages[i]["stage"]
                title=(col==1 ? "Before: " : "Candidate: ")*name*" | "*key
                ax=Axis(fig[row, col]; title, xlabel = "Time (h)", ylabel = unit)
                rows=filter(r->r.quantity==key && r.stage==i, trajectories)
                for j in unique(r.entity for r in rows)
                    selected=filter(r->r.entity==j, rows)
                    color=palette[mod1(j, length(palette))]
                    scatterlines!(
                        ax,
                        [r.time_h for r in selected],
                        [r.value for r in selected];
                        color,
                        label = "entity $j",
                    )
                    if startswith(key, "tau_")
                        replay=filter(
                            r->r.quantity=="replay_"*key[5:5] && r.stage==i && r.entity==j,
                            trajectories,
                        )
                        lines!(
                            ax,
                            [r.time_h for r in replay],
                            [r.value for r in replay];
                            color,
                            linestyle = :dash,
                            label = "replay $j",
                        )
                    elseif key=="m_pipe" && haskey(result, "initial_flow")
                        initial=filter(
                            r->r.quantity==key && r.stage==0 && r.entity==j,
                            trajectories,
                        )
                        lines!(
                            ax,
                            [r.time_h for r in initial],
                            [r.value for r in initial];
                            color,
                            linestyle = :dot,
                            label = "input $j",
                        )
                    end
                end
                isempty(rows) || axislegend(ax; position = :rt, labelsize = 10)
            end
        end
        Label(
            fig[5, 1:2],
            "Final physical acceptance: "*string(loaded.validation.physical_pass)*" | "*result["status"]*"\nDashed temperatures: independent mass replay; dotted flows: initial schedule. All stage trajectories are in CSV.",
            fontsize = 13,
        )
        save(joinpath(output, "F05-trajectories.svg"), fig)
        save(joinpath(output, "F05-trajectories.png"), fig)
    end
    hashes=Dict(f=>bytes2hex(sha256(read(joinpath(output, f)))) for f in readdir(output))
    config=Dict(
        "origin"=>"synthetic",
        "run_id"=>runid,
        "input_sha256"=>loaded.metadata["input_sha256"],
        "run_sha256"=>loaded.metadata["artifacts"]["run.toml"],
        "CairoMakie"=>string(pkgversion(CairoMakie)),
        "julia"=>string(VERSION),
        "source"=>"saved results and independent mass replay; no solve",
        "F04_floor_ratio"=>1e-12,
        "F04_threshold_ratio"=>1.0,
        "F04_detail_groups"=>24,
        "F04_detail_log10_color_range"=>[-6.0, 6.0],
        "artifacts"=>hashes,
    )
    open(io->TOML.print(io, config; sorted = true), joinpath(output, "figure-config.toml"), "w")
    return output
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (1, 2) || error("usage: plot_r3.jl RUN_DIR [NEW_OUTPUT_DIR]")
    println(plot_r3_run(ARGS[1]; output = length(ARGS)==2 ? ARGS[2] : joinpath(ARGS[1], "figures")))
end
