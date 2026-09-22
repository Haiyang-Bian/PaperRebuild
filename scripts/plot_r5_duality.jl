using CairoMakie, CSV, TOML, SHA
function plot_r5_duality(dir)
    any(ispath(joinpath(dir, f)) for f in ("F04.png", "figure-config.toml"))&&error("不覆盖对偶图")
    summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
    rows=collect(CSV.File(joinpath(dir, "kkt-residuals.csv")))
    meta=TOML.parsefile(joinpath(dir, "audit.toml"))
    set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
    fig=Figure(size = (1720, 930))
    Label(
        fig[0, 1],
        "Synthetic fixed-award IES | read-only KKT audit of " *
        meta["parent_batch"] *
        "\nRaw multipliers unchanged; tolerance line = 1; no candidate means no gradient",
        tellwidth = false,
    )
    ax=Axis(
        fig[1, 1],
        ylabel = "Residual / tolerance",
        yscale = log10,
        xticks = (1:length(summary), [replace(x.record_id, "--"=>"\n") for x in summary]),
        xticklabelrotation = pi/3,
        xticklabelsize = 10,
    )
    for (kind, color, marker) in (
        ("sign", :steelblue, :circle),
        ("complementarity", :purple, :rect),
        ("stationarity", :darkorange, :diamond),
        ("gap", :darkgreen, :utriangle),
    )
        values=[
            begin
                rr=filter(z->z.record_id==x.record_id&&z.kind==kind, rows)
                isempty(rr) ? NaN : max(1e-14, maximum(z.normalized for z in rr))
            end for x in summary
        ]
        scatter!(ax, 1:length(summary), values; label = kind, color, marker, markersize = 11)
    end
    for (i, x) in enumerate(summary)
        x.audit_status=="missing_candidate"&&text!(
            ax,
            i,
            2.0;
            text = "no candidate",
            rotation = pi/2,
            align = (:left, :center),
            fontsize = 10,
        )
    end
    hlines!(ax, [1.0]; color = :black, linestyle = :dash)
    xlims!(ax, 0.3, length(summary)+0.7)
    ylims!(ax, 1e-15, max(100, 10maximum(z.normalized for z in rows)))
    axislegend(ax; position = :lt, nbanks = 2)
    save(joinpath(dir, "F04.png"), fig)
    config=Dict(
        "schema"=>"r5-duality-figure-v1",
        "origin"=>"synthetic",
        "solver_reexecuted"=>false,
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "source_run_ids"=>[x.run_id for x in summary],
        "sources"=>Dict(
            f=>bytes2hex(sha256(read(joinpath(dir, f)))) for
            f in ("comparison.csv", "kkt-residuals.csv", "audit.toml")
        ),
    )
    write(joinpath(dir, "figure-config.toml"), sprint(io->TOML.print(io, config; sorted = true)))
    println("KKT F04 written from saved residuals; no solves.")
end
length(ARGS)==1||error("参数：已完成对偶审计目录")
plot_r5_duality(only(ARGS))
