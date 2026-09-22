using CairoMakie, CSV, TOML, SHA
length(ARGS)==1||error("参数：已有分解报告目录")
dir=abspath(only(ARGS))
figures=["F04.png", "F16.png", "F16-routes.png", "F16-progress.png"]
any(ispath(joinpath(dir, f)) for f in vcat(figures, ["figure-config.toml"]))&&error(
    "不覆盖分解图表",
)
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
iter=collect(CSV.File(joinpath(dir, "iterations.csv")))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
set_theme!(Theme(font = "DejaVu Sans", fontsize = 14))
routes=["cuts", "critical", "paper_critical"]
f=Figure(size = (1920, 1180))
residual_handles=Any[]
residual_labels=String[]
Label(
    f[0, 1:2],
    "Synthetic three-route Benders | "*meta["batch_id"]*"\nEach marker is a maximum residual / unchanged tolerance; missing candidates are not zero residual",
    tellwidth = false,
)
for (j, (route, solver)) in
    enumerate(vcat([(r, "highs") for r in routes], [("critical", "gurobi")]))
    rows=filter(x->x.route==route&&x.solver==solver, summary)
    ax=Axis(
        f[cld(j, 2), mod1(j, 2)],
        title = route*" / "*solver,
        ylabel = "Residual / tolerance",
        yscale = log10,
        xticks = (1:length(rows), [replace(x.case, ".toml"=>"") for x in rows]),
        xticklabelrotation = pi/3,
        xticklabelsize = 10,
    )
    mx=1.0
    for (label, prefix, color) in (
        ("all candidate checks", "candidate_", :steelblue),
        ("all LP KKT", "cost_KKT", :darkorange),
        ("all master checks", "master", :purple),
        ("diagnostic KKT", "diagnostic_KKT", :green),
    )
        vals=[
            begin
                rr=filter(a->a.record_id==x.record_id&&startswith(a.phase, prefix), res)
                # 图显示全部返回数值的候选检查，最终逐项残差另有公开CSV。
                isempty(rr) ? NaN : max(1e-14, maximum(a.normalized for a in rr))
            end for x in rows
        ]
        finite=filter(isfinite, vals)
        !isempty(finite)&&(mx=max(mx, maximum(finite)))
        handle=scatter!(ax, 1:length(rows), vals; label, color, markersize = 9)
        j==1&&(push!(residual_handles, handle); push!(residual_labels, label))
    end
    for (i, x) in enumerate(rows)
        !x.model_pass&&text!(
            ax,
            i,
            0.03;
            text = "no final\ncandidate",
            align = (:center, :top),
            fontsize = 10,
        )
    end
    hlines!(ax, [1.0]; color = :black, linestyle = :dash)
    ylims!(ax, 1e-15, max(10.0, 10mx))
end
Legend(
    f[3, 1:2],
    residual_handles,
    residual_labels;
    orientation = :horizontal,
    framevisible = false,
)
save(joinpath(dir, "F04.png"), f)

g=Figure(size = (1800, 1380))
Label(
    g[0, 1:3],
    "Synthetic Benders bounds | "*meta["batch_id"]*"\nUSD; full-domain and restricted-domain lower bounds are different certificates; independent reference never enters the algorithm",
    tellwidth = false,
)
for (i, name) in enumerate(("hard_zero", "thermal_e030_r005", "future_e030_r005")),
    (j, route) in enumerate(routes)

    record=only(filter(x->x.record_id==name*"--"*route*"--highs", summary))
    rr=filter(x->x.record_id==record.record_id, iter)
    ax=Axis(
        g[i, j],
        title = name*" / "*route*"\n"*record.status,
        xlabel = "Actual outer iteration",
        ylabel = "Net cost / bound (synthetic USD)",
        titlesize = 13,
    )
    finitevalue(v) = isfinite(v) ? v : NaN
    lower=[finitevalue(x.lower_bound) for x in rr]
    upper=[finitevalue(x.upper_bound) for x in rr]
    xx=[x.iteration for x in rr]
    scatterlines!(
        ax,
        xx,
        lower;
        color = route=="paper_critical" ? :darkorange : :steelblue,
        markersize = 5,
        label = route=="paper_critical" ? "current-domain lower bound" : "full-domain lower bound",
    )
    scatterlines!(
        ax,
        xx,
        upper;
        color = :purple,
        markersize = 5,
        label = "best verified policy upper bound",
    )
    isfinite(record.reference_cost)&&hlines!(
        ax,
        [record.reference_cost];
        color = :black,
        linestyle = :dash,
        label = "independent direct reference",
    )
    axislegend(ax; position = :rb, labelsize = 10)
end
save(joinpath(dir, "F16.png"), g)

