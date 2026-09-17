# 从可审计CSV重绘；不加载求解器，不重新运行优化。
using CSV, CairoMakie, TOML, SHA, Dates
function main()
    length(ARGS)==1 || error("usage: plot_r3_baseline.jl REPORT_DIRECTORY")
    dir=only(ARGS)
    dest=joinpath(dir, "figures-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
    ispath(dest) && error("拒绝覆盖旧图")
    mkdir(dest)
    comparison=collect(CSV.File(joinpath(dir, "comparison.csv")))
    stages=collect(CSV.File(joinpath(dir, "F04-stages.csv")))
    trajectory=collect(CSV.File(joinpath(dir, "F05-source.csv")))
    curves=collect(CSV.File(joinpath(dir, "F06-source.csv")))
    stops=collect(CSV.File(joinpath(dir, "stopping.csv")))
    trials=collect(CSV.File(joinpath(dir, "F06-trials.csv")))
    shortid=basename(dir)
    function savefig(name, fig)
        save(joinpath(dest, name*".png"), fig)
        save(joinpath(dest, name*".svg"), fig)
    end
    f=Figure(size = (1550, 1050), fontsize = 13)
    Label(f[0, 1:2], "Synthetic inputs | "*shortid, fontsize = 15)
    for (col, name) in enumerate(("single-source", "two-source"))
        selected=filter(x->x.case_group==name, comparison)
        ax=Axis(
            f[1, col],
            title = name*": selected physical or best model candidate",
            xlabel = "Residual / unchanged A1 tolerance",
            xscale = log10,
            yticks = (1:length(selected), [replace(x.id, name*"-"=>"") for x in selected]),
        )
        for (i, r) in enumerate(selected)
            r.selected_stage==0 && continue
            stage=only(x for x in stages if x.id==r.id && x.stage==r.selected_stage)
            scatter!(ax, [max(stage.model_ratio, 1e-12)], [i]; color = :steelblue, marker = :circle)
            scatter!(
                ax,
                [max(stage.physics_ratio, 1e-12)],
                [i];
                color = :firebrick,
                marker = :diamond,
            )
        end
        vlines!(ax, [1]; color = :black, linestyle = :dash)
    end
    Label(
        f[2, 1:2],
        "Blue: model; red: original physics incl. terminal state. No point: no candidate. Threshold = 1.",
        fontsize = 13,
    )
    savefig("F04-comparison", f)
    colors=[:steelblue, :darkorange, :seagreen]
    for name in ("single-source", "two-source")
        f=Figure(size = (1350, 1100), fontsize = 14)
        Label(f[0, 1:3], "Synthetic VF-CT | "*name*" | "*shortid, fontsize = 14)
        for (col, boundary) in enumerate(("legacy_tail", "bounded_return_tail", "core_only"))
            ax=Axis(
                f[1, col],
                title = boundary,
                xlabel = "Time (h)",
                ylabel = "Load return temperature (K)",
            )
            bx=Axis(f[2, col], xlabel = "Time (h)", ylabel = "Delivered heat (MW)")
            cx=Axis(f[3, col], xlabel = "Time (h)", ylabel = "Delivered heat minus demand (W)")
            for (method, style) in
                (("physical", :solid), ("normalized", :dash), ("reference", :dot))
                id=name*"-"*boundary*"-"*method
                row=only(x for x in comparison if x.id==id)
                row.selected_stage==0 && continue
                points=filter(x->x.id==id && x.stage==row.selected_stage, trajectory)
                for node in unique(x.node for x in points)
                    p=sort(filter(x->x.node==node, points); by = x->x.t)
                    label=method*" n"*string(node)*(row.physical_pass ? " A1" : " model only")
                    lines!(
                        ax,
                        [x.time_h for x in p],
                        [x.return_K for x in p];
                        label,
                        linestyle = style,
                        color = colors[node%3+1],
                    )
                    lines!(
                        bx,
                        [x.time_h for x in p],
                        [x.delivered_MW for x in p];
                        label,
                        linestyle = style,
                        color = colors[node%3+1],
                    )
                    lines!(
                        cx,
                        [x.time_h for x in p],
                        [x.delivery_error_W for x in p];
                        label,
                        linestyle = style,
                        color = colors[node%3+1],
                    )
                end
            end
            # 核心时域共同为四个1h时段；分界由图源tail字段确定。
            tail=filter(x->startswith(x.id, name*"-"*boundary)&&x.tail, trajectory)
            isempty(tail) || (
                vlines!(
                    ax,
                    [minimum(x.time_h for x in tail)-0.5];
                    color = :gray,
                    linestyle = :dash,
                );
                vlines!(
                    bx,
                    [minimum(x.time_h for x in tail)-0.5];
                    color = :gray,
                    linestyle = :dash,
                )
            )
            hlines!(cx, [-3, 3]; color = :black, linestyle = :dash)
            axislegend(ax; position = :rb, labelsize = 10)
        end
        Label(
            f[4, 1:3],
            "Line labels retain A1 status; core_only has no terminal restoration requirement. Source: F05-source.csv.",
            fontsize = 12,
        )
        savefig("F05-"*name, f)
    end
    for name in ("single-source", "two-source")
        f=Figure(size = (1550, 1100), fontsize = 13)
        Label(
            f[0, 1:3],
            "Synthetic real accepted trajectories | "*name*" | "*shortid,
            fontsize = 14,
        )
        groups=(
            ("initialization", "Five frozen starts"),
            ("boundary", "VF-CT boundaries"),
            ("step", "SCHPD step sensitivity"),
        )
        for (col, (group, title)) in enumerate(groups)
            field=group=="boundary" ? :core_cost : :cost
            ax=Axis(
                f[1, col];
                title,
                xlabel = "Accepted updates (initial = 0)",
                ylabel = group=="boundary" ? "Common core cost (currency)" :
                         "Operating cost (currency)",
            )
            bx=Axis(
                f[2, col],
                xlabel = "Outer trial sequence",
                ylabel = "Unprojected scalar step gamma",
                yscale = log10,
            )
            chosen=filter(
                x->x.case_group==name &&
                   (x.group==group || group=="step" && x.id==name*"-schpd-physical"),
                comparison,
            )
            for (i, r) in enumerate(chosen)
                p=filter(x->x.id==r.id && isfinite(x.cost), curves)
                label=replace(r.id, name*"-"=>"")
                isempty(p) || scatterlines!(
                    ax,
                    [x.update for x in p],
                    [getproperty(x, field) for x in p];
                    label,
                    markersize = 3,
                )
                ev=filter(x->x.id==r.id, stops)
                # CSV列名保留原ε字符串；通过原始Symbol读取。
                for (eps, marker) in (("1.0e-6", :circle), ("0.0001", :rect), ("0.01", :utriangle))
                    hit=findfirst(
                        x->!ismissing(getproperty(x, Symbol("paper_form_epsilon_"*eps))) &&
                           getproperty(x, Symbol("paper_form_epsilon_"*eps)),
                        ev,
                    )
                    if !isnothing(hit)
                        point=only(x for x in p if x.update==ev[hit].iteration)
                        scatter!(
                            ax,
                            [point.update],
                            [getproperty(point, field)];
                            color = :black,
                            marker,
                            markersize = 9,
                        )
                    end
                end
                tr=filter(x->x.id==r.id && isfinite(x.gamma)&&x.gamma>0, trials)
                isempty(tr) || lines!(bx, 1:length(tr), [x.gamma for x in tr]; label)
                bad=findall(x->!x.accepted, tr)
                isempty(bad) || scatter!(
                    bx,
                    bad,
                    [tr[j].gamma for j in bad];
                    color = :firebrick,
                    marker = :x,
                    markersize = 6,
                )
            end
            axislegend(ax; position = :rt, labelsize = 9)
        end
        Label(
            f[3, 1:3],
            "Black o / square / triangle: first absolute cost change <= 1e-6 / 1e-4 / 1e-2. Red x: rejected trial. No artificial continuation.",
            fontsize = 12,
        )
        savefig("F06-"*name, f)
    end
    inputs=Dict(
        f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in (
            "comparison.csv",
            "F04-stages.csv",
            "F05-source.csv",
            "F06-source.csv",
            "F06-trials.csv",
            "stopping.csv",
            "provenance.toml",
        )
    )
    open(joinpath(dest, "figure-config.toml"), "w") do io
        TOML.print(
            io,
            Dict(
                "origin"=>"synthetic",
                "report_id"=>shortid,
                "inputs"=>inputs,
                "renderer_sha256"=>bytes2hex(sha256(read(@__FILE__))),
                "units"=>["K", "h", "kg/s", "MW", "W", "currency", "dimensionless"],
            );
            sorted = true,
        )
    end
    println(dest)
end
main()
