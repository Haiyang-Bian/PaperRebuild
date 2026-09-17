using PaperRebuild, CairoMakie, CSV, TOML, SHA
include("plot_r3_pg.jl")

# 保存数据驱动：不重新求解；恢复横轴与外层迭代明确分开。
function plot_r3_v3_run(dir; output = joinpath(dir, "v3-figures"), loaded = read_r3_run(dir))
    plot_r3_pg_run(dir; output, loaded)
    c, r=loaded.case, loaded.result
    trace=get(get(r, "physical_restoration", Dict()), "trace", Any[])
    curve=NamedTuple[]
    residuals=NamedTuple[]
    trajectories=NamedTuple[]
    runid=basename(dirname(abspath(dir)))*"/"*loaded.metadata["run_id"]
    for (i, row) in enumerate(trace)
        push!(
            curve,
            (
                run_id = runid,
                trial = i,
                update = row["update"],
                radius = row["radius"],
                before = row["before"],
                after = get(row, "after", missing),
                predicted = get(row, "predicted", missing),
                ratio = get(row, "ratio", missing),
                accepted = row["accepted"],
                termination = get(row, "termination", ""),
                reason = get(row, "reason", ""),
            ),
        )
        haskey(row, "candidate") || continue
        s=row["candidate"]
        v=validate_r3_solution(c, s)
        append!(
            residuals,
            [
                merge(
                    (
                        run_id = runid,
                        trial = i,
                        update = row["update"],
                        accepted = row["accepted"],
                        physical_pass = v.physical_pass,
                    ),
                    x,
                ) for x in v.rows
            ],
        )
        for t in 1:c.data["T"]
            for (p, pipe) in enumerate(c.data["heat"]["pipes"])
                vals=s["values"]
                replay=PaperRebuild.r3_mass_replay(c, vals, p, t, "S")
                push!(
                    trajectories,
                    (
                        run_id = runid,
                        trial = i,
                        update = row["update"],
                        accepted = row["accepted"],
                        physical_pass = v.physical_pass,
                        pipe = p,
                        time_h = t*c.data["dt_h"],
                        flow_kg_s = vals["m_pipe"][p][t],
                        supply_out_K = vals["tau_S_out"][p][t],
                        replay_out_K = replay.out,
                        heat_MW = vals["H_port"][pipe["to"]][t],
                        grid_MW = vals["P_grid"][t],
                    ),
                )
            end
        end
    end
    if !isempty(curve)
        CSV.write(joinpath(output, "F06-restoration-source.csv"), curve)
        isempty(residuals) || CSV.write(joinpath(output, "F04-restoration-source.csv"), residuals)
        isempty(trajectories) ||
            CSV.write(joinpath(output, "F05-restoration-source.csv"), trajectories)
        fig=Figure(size = (1400, 500), fontsize = 14)
        Label(fig[0, 1:3], "Synthetic local physical restoration | "*runid, fontsize = 16)
        for (j, field, title) in (
            (1, :after, "True normalized physical violation"),
            (2, :radius, "Trust radius"),
            (3, :ratio, "Actual / predicted decrease"),
        )
            ax=Axis(
                fig[1, j];
                xlabel = "Restoration trial (not outer iteration)",
                ylabel = "dimensionless",
                title,
            )
            rows=[
                x for
                x in curve if !ismissing(getproperty(x, field)) && isfinite(getproperty(x, field))
            ]
            isempty(rows) || scatterlines!(
                ax,
                [x.trial for x in rows],
                [getproperty(x, field) for x in rows];
                color = :steelblue,
            )
            if field==:ratio
                hlines!(ax, [0.1]; color = :black, linestyle = :dash)
            end
            bad=filter(x->!x.accepted, rows)
            isempty(bad) || scatter!(
                ax,
                [x.trial for x in bad],
                [getproperty(x, field) for x in bad];
                color = :firebrick,
                marker = :x,
            )
        end
        Label(
            fig[2, 1:3],
            "Intermediate restoration points are not feasible dispatches; A1 is checked separately.",
            fontsize = 12,
        )
        for ext in ("png", "svg")
            save(joinpath(output, "F06-restoration."*ext), fig)
        end
        if !isempty(residuals)
            f=Figure(size = (1000, 450), fontsize = 14)
            ax=Axis(
                f[1, 1];
                xlabel = "Restoration trial",
                ylabel = "Residual / A1 tolerance",
                yscale = log10,
                title = "Synthetic physical restoration | "*runid,
            )
            for scope in ("model", "physics")
                points=[
                    (
                        i,
                        maximum(
                            x.residual/x.tolerance for
                            x in residuals if x.trial==i && x.scope==scope
                        ),
                    ) for i in unique(x.trial for x in residuals)
                ]
                scatterlines!(ax, first.(points), max.(1e-12, last.(points)); label = scope)
            end
            hlines!(ax, [1.0]; color = :black, linestyle = :dash)
            axislegend(ax)
            save(joinpath(output, "F04-restoration.png"), f)
            save(joinpath(output, "F04-restoration.svg"), f)
        end
    end
    config=TOML.parsefile(joinpath(output, "figure-config.toml"))
    config["restoration_trials"]=length(trace)
    config["local_stationarity_checked"]=get(r, "local_stationarity_checked", false)
    config["v3_renderer_sha256"]=bytes2hex(sha256(read(@__FILE__)))
    open(io->TOML.print(io, config; sorted = true), joinpath(output, "figure-config.toml"), "w")
    return output
end
