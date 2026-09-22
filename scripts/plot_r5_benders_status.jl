using CairoMakie, CSV, TOML, SHA
length(ARGS)==1||error("参数：已保存状态报告目录")
dir=abspath(only(ARGS))
figures=["F04.png", "F16.png"]
any(ispath(joinpath(dir, f)) for f in vcat(figures, ["figure-config.toml"]))&&error(
    "不覆盖状态图表",
)
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
res=collect(CSV.File(joinpath(dir, "residuals.csv")))
iter=collect(CSV.File(joinpath(dir, "iterations.csv")))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
f=Figure(size = (1600, 650))
Label(
    f[0, 1:3],
    "Synthetic Gurobi status check | " *
    meta["batch_id"] *
    "\nOnly subproblem DualReductions changed to 0; unchanged model and tolerances",
    tellwidth = false,
)
handles=Any[]
for (j, r) in enumerate(summary)
    rr=filter(x->x.record_id==r.record_id, iter)
    ax=Axis(
        f[1, j],
        title = replace(r.case, ".toml"=>""),
        xlabel = "Actual outer iteration",
        ylabel = "Net cost / bound (synthetic USD)",
        titlesize = 14,
    )
    xx=[x.iteration for x in rr]
    safe(v) = isfinite(v) ? v : NaN
    l=scatterlines!(ax, xx, safe.([x.lower_bound for x in rr]); color = :steelblue, markersize = 7)
    u=scatterlines!(ax, xx, safe.([x.upper_bound for x in rr]); color = :purple, markersize = 7)
    h=hlines!(ax, [r.reference_cost]; color = :black, linestyle = :dash)
    j==1&&append!(handles, [l, u, h])
end
Legend(
    f[2, 1:3],
    handles,
    ["Full-domain lower bound", "Feasible upper bound", "Independent direct reference"];
    orientation = :horizontal,
    framevisible = false,
)
save(joinpath(dir, "F16.png"), f)
g=Figure(size = (1400, 720))
Label(
    g[0, 1],
    "Synthetic status follow-up residuals | " *
    meta["batch_id"] *
    "\nMaximum residual / unchanged tolerance across all returned stage values",
    tellwidth = false,
)
ax=Axis(
    g[1, 1],
    ylabel = "Residual / tolerance",
    yscale = log10,
    xticks = (1:length(summary), [replace(r.case, ".toml"=>"") for r in summary]),
    xticklabelsize = 13,
)
for (label, prefix, color) in (
    ("Candidate checks", "candidate_", :steelblue),
    ("Cost LP KKT", "cost_KKT", :purple),
    ("Master checks", "master", :darkorange),
    ("Diagnostic KKT", "diagnostic_KKT", :green),
)
    vals=[
        begin
            rows=filter(a->a.record_id==r.record_id&&startswith(a.phase, prefix), res)
            isempty(rows) ? NaN : max(1e-14, maximum(a.normalized for a in rows))
        end for r in summary
    ]
    scatter!(ax, 1:length(summary), vals; label, color, markersize = 13)
end
hlines!(ax, [1.0]; color = :black, linestyle = :dash, label = "Acceptance threshold")
ylims!(ax, 1e-15, 10)
Legend(g[2, 1], ax; orientation = :horizontal, framevisible = false)
save(joinpath(dir, "F04.png"), g)
config=Dict(
    "schema"=>"r5-benders-status-figures-v1",
    "origin"=>"synthetic",
    "solver_reexecuted"=>false,
    "batch_id"=>meta["batch_id"],
    "run_ids"=>[r.run_id for r in summary],
    "figures"=>figures,
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "sources"=>Dict(
        file=>bytes2hex(sha256(read(joinpath(dir, file)))) for file in (
            "comparison.csv",
            "residuals.csv",
            "iterations.csv",
            "status-probes.csv",
            "before-after.csv",
        )
    ),
)
open(joinpath(dir, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("Saved F04/F16 from existing status-study values only.")
