using CSV, TOML, SHA, CairoMakie
length(ARGS)==3||error("usage: plot_r8_tradeoff.jl REPORT AUDIT NEW_FIGURES")
report, audit, out=abspath.(ARGS)
ispath(out)&&error("不覆盖R8图件")
hashfile(p) = bytes2hex(sha256(read(p)))
registry=TOML.parsefile(joinpath(report, "report-hashes.toml"))["files"]
all(
    hashfile(joinpath(report, p))==registry[p] for p in ("summary.csv", "events.csv", "rule.toml")
)||error("R8图源改变")
a=TOML.parsefile(joinpath(audit, "audit.toml"))
a["report_manifest_sha256"]==hashfile(joinpath(report, "report-hashes.toml"))||error(
    "R8审计归属错误",
)
all(hashfile(joinpath(audit, p))==h for (p, h) in a["files"])||error("R8审计文件改变")
rows=collect(CSV.File(joinpath(report, "summary.csv")))
events=collect(CSV.File(joinpath(report, "events.csv")))
res=vcat([collect(CSV.File(joinpath(audit, p))) for p in a["residual_parts"]]...)
cost_values=[
    r.normal_cost_USD for r in rows if
    r.control=="fixed" && r.resource=="all" && r.mode=="threshold" && r.primary_model_pass
]
cost_min, cost_max=extrema(cost_values)
fig=Figure(size = (1640, 1040), fontsize = 17)
Label(
    fig[0, 1:2],
    "F31 | Normal cost, resilience limits and explicit resource controls";
    fontsize = 25,
)
Label(
    fig[1, 1:2],
    "Synthetic inputs | whole-pipe UA = 10 W/K | exclusive batteries | detailed adopted model";
    fontsize = 17,
)
for (col, family, title) in
    ((1, "legacy", "Two-node counterexample"), (2, "tie_three", "Three-node tie / GT / EB case"))
    ax=Axis(
        fig[2, col],
        title = title,
        xlabel = "Allowed unserved energy per event (MWh)",
        ylabel = "Expected normal cost (USD)",
    )
    curve=sort(
        filter(
            r->r.family==family&&r.resource=="all"&&r.control=="fixed"&&r.mode=="threshold"&&r.solver=="Gurobi",
            rows,
        );
        by = r->r.limit_MWh,
    )
    accepted=filter(r->r.primary_model_pass, curve)
    if !isempty(accepted)
        lines!(
            ax,
            [r.limit_MWh for r in accepted],
            [r.normal_cost_USD for r in accepted];
            color = :steelblue,
            linewidth = 3,
        )
        scatter!(
            ax,
            [r.limit_MWh for r in accepted],
            [r.normal_cost_USD for r in accepted];
            color = :steelblue,
            markersize = 11,
            label = "Feasible cost",
        )
    end
    eco=only(
        filter(
            r->r.family==family&&r.resource=="all"&&r.control=="fixed"&&r.mode=="economic"&&r.solver=="Gurobi",
            rows,
        ),
    )
    if eco.primary_model_pass
        hlines!(
            ax,
            [eco.normal_cost_USD];
            color = :gray,
            linestyle = :dash,
            label = "Economic-only cost",
        )
    end
    invalid=filter(r->r.primary_status=="infeasible_certified", curve)
    if !isempty(invalid)
        y=isempty(accepted) ? 0.0 : maximum(r.normal_cost_USD for r in accepted)+0.2
        scatter!(
            ax,
            [r.limit_MWh for r in invalid],
            fill(y, length(invalid));
            color = :firebrick,
            marker = :xcross,
            markersize = 15,
            label = "Infeasible (symbol height arbitrary)",
        )
    end
    axislegend(ax; position = :rt, labelsize = 13)
    # 共同纵轴避免把1e-13级浮点尾差放大成资源收益。
    ylims!(ax, cost_min-0.15, cost_max+0.35)
