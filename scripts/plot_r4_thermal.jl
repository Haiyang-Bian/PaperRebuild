using CairoMakie, CSV, TOML, SHA
length(ARGS)==1 || error("参数：含CSV的新报告目录")
dir=only(ARGS)
meta=TOML.parsefile(joinpath(dir, "report.toml"))
names=meta["cases"]
files=["comparison.csv", "residuals.csv", "states.csv", "nodes.csv", "policy-comparison.csv"]
summary, residuals, states, nodes, policies=(collect(CSV.File(joinpath(dir, f))) for f in files)
outputs=["F04.png", "F05.png", "F10.png", "figure-config.toml"]
any(ispath(joinpath(dir, x)) for x in outputs) && error("不覆盖旧图")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
banner="Synthetic R4 | "*meta["batch_id"]
labels=["fixed/ref", "fixed/exp", "joint/ref", "joint/exp"]
combos=[
    ("fixed", "reference"),
    ("fixed", "exponential"),
    ("joint", "reference"),
    ("joint", "exponential"),
]
fig=Figure(size = (1280, 860))
Label(
    fig[0, 1:2],
    banner*"\nIndependent residuals; A1 threshold = 1; missing candidates omitted",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[div(i-1, 2)+1, mod1(i, 2)],
        title = name,
        xlabel = "Policy / loss",
        ylabel = "Max residual / tolerance",
        xticks = (1:4, labels),
        yscale = log10,
    )
    for (scope, color, marker) in (
        ("heat", :darkorange, :circle),
        ("electric_original", :steelblue, :rect),
        ("other_model", :darkgreen, :utriangle),
    )
        values=Float64[]
        for (policy, loss) in combos
            rr=filter(
                x->x.case==name&&x.policy==policy&&x.loss==loss &&
                   (
                       scope=="other_model" ? !(x.scope in ("heat", "electric_original")) :
                       x.scope==scope
                   ),
                residuals,
            )
            push!(values, isempty(rr) ? NaN : max(1e-9, maximum(x.normalized for x in rr)))
        end
        scatterlines!(ax, 1:4, values; color, marker, label = scope)
    end
    hlines!(ax, [1.0], linestyle = :dash, color = :black)
    i==1 && axislegend(ax; position = :rb, labelsize = 11)
end
save(joinpath(dir, "F04.png"), fig)
# 所有图使用预声明的joint策略；不根据结果挑选看起来更好的运行。
fig=Figure(size = (1450, 1180))
Label(
    fig[0, 1:3],
    banner*"\nJoint strategy | active flow, operating supply temperatures and paired-pipe heat loss",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    flowax=Axis(
        fig[i, 1],
        title = name,
        xlabel = "Period",
        ylabel = "Sum active arc mass (kg/s)",
        xticks = 1:4,
    )
    tempax=Axis(
        fig[i, 2],
        xlabel = "Period",
        ylabel = "Active supply inlet range (K)",
        xticks = 1:4,
    )
    lossax=Axis(fig[i, 3], xlabel = "Period", ylabel = "Heat loss (MW)", xticks = 1:4)
    for (loss, color) in (("reference", :steelblue), ("exponential", :darkorange))
        flows=Float64[]
        lo=Float64[]
        hi=Float64[]
        losses=Float64[]
        for t in 1:4
            rr=filter(x->x.case==name&&x.policy=="joint"&&x.loss==loss&&x.t==t, states)
            operating=filter(x->x.active, rr)
            push!(flows, isempty(rr) ? NaN : sum(x.m_kg_s for x in rr))
            push!(lo, isempty(operating) ? NaN : minimum(x.S_in_K for x in operating))
            push!(hi, isempty(operating) ? NaN : maximum(x.S_in_K for x in operating))
            push!(losses, isempty(rr) ? NaN : sum(x.loss_MW for x in rr))
        end
        scatterlines!(flowax, 1:4, flows; color, label = loss)
        band!(tempax, 1:4, lo, hi; color = (color, 0.2))
        scatterlines!(tempax, 1:4, lo; color, label = loss*" min")
        lines!(tempax, 1:4, hi; color, linestyle = :dash)
        scatterlines!(lossax, 1:4, losses; color, label = loss)
    end
    i==1 && axislegend(flowax; position = :rt, labelsize = 11)
end
save(joinpath(dir, "F05.png"), fig)
fig=Figure(size = (1400, 930))
Label(
    fig[0, 1:2],
    banner*"\nVerified steady candidates | operating cost and valid solver lower bound\nNo pump or restart cost; no dynamic-cycle claim",
    tellwidth = false,
)
for (i, name) in enumerate(names)
    ax=Axis(
        fig[div(i-1, 2)+1, mod1(i, 2)],
        title = name,
        xlabel = "Policy / loss",
        ylabel = "Synthetic USD",
        xticks = (1:4, labels),
        yautolimitmargin = (0.08, 0.18),
    )
    xlims!(ax, 0.45, 4.55)
    rr=[only(filter(x->x.case==name&&x.policy==p&&x.loss==l, summary)) for (p, l) in combos]
    cost=[x.adopted_physical_pass ? x.operating_cost : NaN for x in rr]
    lower=[x.objective_bound for x in rr]
    finite_values=filter(isfinite, vcat(cost, lower))
    label_base=isempty(finite_values) ? 0.0 : minimum(finite_values)
    scatter!(
        ax,
        1:4,
        cost;
        color = :steelblue,
        marker = :circle,
        markersize = 15,
        label = "A1 candidate",
    )
    scatter!(
        ax,
        1:4,
        lower;
        color = :darkorange,
        marker = :hline,
        markersize = 25,
        label = "Solver bound",
    )
    for k in 1:4
        isfinite(cost[k])&&isfinite(lower[k]) &&
            lines!(ax, [k, k], [lower[k], cost[k]]; color = :gray)
        text!(
            ax,
            k,
            isfinite(cost[k]) ? cost[k] : label_base;
            text = !rr[k].adopted_physical_pass ? " no A1" :
                   rr[k].cost_optimization_complete ? " A2" : " incomplete",
            fontsize = 11,
            align = (:center, :bottom),
            offset = (0, 6),
        )
    end
    i==1 && axislegend(ax; position = :rt, labelsize = 11)
end
save(joinpath(dir, "F10.png"), fig)
config=Dict(
    "batch_id"=>meta["batch_id"],
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "flow_plot"=>"joint strategy for all four frozen inputs; sums over running directed arcs",
    "temperature_plot"=>"active supply inlet min/max; idle temperatures omitted",
    "cost_plot"=>"only independently accepted candidates; effective bound shown separately",
    "source_run_ids"=>[String(x.run_id) for x in summary],
    "sources"=>Dict(f=>bytes2hex(sha256(read(joinpath(dir, f)))) for f in files),
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("Saved F04/F05/F10 from existing records; no solve performed.")
