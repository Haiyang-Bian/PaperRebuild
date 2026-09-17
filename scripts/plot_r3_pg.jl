using PaperRebuild, CairoMakie, CSV, TOML, SHA

# 只读取保存结果；所有图源CSV与图形配置一起交付，不重新求解。
function plot_r3_pg_run(dir; output = joinpath(dir, "pg-figures"), loaded = read_r3_run(dir))
    c, r=loaded.case, loaded.result
    r["algorithm"] in
    ("r3_pg_checked_v1", "r3_pg_checked_v2", "r3_pg_checked_v3", "r3_cost_reference_v1") ||
        error("需要R3外层或参考运行")
    ispath(output) && error("拒绝覆盖旧图；请使用新输出目录")
    mkdir(output)
    runid=basename(dirname(abspath(dir)))*"/"*loaded.metadata["run_id"]
    iterations=get(r, "iterations", Any[])
    curve=NamedTuple[]
    trials=NamedTuple[]
    local_trials=NamedTuple[]
    residuals=NamedTuple[]
    for row in iterations
        stage=r["stages"][row["stage"]]
        accepted=findfirst(t->get(t, "accepted", false), row["trials"])
        accepted_step=isnothing(accepted) ? missing : get(row["trials"][accepted], "step", missing)
        radii=[tr["local"]["radius"] for tr in row["trials"] if haskey(tr, "local")]
        push!(
            curve,
            (
                run_id = runid,
                iteration = row["iteration"],
                mode = row["mode"],
                cost = row["mode"]=="dispatch" ? stage["operating_cost"] : missing,
                diagnostic = row["mode"]=="diagnostic" ? row["merit"] : missing,
                step = get(row, "step", accepted_step),
                projected_gradient = get(row, "projected_gradient_norm", missing),
                accepted = row["accepted"],
                smooth = get(row, "smooth", isempty(get(row, "switches", String[]))),
                local_direction = get(row, "local_direction_norm", missing),
                trust_radius = isempty(radii) ? missing : maximum(radii),
                active_changed = get(row, "active_set_changed", false),
                elapsed_sec = row["elapsed_sec"],
            ),
        )
        seen_projections=Set{String}()
        for (j, t) in enumerate(row["trials"])
            if haskey(t, "local")
                local_result=t["local"]
                push!(
                    local_trials,
                    (
                        run_id = runid,
                        iteration = row["iteration"],
                        trial = j,
                        status = local_result["status"],
                        radius = local_result["radius"],
                        accepted = t["accepted"],
                        direction = get(local_result, "direction_norm", missing),
                        prediction = get(t, "prediction", missing),
                        ratio = get(t, "ratio", missing),
                        reason = get(t, "reason", ""),
                        switches = join(get(local_result, "switches", String[]), ";"),
                    ),
                )
            end
            if haskey(t, "projection") && haskey(t["projection"], "values")
                p=t["projection"]
                key=repr(p["flow"])
                if !(key in seen_projections)
                    push!(seen_projections, key)
                    witness=Dict{String,Any}(
                        "input_sha256"=>c.sha256,
                        "values"=>p["values"],
                        "spec"=>PaperRebuild.r2_spec_dict(R2Spec()),
                        "fixed_flows"=>false,
                        "objective"=>PaperRebuild.r3_operating_cost(c, p["values"]),
                    )
                    if haskey(r, "operation")
                        witness["operation"]=r["operation"]
                        witness["operation_sha256"]=r["operation_sha256"]
                    end
                    omitted=("3-17", "3-27", "3-28", "3-30", "3-31", "3-33:34", "3-35:36")
                    for rr in validate_r2_solution(c, witness).rows
                        rr.scope=="model" && !(rr.equation in omitted) || continue
                        push!(
                            residuals,
                            merge(
                                (
                                    run_id = runid,
                                    iteration = row["iteration"],
                                    stage = row["stage"],
                                ),
                                rr,
                                (scope = "projection", entity = "trial$j:"*rr.entity),
                            ),
                        )
                    end
                end
            end
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
    if isempty(iterations)
        for (i, report) in enumerate(loaded.validation.stages), rr in report.rows
            push!(residuals, merge((run_id = runid, iteration = i, stage = i), rr))
        end
    elseif r["final_stage"]>0
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
    isempty(local_trials) || CSV.write(joinpath(output, "F06-local-trials.csv"), local_trials)
    isempty(residuals) || CSV.write(joinpath(output, "F04-source.csv"), residuals)
    fig=Figure(size = (1300, 1150), fontsize = 16)
    Label(fig[0, 1:2], "Synthetic PG | $runid | stop: $(r["outer_status"])", fontsize = 18)
    for (pos, field, title, unit, scale) in (
        ((1, 1), :cost, "Feasible subproblem cost", "currency", identity),
        ((1, 2), :diagnostic, "Elastic diagnostic objective", "dimensionless", identity),
        ((2, 1), :step, "Accepted backtracking step", "dimensionless", identity),
        ((2, 2), :projected_gradient, "Projected gradient mapping", "dimensionless", log10),
        (
            (3, 1),
            :local_direction,
            "Primal local direction (separate metric)",
            "dimensionless",
            log10,
        ),
        ((3, 2), :trust_radius, "Local trust radius", "dimensionless", identity),
    )
        ax=Axis(fig[pos...]; title, xlabel = "Outer iteration", ylabel = unit, yscale = scale)
        data=filter(x->!ismissing(getproperty(x, field)) && isfinite(getproperty(x, field)), curve)
        if !isempty(data)
            ys=[
                scale==log10 ? max(getproperty(x, field), 1e-12) : getproperty(x, field) for
                x in data
            ]
            # 先固定全体数据的对数范围，避免单点诊断序列触发过窄的自动缩放。
            if scale==log10
                ylims!(ax, minimum(ys)/2, maximum(ys)*2)
                ax.ytickformat=values->string.(round.(values; sigdigits = 3))
            elseif field==:cost && maximum(ys)-minimum(ys)<1e-8*max(1, maximum(abs, ys))
                center=(minimum(ys)+maximum(ys))/2
                pad=1e-6*max(1, abs(center))
                ylims!(ax, center-pad, center+pad)
            end
            for mode in unique(x.mode for x in data)
                indices=findall(x->x.mode==mode, data)
                scatterlines!(
                    ax,
                    [data[i].iteration for i in indices],
                    ys[indices];
                    color = mode=="diagnostic" ? :darkorange : :steelblue,
                    markersize = 7,
                    label = mode,
                )
            end
            field in (:step, :projected_gradient) && axislegend(ax; position = :rt, labelsize = 11)
        end
        if field in (:cost, :diagnostic)
            rejected_x=Float64[]
            rejected_y=Float64[]
            for tr in trials
                value=field==:cost ? tr.cost : tr.mode=="diagnostic" ? tr.merit : missing
                (ismissing(value) || !isfinite(value) || tr.accepted) && continue
                push!(rejected_x, tr.iteration+0.02tr.trial)
                push!(rejected_y, value)
            end
            isempty(rejected_x) || scatter!(
                ax,
                rejected_x,
                rejected_y;
                color = :firebrick,
                marker = :x,
                markersize = 7,
            )
        end
        if field==:trust_radius && !isempty(local_trials)
            scatter!(
                ax,
                [t.iteration+0.02t.trial for t in local_trials],
                [t.radius for t in local_trials];
                color = [t.accepted ? :seagreen : :firebrick for t in local_trials],
                markersize = 4,
            )
        end
        switches=[x.iteration for x in curve if !x.smooth]
        isempty(switches) || vlines!(ax, switches; color = (:orange, 0.45), linestyle = :dash)
    end
    Label(
        fig[4, 1:2],
        "Red crosses: rejected trials. Orange: transport switch or unavailable derivative.\nCost and elastic objective are different quantities; no global optimality claim.",
        fontsize = 13,
    )
    for ext in (isempty(iterations) ? String[] : ["svg", "png"])
        save(joinpath(output, "F06-iterations."*ext), fig)
    end
    fig=Figure(size = (1500, 650), fontsize = 16)
    Label(fig[0, 1:3], "Synthetic R3 residuals | $runid", fontsize = 18)
    for (j, scope) in enumerate(("model", "physics", "projection"))
        ax=Axis(
            fig[1, j];
            title = scope,
            xlabel = scope=="projection" ? "Outer iteration (projected trial)" :
                     isempty(iterations) ? "Workflow stage (no outer iterations)" :
                     r["final_stage"]>0 ? "Outer iterate; last point = verified final" :
                     "Outer iterate; no verified final candidate",
            ylabel = "Residual / A1 tolerance",
            yscale = log10,
        )
        data=filter(x->x.scope==scope, residuals)
        xx=Int[]
        yy=Float64[]
        colors=Symbol[]
        for k in unique(x.iteration for x in data)
            rr=filter(x->x.iteration==k, data)
            push!(xx, k)
            push!(yy, max(1e-12, maximum(x.residual/x.tolerance for x in rr)))
            push!(colors, all(x.pass for x in rr) ? :steelblue : :firebrick)
        end
        isempty(xx) || scatter!(ax, xx, yy; color = colors)
        hlines!(ax, [1.0]; color = :black, linestyle = :dash)
    end
    Label(
        fig[2, 1:3],
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
    if r["final_stage"]==0 && get(r, "best_subproblem_stage", 0)>0
        push!(ids, r["best_subproblem_stage"])
    end
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
                            id==get(r, "best_subproblem_stage", 0) && r["final_stage"]==0 ?
                            "unverified best subproblem" : "initial subproblem / diagnostic",
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
        fig=Figure(size = (1350, 600), fontsize = 15)
        Label(fig[0, 1:3], "Synthetic R3 trajectories | $runid", fontsize = 18)
        for (j, field, unit) in ((1, :flow_kg_s, "kg/s"), (2, :outlet_K, "K"), (3, :heat_MW, "MW"))
            ax=Axis(fig[1, j]; xlabel = "Time (h)", ylabel = unit, title = string(field))
            if field==:outlet_K
                ylims!(ax, c.data["heat"]["S_bounds_K"]...)
            elseif field==:flow_kg_s
                ylims!(
                    ax,
                    0.95minimum(p["flow_min"] for p in c.data["heat"]["pipes"]),
                    1.05maximum(p["flow_max"] for p in c.data["heat"]["pipes"]),
                )
            end
            if haskey(r, "operation") && r["operation"]["core_periods"]<c.data["T"]
                vlines!(
                    ax,
                    [r["operation"]["core_periods"]*c.data["dt_h"]];
                    color = :gray,
                    linestyle = :dot,
                )
            end
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
            Legend(fig[2, j], ax; labelsize = 10, tellwidth = false, tellheight = true)
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
                "figures"=>(isempty(iterations) ? ["F04", "F05"] : ["F04", "F05", "F06"]),
                "reoptimized"=>false,
                "renderer_script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            );
            sorted = true,
        )
    end
    return output
end
