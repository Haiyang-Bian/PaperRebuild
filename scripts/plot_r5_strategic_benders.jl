using CairoMakie, CSV, TOML, SHA
length(ARGS) == 1 || error("参数：已生成的策略分解报告目录")
dir = abspath(only(ARGS))
figures = ["F04.png", "F16.png", "F16-routes.png"]
any(ispath(joinpath(dir, f)) for f in vcat(figures, ["figure-config.toml"])) &&
    error("不覆盖已有图表")
rows = collect(CSV.File(joinpath(dir, "comparison.csv")))
res = collect(CSV.File(joinpath(dir, "selected-residuals.csv")))
iterations = collect(CSV.File(joinpath(dir, "iterations.csv")))
meta = TOML.parsefile(joinpath(dir, "report.toml"))
routes = ["cuts", "critical", "paper_critical"]
names = sort!(unique(x.case for x in rows))
labels = replace.(names, "competitive_"=>"", ".toml"=>"")
set_theme!(Theme(font = "DejaVu Sans", fontsize = 14))
f = Figure(size = (1800, 820))
Label(
    f[0, 1:3],
    "Synthetic strategy Benders | " *
    meta["batch_id"] *
    "\nF04: selected strategy, market, dispatch and risk residuals / unchanged tolerance. Missing candidates are not zeros.",
    tellwidth = false,
)
for (j, route) in enumerate(routes)
    ax = Axis(
        f[1, j],
        title = route,
        ylabel = "Maximum residual / tolerance",
        yscale = log10,
        xticks = (1:length(names), labels),
        xticklabelrotation = pi/3,
        xticklabelsize = 11,
    )
    rr = [only(filter(x->x.case==name && x.route==route, rows)) for name in names]
    values = [
        begin
            a = filter(y->y.record_id==x.record_id, res)
            isempty(a) ? NaN : max(1e-14, maximum(y.normalized for y in a))
        end for x in rr
    ]
    scatter!(ax, 1:length(names), values; markersize = 12, color = :steelblue)
    for (i, x) in enumerate(rr)
        !x.model_pass &&
            text!(ax, i, 0.02; text = "no\ncandidate", align = (:center, :top), fontsize = 11)
    end
    hlines!(ax, [1.0]; color = :black, linestyle = :dash)
    xlims!(ax, 0.5, length(names)+0.5)
    ylims!(ax, 1e-15, 10.0)
end
save(joinpath(dir, "F04.png"), f)

g = Figure(size = (1900, 1400))
Label(
    g[0, 1:3],
    "Synthetic strategy bounds | " *
    meta["batch_id"] *
    "\nF16: IES net payment + worst recourse (USD). Orange lower bounds apply only to the current restricted comfort domain.",
    tellwidth = false,
)
for (i, name) in enumerate((
        "competitive_hard_zero",
        "competitive_thermal_e030_r005",
        "competitive_future_e030_r005",
    )),
    (j, route) in enumerate(routes)

    record = only(filter(x->x.record_id==name*"--"*route, rows))
    rr = filter(x->x.record_id==record.record_id, iterations)
    ax = Axis(
        g[i, j],
        title = replace(name, "competitive_"=>"")*" / "*route*"\n"*record.status,
        xlabel = "Actual outer iteration",
        ylabel = "Net cost / bound (synthetic USD)",
        titlesize = 13,
    )
    xx = [x.iteration for x in rr]
    finite(v) = isfinite(v) ? v : NaN
    scatterlines!(
        ax,
        xx,
        [finite(x.lower_bound) for x in rr];
        color = route=="paper_critical" ? :darkorange : :steelblue,
        markersize = 5,
        label = route=="paper_critical" ? "current restricted lower" : "full-domain lower",
    )
    scatterlines!(
        ax,
        xx,
        [finite(x.upper_bound) for x in rr];
        color = :purple,
        markersize = 5,
        label = "best verified strategy upper",
    )
    isfinite(record.reference_cost) && hlines!(
        ax,
        [record.reference_cost];
        color = :black,
        linestyle = :dash,
        label = "independent direct reference",
    )
    axislegend(ax; position = :rb, labelsize = 10)
end
save(joinpath(dir, "F16.png"), g)

h = Figure(size = (1800, 950))
Label(
    h[0, 1:2],
    "Synthetic route comparison | " *
    meta["batch_id"] *
    "\nCandidate cost differences are not optimality gaps. Full-domain certification and restricted stopping are separate.",
    tellwidth = false,
)
a = Axis(
    h[1, 1:2],
    ylabel = "Candidate minus direct reference (synthetic USD)",
    xticks = (1:length(names), labels),
    xticklabelrotation = pi/4,
    xticklabelsize = 11,
)
b = Axis(
    h[2, 1],
    ylabel = "Actual outer iterations",
    xticks = (1:length(names), labels),
    xticklabelrotation = pi/3,
    xticklabelsize = 10,
)
c = Axis(h[2, 2], ylabel = "Number of runs", xticks = (1:3, routes), title = "Evidence categories")
for (j, route, color) in
    ((1, "cuts", :steelblue), (2, "critical", :purple), (3, "paper_critical", :darkorange))
    rr = [only(filter(x->x.case==name && x.route==route, rows)) for name in names]
    xx = collect(1:length(names)) .+ (j-2)*0.18
    scatter!(
        a,
        xx,
        [x.candidate_cost_difference for x in rr];
        color,
        label = route,
        markersize = 10,
    )
    scatter!(b, xx, [x.iterations for x in rr]; color, label = route, markersize = 9)
    for (k, label, pred, col) in (
        (1, "full cost complete", x->x.cost_complete, :steelblue),
        (2, "restricted stop", x->x.restricted_stopping, :darkorange),
        (3, "infeasible / unresolved", x->!x.cost_complete && !x.restricted_stopping, :gray),
    )
        barplot!(
            c,
            [j+(k-2)*0.23],
            [count(pred, rr)];
            color = col,
            width = 0.21,
            label = j==1 ? label : nothing,
        )
    end
end
hlines!(a, [0]; color = :black, linestyle = :dash)
xlims!(a, 0.5, length(names)+0.5)
axislegend(a; position = :rt);
axislegend(b; position = :rt, labelsize = 10);
Legend(h[3, 1:2], c; orientation = :horizontal, framevisible = false)
save(joinpath(dir, "F16-routes.png"), h)
sources = Dict(
    f=>bytes2hex(sha256(read(joinpath(dir, f)))) for
    f in ("comparison.csv", "iterations.csv", "selected-residuals.csv", "report.toml")
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r5-strategic-benders-figures-v1",
            "origin"=>"synthetic",
            "batch_id"=>meta["batch_id"],
            "solver_reexecuted"=>false,
            "run_ids"=>[x.run_id for x in rows],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "sources"=>sources,
            "figures"=>figures,
        );
        sorted = true,
    )
end
println("F04/F16 redrawn from saved strategy evidence; no optimization.")
