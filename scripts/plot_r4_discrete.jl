# 从保存的比较CSV重绘，不装载求解器、不重新优化。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==1 || error("参数：新报告目录")
dir=only(ARGS)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
files=["comparison.csv", "modes.csv", "trajectory.csv", "residuals.csv", "dispatch.csv"]
summ, modes, trace, res, dispatch=(collect(CSV.File(joinpath(dir, f))) for f in files)
outputs=["battery-mode-costs.png", "F04.png", "F10.png", "F11.png", "figure-config.toml"]
any(ispath(joinpath(dir, f)) for f in outputs) && error("不覆盖图表")
names=["open_flexible", "open_fixed", "import_flexible", "import_fixed"]
set_theme!(Theme(font = "DejaVu Sans", fontsize = 14))
banner="Synthetic R4 | "*meta["batch_id"]
fig=Figure(size = (1200, 900))
Label(fig[0, 1:2], banner*"\nAll 16 battery states: same-model cost comparison", tellwidth = false)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[div(i-1, 2)+1, mod1(i, 2)],
        title = name,
        xlabel = "Pattern index (1..16)",
        ylabel = "Resource cost (synthetic USD)",
    )
    for (method, color) in (("central_enumeration", :steelblue), ("distributed", :darkorange))
        rr=filter(x->x.case==name&&x.method==method&&isfinite(x.cost), modes)
        sort!(rr; by = x->x.pattern)
        scatterlines!(
            ax,
            [x.pattern for x in rr],
            [x.cost for x in rr];
            color,
            label = method,
            markersize = 8,
        )
        bad=filter(x->!x.model_A1, rr)
        scatter!(
            ax,
            [x.pattern for x in bad],
            [x.cost for x in bad];
            color = :red,
            marker = :xcross,
            markersize = 17,
        )
    end
    i==1&&axislegend(ax; position = :rt, labelsize = 11)
end
Label(
    fig[3, 1:2],
    "Red crosses: rejected model candidates. Mode ordering and all run IDs: modes.csv.\nCosts before A1 acceptance are diagnostic values, not executable dispatches.",
    tellwidth = false,
)
save(joinpath(dir, outputs[1]), fig)
fig=Figure(size = (1380, 820))
Label(
    fig[0, 1],
    banner*"\nF04  Selected candidates: residuals against unchanged A1",
    tellwidth = false,
)
ids=[x.run_id for x in summ]
ax=Axis(
    fig[1, 1],
    xscale = log10,
    xlabel = "Maximum residual / tolerance",
    yticks = (1:length(ids), ids),
)
source=NamedTuple[]
for (j, kind) in enumerate(("model", "electric_original"))
    xx=Float64[]
    yy=Float64[]
    for (i, id) in enumerate(ids)
        rr=filter(
            x->x.run_id==id&&(
                kind=="model" ? x.scope!="electric_original" : x.scope=="electric_original"
            ),
            res,
        )
        isempty(rr)&&continue
        ratio=maximum(abs(x.residual)/x.tolerance for x in rr)
        push!(source, (run_id = id, kind, ratio))
        push!(xx, max(ratio, 1e-12))
        push!(yy, i+(j==1 ? -0.12 : 0.12))
    end
    scatter!(ax, xx, yy; label = kind, color = j==1 ? :steelblue : :darkorange)
end
vlines!(ax, [1.0]; color = :black, linestyle = :dash);
axislegend(ax; position = :lb)
Label(
    fig[2, 1],
    "Precision runs may retain infeasible final candidates. See separate consensus/model/physical flags.\nOriginal-grid pass never substitutes for all adopted-model checks.",
    tellwidth = false,
)
save(joinpath(dir, "F04.png"), fig)
CSV.write(joinpath(dir, "F04-source.csv"), source)
fig=Figure(size = (1250, 950))
Label(
    fig[0, 1:2],
    banner*"\nF11  Actual selected-mode coordination and QCP precision tests",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[i, 1],
        title = name,
        xlabel = "Outer iteration",
        ylabel = "Residual",
        yscale = log10,
    )
    bx=Axis(fig[i, 2], xlabel = "Outer iteration", ylabel = "Resource cost (synthetic USD)")
    for (method, color) in (
        ("distributed", :steelblue),
        ("precision_original", :darkorange),
        ("precision_qcp_1e9", :seagreen),
    )
        rr=filter(x->x.case==name&&x.method==method, trace)
        isempty(rr)&&continue
        lines!(
            ax,
            [x.iteration for x in rr],
            max.(1e-12, [x.primal for x in rr]);
            color,
            label = method*" primal",
        )
        lines!(
            ax,
            [x.iteration for x in rr],
            max.(1e-12, [x.dual for x in rr]);
            color,
            linestyle = :dash,
        )
        scatterlines!(bx, [x.iteration for x in rr], [x.cost for x in rr]; color, markersize = 2)
    end
    hlines!(ax, [1e-4]; color = :black, linestyle = :dot)
    i==1&&axislegend(ax; position = :rt, labelsize = 9)
end
Label(
    fig[5, 1:2],
    "Precision runs use fixed p1; enumeration selects its own best mode. These are distinct trajectories.\nNo centralized reference or exact-network repair is injected into distributed runs.",
    tellwidth = false,
)
save(joinpath(dir, "F11.png"), fig)
fig=Figure(size = (1250, 900))
Label(
    fig[0, 1:2],
    banner*"\nF10  Selected distributed battery and aggregator electric dispatch",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    rr=filter(x->x.case==name&&x.method=="distributed"&&x.actor==2, dispatch)
    ax=Axis(fig[div(i-1, 2)+1, mod1(i, 2)], title = name, xlabel = "Hour", ylabel = "Power (MW)")
    for (label, vals, color) in (
        ("charge", [x.charge_MW for x in rr], :steelblue),
        ("discharge", [x.discharge_MW for x in rr], :darkorange),
        ("PV", [x.PV_MW for x in rr], :seagreen),
        ("electric demand", [x.electric_load_MW for x in rr], :black),
    )
        scatterlines!(ax, [x.t for x in rr], vals; label, color)
    end
    i==1&&axislegend(ax; position = :rt, labelsize = 10)
end
Label(
    fig[3, 1:2],
    "Selected adopted-model candidate, not automatically original-grid feasible.\nFor original-grid acceptance and a separate feasible candidate, read comparison.csv.",
    tellwidth = false,
)
save(joinpath(dir, "F10.png"), fig)
metaout=Dict(
    "origin"=>"synthetic",
    "batch_id"=>meta["batch_id"],
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "unit"=>"synthetic USD, MW, dimensionless residual ratios",
    "figures"=>outputs[1:4],
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(io, metaout; sorted = true)
end
println("Saved read-only battery mode, F04/F10/F11 figures.")