h=Figure(size = (1880, 1020))
Label(
    h[0, 1:2],
    "Synthetic route comparison | "*meta["batch_id"]*"\nCandidate cost differences are not optimality gaps; restricted-domain stops remain separate; no scale-speed conclusion",
    tellwidth = false,
)
names=sort!(unique(x.case for x in summary if x.solver=="highs"))
a=Axis(
    h[1, 1:2],
    ylabel = "Candidate cost minus direct reference (synthetic USD)",
    xticks = (1:length(names), replace.(names, ".toml"=>"")),
    xticklabelrotation = pi/4,
    xticklabelsize = 11,
)
b=Axis(
    h[2, 1],
    ylabel = "Actual outer iterations",
    xticks = (1:length(names), replace.(names, ".toml"=>"")),
    xticklabelrotation = pi/3,
    xticklabelsize = 10,
)
c=Axis(
    h[2, 2],
    ylabel = "Number of runs",
    xticks = (1:3, routes),
    title = "HiGHS: evidence categories",
)
for (j, route, color) in
    ((1, "cuts", :steelblue), (2, "critical", :purple), (3, "paper_critical", :darkorange))
    rr=[only(filter(x->x.case==name&&x.route==route&&x.solver=="highs", summary)) for name in names]
    xx=(1:length(names)) .+ (j-2)*0.18
    scatter!(
        a,
        xx,
        [x.candidate_cost_difference for x in rr];
        label = route,
        color,
        markersize = 11,
    )
    scatter!(b, xx, [x.iterations for x in rr]; label = route, color, markersize = 9)
    for (k, label, predicate, col) in (
        (1, "full domain complete", x->x.cost_complete, :steelblue),
        (2, "restricted stop", x->x.restricted_stopping, :darkorange),
        (3, "infeasible / unresolved", x->!x.cost_complete&&!x.restricted_stopping, :gray),
    )
        barplot!(
            c,
            [j+(k-2)*0.23],
            [count(predicate, rr)];
            width = 0.21,
            color = col,
            label = j==1 ? label : nothing,
        )
    end
end
hlines!(a, [0]; color = :black, linestyle = :dash);
axislegend(a; position = :lt);
axislegend(b; position = :rt, labelsize = 11);
axislegend(c; position = :lt, labelsize = 11)
save(joinpath(dir, "F16-routes.png"), h)
p=Figure(size = (1740, 900))
Label(
    p[0, 1:3],
    "Four-period synthetic algorithm evidence | "*meta["batch_id"]*"\nGaps use each current declared domain; three scenario LPs are attempted even when worst probabilities are zero",
    tellwidth = false,
)
for (j, route) in enumerate(routes)
    rr=filter(x->x.record_id=="future_e030_r005--"*route*"--highs", iter)
    local a=Axis(
        p[1, j],
        title = route,
        xlabel = "Actual outer iteration",
        ylabel = "Current-domain relative gap",
        yscale = log10,
    )
    vals=[isfinite(x.relative_gap) ? max(1e-14, x.relative_gap) : NaN for x in rr]
    scatterlines!(
        a,
        [x.iteration for x in rr],
        vals;
        color = route=="paper_critical" ? :darkorange : :steelblue,
        markersize = 6,
    )
    # 精确停止仍使用绝对+相对规则；参考线仅表示其中预声明的相对项。
    hlines!(a, [1e-6]; color = :black, linestyle = :dash, label = "relative term of stop rule")
    axislegend(a; position = :rt, labelsize = 10)
    local b=Axis(
        p[2, j],
        xlabel = "Actual outer iteration",
        ylabel = "Scenario count",
        yticks = 0:3,
    )
    stairs!(
        b,
        [x.iteration for x in rr],
        [x.critical_count for x in rr];
        color = :purple,
        label = "critical set after update",
    )
    scatter!(
        b,
        [x.iteration for x in rr],
        [x.cost_scenarios for x in rr];
        color = :steelblue,
        label = "cost scenario LPs attempted",
        markersize = 6,
    )
    ylims!(b, -0.15, 3.25)
    axislegend(b; position = :rb, labelsize = 10)
end
save(joinpath(dir, "F16-progress.png"), p)
sources=Dict(
    file=>bytes2hex(sha256(read(joinpath(dir, file)))) for
    file in ("comparison.csv", "iterations.csv", "residuals.csv", "report.toml")
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r5-benders-figures-v1",
            "origin"=>"synthetic",
            "batch_id"=>meta["batch_id"],
            "solver_reexecuted"=>false,
            "run_ids"=>[x.run_id for x in summary],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "sources"=>sources,
            "figures"=>figures,
        );
        sorted = true,
    )
end
println("F04/F16 redrawn from saved values and actual iterations; no optimization.")
