# 读取已保存CSV，绝不重新求解。
include("r4_setup.jl")
using CairoMakie, CSV, SHA
function main()
    length(ARGS)==1 || error("参数：新报告目录")
    dir=only(ARGS)
    meta=TOML.parsefile(joinpath(dir, "report.toml"))
    rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
    outer=collect(CSV.File(joinpath(dir, "outer.csv")))
    inner=collect(CSV.File(joinpath(dir, "inner.csv")))
    res=collect(CSV.File(joinpath(dir, "residuals.csv")))
    contracts=collect(CSV.File(joinpath(dir, "contracts.csv")))
    any(
        isfile(joinpath(dir, x)) for x in ("F04.png", "F10.png", "F11.png", "figure-config.toml")
    ) && error("不覆盖图表")
    set_theme!(Theme(font = "DejaVu Sans", fontsize = 14))
    names=["open_flexible", "open_fixed", "import_flexible", "import_fixed"]
    fig=Figure(size = (1300, 900))
    Label(
        fig[0, 1:2],
        "Synthetic R4 | "*meta["batch"]*"\nF11  True outer trajectories, fixed battery states (Clarabel)",
        tellwidth = false,
    )
    for (i, name) in enumerate(names)
        ax=Axis(
            fig[i, 1],
            title = name,
            ylabel = "Consensus residual",
            yscale = log10,
            xlabel = "Outer iteration",
        )
        bx=Axis(fig[i, 2], ylabel = "Resource cost (synthetic USD)", xlabel = "Outer iteration")
        for p in 1:2
            rr=filter(x->x.case==name&&x.pattern==p&&x.solver=="clarabel", outer)
            isempty(rr) && continue
            color=p==1 ? :steelblue : :darkorange
            lines!(
                ax,
                [x.iteration for x in rr],
                max.(1e-12, [x.primal for x in rr]);
                color,
                label = "p$(p) primal",
            )
            lines!(
                ax,
                [x.iteration for x in rr],
                max.(1e-12, [x.dual for x in rr]);
                color,
                linestyle = :dash,
                label = "p$(p) dual",
            )
            lines!(
                bx,
                [x.iteration for x in rr],
                [x.cost for x in rr];
                color,
                label = "p$(p) distributed",
            )
            hlines!(bx, [first(rr).reference_cost]; color, linestyle = :dash)
        end
        hlines!(ax, [1e-4]; color = :black, linestyle = :dot)
        i==1 && axislegend(ax; position = :rt, labelsize = 10)
    end
    Label(
        fig[5, 1:2],
        "Dashed cost: same-model central reference. Before consensus/A1, cost is not an executable dispatch.\nA4 residual 1e-4 does not replace A1. Full run IDs and units are in outer.csv.",
        tellwidth = false,
    )
    save(joinpath(dir, "F11.png"), fig)
    fig=Figure(size = (1380, 780))
    Label(
        fig[0, 1],
        "Synthetic R4 | "*meta["batch"]*"\nF04  Final candidate residuals relative to frozen A1 thresholds",
        tellwidth = false,
    )
    ids=[x.run_id for x in rows]
    ax=Axis(
        fig[1, 1],
        xscale = log10,
        xlabel = "Maximum residual / A1 tolerance (1 = threshold)",
        yticks = (1:length(ids), ids),
    )
    sources=NamedTuple[]
    for (j, kind) in enumerate(("adopted_model", "electric_original"))
        xx=Float64[]
        yy=Float64[]
        for (i, id) in enumerate(ids)
            rr=filter(
                x->x.run_id==id&&(
                    kind=="electric_original" ? x.scope=="electric_original" :
                    x.scope!="electric_original"
                ),
                res,
            )
            isempty(rr) && continue
            ratio=maximum(x.residual/x.tolerance for x in rr)
            push!(sources, (run_id = id, kind, ratio, threshold = 1.0))
            push!(xx, max(1e-12, ratio))
            push!(yy, i+(j==1 ? -0.12 : 0.12))
        end
        scatter!(ax, xx, yy; color = j==1 ? :steelblue : :darkorange, label = kind)
    end
    vlines!(ax, [1.0]; color = :black, linestyle = :dash)
    axislegend(ax; position = :lb)
    Label(
        fig[2, 1],
        "AGNB has no network; orange markers are only applicable to SWM. Display floor 1e-12; raw data unchanged.",
        tellwidth = false,
    )
    save(joinpath(dir, "F04.png"), fig)
    CSV.write(joinpath(dir, "F04-source.csv"), sources)
    fig=Figure(size = (1220, 820))
    Label(
        fig[0, 1:2],
        "Synthetic R4 | "*meta["batch"]*"\nF10  Nonzero AGNB bilateral contracts and inner convergence (Clarabel)",
        tellwidth = false,
    )
    for (i, name) in enumerate(names)
        ax=Axis(fig[i, 1], title = name, xlabel = "Core hour", ylabel = "A peer export (MW)")
        bx=Axis(
            fig[i, 2],
            yscale = log10,
            xlabel = "Inner iteration",
            ylabel = "Consensus residual",
        )
        for p in 1:2
            id=name*"--p$(p)--agnb--clarabel"
            for (j, carrier) in enumerate(("P", "H"))
                rr=sort(
                    filter(x->x.run_id==id&&x.actor==2&&x.carrier==carrier, contracts);
                    by = x->x.t,
                )
                color=carrier=="P" ? :steelblue : :darkorange
                isempty(rr) || lines!(
                    ax,
                    [x.t for x in rr],
                    [x.peer_export_MW for x in rr];
                    color,
                    linestyle = p==1 ? :solid : :dash,
                    label = carrier*" p$(p)",
                )
            end
            rr=filter(x->x.run_id==id, inner)
            if !isempty(rr)
                lines!(
                    bx,
                    [x.inner_iteration for x in rr],
                    max.(1e-12, [max(x.primal, x.dual) for x in rr]);
                    label = "p$(p)",
                )
            end
        end
        hlines!(bx, [1e-7]; color = :black, linestyle = :dot)
        i==1 && axislegend(ax; labelsize = 10, position = :rb)
    end
    Label(
        fig[5, 1:2],
        "Contracts are not branch flows. AGNB ignores the network; no physical feasibility claim.\nRaw values, including numerical near-zero contracts, are retained in contracts.csv.",
        tellwidth = false,
    )
    save(joinpath(dir, "F10.png"), fig)
    files=[
        "comparison.csv",
        "outer.csv",
        "inner.csv",
        "residuals.csv",
        "contracts.csv",
        "F04-source.csv",
    ]
    write(
        joinpath(dir, "figure-config.toml"),
        PaperRebuild.r4_text(
            Dict(
                "batch"=>meta["batch"],
                "origin"=>"synthetic",
                "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
                "source_sha256"=>Dict(x=>bytes2hex(sha256(read(joinpath(dir, x)))) for x in files),
                "display_floor"=>1e-12,
                "solver_for_trajectory_panels"=>"clarabel",
            ),
        ),
    )
    println("F04, F10 and F11 drawn from saved data.")
end
main()