end
ax=Axis(
    fig[3, 1],
    title = "Resources: same cost can hide different recovery risk",
    ylabel = "Expected normal cost (USD)",
    xticks = (1:4, ["All resources", "Battery removed*", "No net preheat", "No switching"]),
)
resources=["all", "no_battery", "no_net_heat_charge", "no_reconfiguration"]
for (i, key) in enumerate(resources)
    r=only(
        filter(
            r->r.family=="tie_three"&&r.resource==key&&r.control=="fixed"&&r.mode=="threshold"&&r.limit_MWh==0.4&&r.solver=="Gurobi",
            rows,
        ),
    )
    if r.primary_model_pass
        scatter!(ax, [i], [r.normal_cost_USD]; color = :darkorange, markersize = 14)
        text!(
            ax,
            i,
            r.normal_cost_USD;
            text = string(
                round(r.normal_cost_USD; digits = 4),
                " USD\nrisk ",
                round(r.worst_upper_MWh; digits = 4),
                " MWh",
            ),
            align = (:center, :bottom),
            offset = (0, 9),
            fontsize = 14,
        )
    elseif r.primary_status=="infeasible_certified"
        scatter!(ax, [i], [191.95]; color = :firebrick, marker = :xcross, markersize = 15)
        text!(
            ax,
            i,
            191.95;
            text = "Normal heat\nboundary conflict",
            align = (:center, :bottom),
            offset = (0, 8),
            fontsize = 13,
            color = :firebrick,
        )
    end
end
ylims!(ax, 191.70, 192.10)
xlims!(ax, 0.5, 4.5)
ax2=Axis(
    fig[3, 2],
    title = "Independent residuals (candidate runs only)",
    xlabel = "Frozen run index",
    ylabel = "Maximum residual / A1 threshold",
    yscale = log10,
)
points=NamedTuple[]
for (i, r) in enumerate(rows)
    rr=filter(z->z.id==r.id, res)
    isempty(rr)&&continue
    ratio=maximum(z.tolerance>0 ? z.residual/z.tolerance : z.residual==0 ? 0.0 : Inf for z in rr)
    scatter!(
        ax2,
        [i],
        [max(ratio, 1e-12)];
        color = ratio<=1 ? :seagreen : :firebrick,
        markersize = 8,
    )
    push!(points, (index = i, id = r.id, run_id = r.run_id, residual_ratio = ratio))
end
hlines!(ax2, [1.0]; color = :firebrick, linestyle = :dash)
finite_ratios=[p.residual_ratio for p in points if isfinite(p.residual_ratio)]
ylims!(ax2, 1e-12, max(10.0, 2maximum(finite_ratios; init = 0.0)))
xlims!(ax2, 0.5, length(rows)+0.5)
Label(
    fig[4, 1:2],
    "* Battery removal also removes its sole grid-forming role. No net preheat retains dynamic transport and initial heat.";
    fontsize = 15,
)
Label(
    fig[5, 1:2],
    "Sampled limits only; crosses have arbitrary height; zero residuals plot at 1e-12. Free-flow / time limits: see full tables.";
    fontsize = 15,
)
mkpath(out)
save(joinpath(out, "F31-r8-tradeoff.png"), fig; px_per_unit = 2)
cp(joinpath(report, "summary.csv"), joinpath(out, "summary.csv"))
cp(joinpath(report, "events.csv"), joinpath(out, "events.csv"))
CSV.write(joinpath(out, "residual-points.csv"), points)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
write(
    joinpath(out, "figure.toml"),
    sprint(
        io->TOML.print(
            io,
            Dict(
                "figure"=>"F31",
                "origin"=>"synthetic",
                "report_manifest_sha256"=>hashfile(joinpath(report, "report-hashes.toml")),
                "audit_sha256"=>hashfile(joinpath(audit, "audit.toml")),
                "run_ids"=>String[r.run_id for r in rows],
                "layout_size"=>[1640, 1040],
                "pixels_per_layout_unit"=>2,
                "size_pixels"=>[3280, 2080],
                "units"=>["USD", "MWh", "W/K", "dimensionless residual ratio"],
                "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out)),
            );
            sorted = true,
        ),
    ),
)
println("R8 F31 generated from saved values without optimization.")
