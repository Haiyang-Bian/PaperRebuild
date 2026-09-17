using PaperRebuild, CairoMakie, CSV, TOML, SHA

# 只读取保存结果；所有图源CSV与图形配置一起交付，不重新求解。
function plot_r3_pg_run(dir; output = joinpath(dir, "pg-figures"))
    loaded=read_r3_run(dir)
    c, r=loaded.case, loaded.result
    r["algorithm"]=="r3_pg_checked_v1" || error("需要PG运行")
    ispath(output) && error("拒绝覆盖旧图；请使用新输出目录")
    mkdir(output)
    runid=loaded.metadata["run_id"]
    iterations=r["iterations"]
    curve=NamedTuple[]
    trials=NamedTuple[]
    residuals=NamedTuple[]
    for row in iterations
        stage=r["stages"][row["stage"]]
        push!(
            curve,
            (
                run_id = runid,
                iteration = row["iteration"],
                mode = row["mode"],
                cost = row["mode"]=="dispatch" ? stage["operating_cost"] : missing,
                diagnostic = row["mode"]=="diagnostic" ? row["merit"] : missing,
                step = get(row, "step", missing),
                projected_gradient = get(row, "projected_gradient_norm", missing),
                accepted = row["accepted"],
                smooth = get(row, "smooth", false),
                active_changed = get(row, "active_set_changed", false),
                elapsed_sec = row["elapsed_sec"],
            ),
        )
        for (j, t) in enumerate(row["trials"])
            haskey(t, "stage") || continue
            st=r["stages"][t["stage"]]
            push!(
                trials,
                (
                    run_id = runid,
                    iteration = row["iteration"],
                    trial = j,
                    kind = t["kind"],
                    mode = t["mode"],
                    accepted = t["accepted"],
                    merit = t["merit"],
                    cost = t["mode"]=="dispatch" ? st["operating_cost"] : missing,
                    step = get(t, "step", missing),
                ),
            )
        end
        for rr in loaded.validation.stages[row["stage"]].rows
            push!(
                residuals,
                merge((run_id = runid, iteration = row["iteration"], stage = row["stage"]), rr),
            )
        end
    end
    if r["final_stage"]>0
        for rr in loaded.validation.stages[r["final_stage"]].rows
            push!(
                residuals,
                merge(
                    (run_id = runid, iteration = length(iterations)+1, stage = r["final_stage"]),
                    rr,
                ),
            )
        end
    end
    isempty(curve) || CSV.write(joinpath(output, "F06-source.csv"), curve)
    isempty(trials) || CSV.write(joinpath(output, "F06-trials.csv"), trials)
    isempty(residuals) || CSV.write(joinpath(output, "F04-source.csv"), residuals)
    fig=Figure(size = (1300, 900), fontsize = 16)
    Label(fig[0, 1:2], "Synthetic PG | $runid | stop: $(r["outer_status"])", fontsize = 18)
    for (pos, field, title, unit, scale) in (
        ((1, 1), :cost, "Feasible subproblem cost", "currency", identity),
        ((1, 2), :diagnostic, "Elastic diagnostic objective", "dimensionless", identity),
        ((2, 1), :step, "Accepted backtracking step", "dimensionless", identity),
        ((2, 2), :projected_gradient, "Projected gradient mapping", "dimensionless", log10),
    )
        ax=Axis(fig[pos...]; title, xlabel = "Outer iteration", ylabel = unit, yscale = scale)
        data=filter(x->!ismissing(getproperty(x, field)) && isfinite(getproperty(x, field)), curve)
        if !isempty(data)
            ys=[
                scale==log10 ? max(getproperty(x, field), 1e-12) : getproperty(x, field) for
                x in data
            ]
            scatterlines!(ax, [x.iteration for x in data], ys; color = :steelblue, markersize = 7)
        end
        if field==:cost
            for tr in trials
                ismissing(tr.cost) && continue
                tr.accepted || scatter!(
                    ax,
                    [tr.iteration+0.02tr.trial],
                    [tr.cost];
                    color = :firebrick,
                    marker = :x,
                    markersize = 7,
                )
            end
        end
        for x in curve
            !x.smooth && vlines!(ax, [x.iteration]; color = (:orange, 0.45), linestyle = :dash)
        end
    end
    Label(
        fig[3, 1:2],
        "Red crosses: rejected cost trials. Orange: transport switch or unavailable derivative.\nCost and elastic objective are different quantities; no global optimality claim.",
        fontsize = 13,
    )
    for ext in ("svg", "png")
        save(joinpath(output, "F06-iterations."*ext), fig)
    end
    fig=Figure(size = (1250, 650), fontsize = 16)
    Label(fig[0, 1:2], "Synthetic PG residuals | $runid", fontsize = 18)
    for (j, scope) in enumerate(("model", "physics"))
        ax=Axis(
            fig[1, j];
            title = scope,
            xlabel = "Outer iterate; last point = final physical candidate",
            ylabel = "Residual / A1 tolerance",
            yscale = log10,
        )
        data=filter(x->x.scope==scope, residuals)
        for k in unique(x.iteration for x in data)
            rr=filter(x->x.iteration==k, data)
            scatter!(
                ax,
                [k],
                [max(1e-12, maximum(x.residual/x.tolerance for x in rr))];
                color = all(x.pass for x in rr) ? :steelblue : :firebrick,
            )
        end
        hlines!(ax, [1.0]; color = :black, linestyle = :dash)
    end
    Label(
        fig[2, 1:2],
        "Raw pressure/cone residuals remain visible; reconstruction and final dispatch are separate saved stages.",
        fontsize = 13,
    )
    for ext in ("svg", "png")
        save(joinpath(output, "F04-residuals."*ext), fig)
    end
    ids=Int[]
    !isempty(iterations) &&
        haskey(r["stages"][first(iterations)["stage"]], "values") &&
        push!(ids, first(iterations)["stage"])
    r["final_stage"]>0 && push!(ids, r["final_stage"])
    trajectories=NamedTuple[]
    for (k, id) in enumerate(unique(ids))
        st=r["stages"][id]
        v=st["values"]
        for (p, pipe) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"], side in ("S", "R")
            replay=PaperRebuild.r3_mass_replay(c, v, p, t, side)
            push!(
                trajectories,
                (
                    run_id = runid,
                    stage = id,
                    label = id==r["final_stage"] ? "verified final" :
                            "initial subproblem / diagnostic",
                    pipe = p,
                    side,
                    time_h = t*c.data["dt_h"],
                    flow_kg_s = v["m_pipe"][p][t],
                    outlet_K = v["tau_"*side*"_out"][p][t],
                    replay_K = replay.out,
                    heat_MW = v["H_port"][pipe["to"]][t],
                ),
            )
        end
    end
    if !isempty(trajectories)
        CSV.write(joinpath(output, "F05-source.csv"), trajectories)
        fig=Figure(size = (1350, 500), fontsize = 15)
        Label(fig[0, 1:3], "Synthetic PG trajectories | $runid", fontsize = 18)
        for (j, field, unit) in ((1, :flow_kg_s, "kg/s"), (2, :outlet_K, "K"), (3, :heat_MW, "MW"))
            ax=Axis(fig[1, j]; xlabel = "Time (h)", ylabel = unit, title = string(field))
            for id in unique(x.stage for x in trajectories),
                p in unique(x.pipe for x in trajectories)

                dd=filter(x->x.stage==id && x.pipe==p && x.side=="S", trajectories)
                scatterlines!(
                    ax,
                    [x.time_h for x in dd],
                    [getproperty(x, field) for x in dd];
                    label = "$(first(dd).label) p$p",
                )
                field==:outlet_K && lines!(
                    ax,
                    [x.time_h for x in dd],
                    [x.replay_K for x in dd];
                    linestyle = :dash,
                    label = "mass replay p$p",
                )
            end
            axislegend(ax; position = :lt, labelsize = 10)
        end
        for ext in ("svg", "png")
            save(joinpath(output, "F05-trajectories."*ext), fig)
        end
    end
    open(joinpath(output, "figure-config.toml"), "w") do io
        TOML.print(
            io,
            Dict(
                "origin"=>"synthetic",
                "run_id"=>runid,
                "renderer"=>"CairoMakie",
                "run_sha256"=>bytes2hex(sha256(read(joinpath(dir, "run.toml")))),
                "figures"=>["F04", "F05", "F06"],
                "reoptimized"=>false,
            );
            sorted = true,
        )
    end
    return output
end
