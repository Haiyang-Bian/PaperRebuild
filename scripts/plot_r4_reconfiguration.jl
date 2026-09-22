using CairoMakie, CSV, TOML, SHA
length(ARGS)==1 || error("参数：报告目录")
dir=only(ARGS);
meta=TOML.parsefile(joinpath(dir, "report.toml"))
files=["comparison.csv", "topology.csv", "residuals.csv", "thermal-diagnostic.csv"]
summary, topology, residuals, diagnostics=(collect(CSV.File(joinpath(dir, f))) for f in files)
outputs=["F01.png", "F04.png", "F10.png", "heat-mass-screen.png", "figure-config.toml"]
any(ispath(joinpath(dir, f)) for f in outputs) && error("不覆盖旧图")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
names=meta["cases"];
policies=meta["policies"]
banner="Synthetic R4 | "*meta["batch_id"]
fig=Figure(size = (1250, 850))
Label(
    fig[0, 1:2],
    banner*"\nJoint strategy: closed electrical lines and daily heat valves",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[div(i-1, 2)+1, mod1(i, 2)],
        title = name,
        xlabel = "Period",
        yticks = (1:6, ["E:1-2", "E:2-3", "E:1-3", "H:1-2", "H:2-3", "H:1-3"]),
        xticks = 1:4,
    )
    rr=filter(x->x.case==name&&x.policy=="joint"&&x.electric=="exact", topology)
    for row in rr
        scatter!(
            ax,
            [row.t, row.t],
            [row.edge, row.edge+3],
            color = [row.u_E>0.5 ? :steelblue : :lightgray, row.u_H>0.5 ? :darkorange : :lightgray],
            markersize = 25,
            marker = :rect,
        )
    end
    ylims!(ax, 0.4, 6.6)
    xlims!(ax, 0.5, 4.5)
end
save(joinpath(dir, "F01.png"), fig)
fig=Figure(size = (1250, 850))
Label(
    fig[0, 1:2],
    banner*"\nA1: adopted model versus original electrical equality (threshold = 1)",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[div(i-1, 2)+1, mod1(i, 2)],
        title = name,
        xlabel = "Strategy",
        ylabel = "Max residual / tolerance",
        yscale = log10,
        xticks = (1:4, policies),
    )
    for (electric, scope, color, mark) in (
        ("socp", "model", :steelblue, :circle),
        ("socp", "electric_original", :crimson, :utriangle),
        ("exact", "electric_original", :darkgreen, :rect),
    )
        yy=Float64[]
        for policy in policies
            vals=[
                x.normalized for
                x in residuals if x.case==name&&x.policy==policy&&x.electric==electric &&
                    (scope=="model" ? x.scope!="electric_original" : x.scope==scope)
            ]
            push!(yy, isempty(vals) ? NaN : max(1e-8, maximum(vals)))
        end
        scatterlines!(ax, 1:4, yy; color, marker = mark, label = electric*" / "*scope)
    end
    hlines!(ax, [1.0], color = :black, linestyle = :dash)
    i==1 && axislegend(ax; position = :rb, labelsize = 10)
end
save(joinpath(dir, "F04.png"), fig)
fig=Figure(size = (1250, 850))
Label(
    fig[0, 1:2],
    banner*"\nExact electrical reference; thermal mass/heat consistency remains unverified",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[div(i-1, 2)+1, mod1(i, 2)],
        title = name,
        xlabel = "Strategy",
        ylabel = "Cost saving versus fixed (synthetic USD)",
        xticks = (1:4, policies),
    )
    rr=[only(filter(x->x.case==name&&x.policy==p&&x.electric=="exact", summary)) for p in policies]
    saving=[x.electric_checked_saving for x in rr]
    barplot!(ax, 1:4, saving; color = :steelblue)
    scatterlines!(
        ax,
        1:4,
        [x.switching_cost for x in rr];
        color = :darkorange,
        label = "Switching cost",
        markersize = 9,
    )
    hlines!(ax, [0.0], color = :black)
    ylims!(ax, -0.01, 0.26)
    axislegend(ax; position = :rt, labelsize = 11)
end
save(joinpath(dir, "F10.png"), fig)
fig=Figure(size = (1100, 650))
ax=Axis(
    fig[1, 1],
    xlabel = "Saved pipe mass flow (kg/s)",
    ylabel = "Saved inlet heat (MW)",
    title = banner*"\nStatic heat diagnostic: zero mass with positive heat is not temperature certification",
)
for (electric, color) in (("socp", :steelblue), ("exact", :darkorange))
    rr=filter(x->endswith(x.run_id, "--"*electric)&&x.heat_MW>1e-6, diagnostics)
    scatter!(
        ax,
        [x.mass_kg_s for x in rr],
        [x.heat_MW for x in rr];
        color,
        markersize = 8,
        label = electric,
        alpha = 0.65,
    )
end
vlines!(ax, [0.0], color = :crimson, linestyle = :dash)
axislegend(ax; position = :rt)
save(joinpath(dir, "heat-mass-screen.png"), fig)
config=Dict(
    "batch_id"=>meta["batch_id"],
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "units"=>["USD_synthetic", "MW", "kg/s", "normalized residual", "binary state"],
    "scope"=>"static adopted heat model; original electrical equations checked separately; no dynamic heat claim",
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("R4 network figures saved without optimization.")
