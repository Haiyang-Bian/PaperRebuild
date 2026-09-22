# F04/F10/F12只读取保存的数值；不重新优化，不覆盖已封存图片。
include("r4_setup.jl")
using CairoMakie, CSV
length(ARGS)==1 || error("参数：新报告目录")
dir=only(ARGS)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
contracts=collect(CSV.File(joinpath(dir, "contracts.csv")))
any(isfile(joinpath(dir, f)) for f in ("F04.png", "F10.png", "F12.png", "figure-config.toml")) &&
    error("不覆盖图表")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
names=["open_flexible", "open_fixed", "import_flexible", "import_fixed"]
fig=Figure(size = (1240, 760))
Label(
    fig[0, 1:2],
    "Synthetic R4 | "*meta["batch"]*"\nF12  Stage-II surplus depends on the disagreement definition",
    fontsize = 17,
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[1+(i-1)÷2, 1+(i-1)%2],
        title = name,
        ylabel = "Stage-II surplus (synthetic USD)",
        xticks = ([1, 2], ["Penalty 100", "Penalty 10000"]),
    )
    rr=filter(x->x.case==name&&x.variant!="not_evaluated", rows)
    if isempty(rr)
        text!(
            ax,
            0.5,
            0.5;
            text = "No evaluable stage-II allocation",
            space = :relative,
            align = (:center, :center),
        )
    else
        for (j, v) in enumerate(["penalty_excluded", "penalty_included"])
            xx=sort(filter(x->x.variant==v, rr); by = x->x.penalty)
            barplot!(
                ax,
                [1, 2] .+ (j==1 ? -0.17 : 0.17),
                [x.stage2_surplus for x in xx];
                width = 0.3,
                color = j==1 ? :steelblue : :darkorange,
            )
        end
        hlines!(ax, [0], color = :black)
    end
end
Legend(
    fig[3, 1:2],
    [PolyElement(color = :steelblue), PolyElement(color = :darkorange)],
    ["Penalty excluded from disagreement", "Penalty included in disagreement"],
    orientation = :horizontal,
)
Label(
    fig[4, 1:2],
    "Positive accounting surplus is not a feasible resource saving when network slacks remain.",
    tellwidth = false,
)
save(joinpath(dir, "F12.png"), fig)
ids=unique(x.run_id for x in rows)
fig=Figure(size = (1260, 670))
Label(
    fig[0, 1],
    "Synthetic R4 | "*meta["batch"]*"\nF04  Elastic equations versus unrelaxed physical checks",
    fontsize = 17,
    tellwidth = false,
)
ax=Axis(
    fig[1, 1],
    xscale = log10,
    xlabel = "Largest residual / A1 threshold (dimensionless)",
    yticks = (1:length(ids), ids),
)
src=NamedTuple[]
for (j, stage) in enumerate(("elastic_model", "elastic_original"))
    ratios=Float64[]
    for id in ids
        rr=filter(
            x->x.run_id==id&&x.stage==stage&&(stage!="elastic_model"||x.scope!="electric_original"),
            res,
        )
        ratio=isempty(rr) ? NaN : maximum(x.residual/x.tolerance for x in rr)
        push!(ratios, ratio)
        push!(src, (run_id = id, stage = stage, ratio = ratio, threshold = 1.0))
    end
    scatter!(
        ax,
        max.(ratios, 1e-14),
        collect(1:length(ids)) .+ (j==1 ? -0.12 : 0.12),
        color = j==1 ? :seagreen : :orangered,
        marker = j==1 ? :circle : :diamond,
        markersize = 13,
        label = stage=="elastic_model" ? "Elastic model" : "Original relations",
    )
end
vlines!(ax, [1.0], linestyle = :dash, color = :black)
axislegend(ax, position = :rb)
save(joinpath(dir, "F04.png"), fig)
CSV.write(joinpath(dir, "F04-source.csv"), src)
fig=Figure(size = (1120, 710))
Label(
    fig[0, 1:2],
    "Synthetic R4 | "*meta["batch"]*"\nF10  AGNB contracts (positive: A sells to B)",
    fontsize = 17,
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[1+(i-1)÷2, 1+(i-1)%2],
        title = name,
        xlabel = "Period (1 h)",
        ylabel = "Peer contract (MW)",
        xticks = 1:4,
    )
    for (carrier, color) in (("P", :steelblue), ("H", :darkorange))
        rr=sort(
            filter(x->x.case==name&&x.penalty==100&&x.actor=="A"&&x.carrier==carrier, contracts);
            by = x->x.t,
        )
        lines!(
            ax,
            [x.t for x in rr],
            [abs(x.peer_export_MW)<1e-6 ? 0.0 : x.peer_export_MW for x in rr];
            color,
            label = carrier,
        )
    end
    ylims!(ax, -0.3, 0.3)
    axislegend(ax, position = :lt)
end
Label(
    fig[3, 1:2],
    "Contracts ignore network constraints. Plot floor 1e-6 MW; original numbers retained in CSV.",
    tellwidth = false,
)
save(joinpath(dir, "F10.png"), fig)
write(
    joinpath(dir, "figure-config.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>meta["batch"],
            "origin"=>"synthetic",
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "source_sha256"=>Dict(
                f=>bytes2hex(sha256(read(joinpath(dir, f)))) for
                f in ("comparison.csv", "actors.csv", "contracts.csv", "residuals.csv")
            ),
            "figures"=>["F04", "F10", "F12"],
            "units"=>["dimensionless", "MW", "USD_synthetic"],
            "plot_contract_floor_MW"=>1e-6,
            "scope"=>"counterfactual network disagreement; not coalition core",
        ),
    ),
)
println("F04/F10/F12 redrawn from saved data.")
