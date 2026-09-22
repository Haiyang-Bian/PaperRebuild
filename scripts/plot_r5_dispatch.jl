using CairoMakie, CSV, TOML, SHA
function plot_r5_dispatch(dir)
    any(ispath(joinpath(dir, f)) for f in ("F04.png", "F19.png", "figure-config.toml"))&&error(
        "不覆盖IES科学图",
    )
    meta=TOML.parsefile(joinpath(dir, "report.toml"))
    files=[
        "comparison.csv",
        "residuals.csv",
        "dispatch.csv",
        "buildings.csv",
        "pipes.csv",
        "cost-components.csv",
    ]
    summary, residuals, dispatch, buildings, pipes, components=(
        collect(CSV.File(joinpath(dir, f))) for f in files
    )
    set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
    banner="Synthetic deterministic IES | "*meta["batch_id"]
    fig=Figure(size = (1760, 920))
    Label(
        fig[0, 1],
        banner*"\nIndependent residuals / unchanged A1; no candidate is not a zero residual",
        tellwidth = false,
    )
    ax=Axis(
        fig[1, 1],
        ylabel = "Residual / tolerance",
        xticks = (1:length(summary), [replace(x.record_id, "--"=>"\n") for x in summary]),
        xticklabelrotation = pi/3,
        xticklabelsize = 10,
        yscale = log10,
    )
    for (group, color, marker) in (
        ("electric", :steelblue, :circle),
        ("heat", :darkorange, :rect),
        ("comfort", :purple, :utriangle),
        ("delivery", :darkgreen, :diamond),
        ("cost", :brown, :cross),
    )
        values=[
            begin
                rr=filter(z->z.record_id==r.record_id&&z.group==group, residuals)
                isempty(rr) ? NaN : max(1e-12, maximum(z.normalized for z in rr))
            end for r in summary
        ]
        scatter!(ax, 1:length(summary), values; color, marker, markersize = 11, label = group)
    end
    hlines!(ax, [1.0]; color = :black, linestyle = :dash)
    for (i, r) in enumerate(summary)
        r.candidate||text!(
            ax,
            i,
            2.0;
            text = "no candidate",
            rotation = pi/2,
            align = (:left, :center),
            fontsize = 10,
        )
    end
    xlims!(ax, 0.25, length(summary)+0.75)
    ylims!(ax, 1e-13, max(100.0, 10maximum(z.normalized for z in residuals)))
    axislegend(ax; position = :lt, nbanks = 3)
    save(joinpath(dir, "F04.png"), fig)
    fig=Figure(size = (1580, 1180))
    Label(
        fig[0, 1:2],
        banner*"\nAward, delivery and temperature; one known trajectory, not a probability guarantee",
        tellwidth = false,
    )
    power=Axis(
        fig[1, 1],
        title = "Four-period reserve delivery",
        xlabel = "Period",
        ylabel = "MW",
        xticks = 1:4,
    )
    temp=Axis(fig[1, 2], title = "Building comfort", xlabel = "Period", ylabel = "K", xticks = 1:4)
    heat=Axis(
        fig[2, 1],
        title = "Heat actually received by the building",
        xlabel = "Period",
        ylabel = "MW thermal",
        xticks = 1:4,
    )
    bridge=Axis(
        fig[2, 2],
        title = "Same market award; separate physical checks",
        xlabel = "Period",
        ylabel = "Actual PCC import (MW)",
        xticks = 1:4,
    )
    id="four_period--highs"
    rr=sort(filter(x->x.record_id==id, dispatch); by = x->x.t)
    if !isempty(rr)
        for (field, label, color) in (
            (:request_MW, "requested", :steelblue),
            (:delivered_MW, "delivered", :darkorange),
            (:mismatch_MW, "absolute error", :brown),
        )
            scatterlines!(
                power,
                [x.t for x in rr],
                [getproperty(x, field) for x in rr];
                label,
                color,
            )
        end
        bb=sort(filter(x->x.record_id==id, buildings); by = x->x.t)
        scatterlines!(
            temp,
            [x.t for x in bb],
            [x.T_IN_K for x in bb];
            color = :darkgreen,
            label = "room",
        )
        lines!(
            temp,
            [x.t for x in bb],
            [x.T_min_K for x in bb];
            color = :black,
            linestyle = :dash,
            label = "comfort limits",
        )
        lines!(temp, [x.t for x in bb], [x.T_max_K for x in bb]; color = :black, linestyle = :dash)
        for (field, label, color) in
            ((:H_district_MW, "district", :steelblue), (:H_local_MW, "local electric", :darkorange))
            scatterlines!(
                heat,
                [x.t for x in bb],
                [getproperty(x, field) for x in bb];
                label,
                color,
            )
        end
    else
        text!(power, 0.5, 0.5; text = "No candidate", space = :relative)
    end
    for (record, label, color) in (
        ("market_no_call--highs", "no call", :steelblue),
        ("market_up_10percent--highs", "10% up call", :darkgreen),
    )
        rr=sort(filter(x->x.record_id==record, dispatch); by = x->x.t)
        isempty(rr)||scatterlines!(
            bridge,
            [x.t for x in rr],
            [x.P_actual_MW for x in rr];
            label,
            color,
        )
    end
    full=only(filter(x->x.record_id=="market_up_full--highs", summary))
    text!(bridge, 0.03, 0.18; text = "Full up call: "*full.status, space = :relative, fontsize = 13)
    cap=only(filter(x->x.record_id=="capacity_denominator--highs", summary))
    Label(
        fig[3, 1:2],
        "Capacity-denominator example: model=" *
        string(cap.model_pass) *
        " | mismatch=" *
        string(round(cap.mismatch_MWh; digits = 5)) *
        " MWh\nRead requested and delivered energy separately; passing the budget does not mean full delivery.",
        tellwidth = false,
    )
    for ax in (power, temp, heat, bridge)
        axislegend(ax; position = :lt, labelsize = 11)
    end
    save(joinpath(dir, "F19.png"), fig)
    cfg=Dict(
        "schema"=>"r5-dispatch-figures-v1",
        "origin"=>"synthetic",
        "solver_reexecuted"=>false,
        "source_run_ids"=>[x.run_id for x in summary],
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
        "units"=>["MW", "MWh", "K", "residual/tolerance"],
        "batch_id"=>meta["batch_id"],
    )
    open(joinpath(dir, "figure-config.toml"), "w") do io
        TOML.print(io, cfg; sorted = true)
    end
    println("F04/F19 written from saved CSV; no solve.")
end
length(ARGS)==1||error("参数：已有CSV的新绘图目录")
plot_r5_dispatch(only(ARGS))
