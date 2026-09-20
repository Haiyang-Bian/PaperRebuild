using CSV, TOML, SHA, CairoMakie
length(ARGS)==3||error("usage: plot_r7_lossy_flow.jl REPORT AUDIT NEW_FIGURES")
report, audit, out=abspath.(ARGS)
ispath(out)&&error("不覆盖有损规划图件")
hashfile(p) = bytes2hex(sha256(read(p)))
sources=["summary.csv", "events.csv", "trajectories.csv", "residuals.csv", "rule.toml"]
registry=TOML.parsefile(joinpath(report, "report-hashes.toml"))["files"]
all(hashfile(joinpath(report, p))==registry[p] for p in sources)||error("报告图源改变")
ac=TOML.parsefile(joinpath(audit, "audit.toml"))
ac["report_manifest_sha256"]==hashfile(joinpath(report, "report-hashes.toml"))||error(
    "费用审计归属错误",
)
hashfile(joinpath(audit, "energy-cost.csv"))==ac["files"]["energy-cost.csv"]||error("费用图源改变")
rows=collect(CSV.File(joinpath(report, "summary.csv")))
flows=collect(CSV.File(joinpath(report, "trajectories.csv")))
res=collect(CSV.File(joinpath(report, "residuals.csv")))
energy=collect(CSV.File(joinpath(audit, "energy-cost.csv")))
controls=["prescribed", "recovery_continuous", "joint_continuous"]
ticks=["Fixed", "Recovery free", "Both free"]
groups=["healthy_zero_loss", "all_faults_heat_limit"]
colors=[:steelblue, :darkorange]
fig=Figure(size = (1830, 1000), fontsize = 17)
Label(
    fig[0, 1:3],
    "F30 | Heat loss and exclusive batteries in shared normal / recovery planning";
    fontsize = 24,
    tellwidth = false,
)
axes_cost=[
    Axis(fig[1, i]; title = title, xticks = (1:3, ticks), ylabel = "Expected normal cost (USD)") for
    (i, title) in enumerate((
        "A  Healthy internal line; no unserved energy",
        "B  All faults; 0.4 MWh loss allowance",
    ))
]
for (ax, group) in zip(axes_cost, groups)
    for (UA, color, offset) in ((0, :steelblue, -0.07), (10, :darkorange, 0.07)),
        (i, control) in enumerate(controls)

        r=only(filter(x->x.id=="ua$(UA)_$(group)_$(control)_gurobi", rows))
        r.model_pass||continue
        scatter!(
            ax,
            [i+offset],
            [r.cost_USD];
            color,
            markersize = 13,
            label = i==1 ? "UA = $UA W/K" : nothing,
        )
        text!(
            ax,
            i+offset,
            r.cost_USD+(UA==0 ? 0.028 : -0.028);
            text = string(round(r.cost_USD; digits = 5)),
            align = (:center, UA==0 ? :bottom : :top),
            fontsize = 13,
            color,
        )
    end
    xlims!(ax, 0.65, 3.35)
    ylims!(ax, group=="healthy_zero_loss" ? (191.65, 192.12) : (192.90, 193.40))
end
Legend(
    fig[2, 1:2],
    axes_cost[1];
    orientation = :horizontal,
    tellwidth = false,
    tellheight = true,
    fontsize = 14,
)
c=Axis(
    fig[1, 3];
    title = "C  Cost certification within adopted models",
    xticks = (
        1:6,
        ["UA0\nfixed", "UA0\nrecovery", "UA0\nboth", "UA10\nfixed", "UA10\nrecovery", "UA10\nboth"],
    ),
    ylabel = "Candidate minus bound / |cost| (%)",
)
for (group, color, marker) in ((groups[1], :forestgreen, :circle), (groups[2], :purple, :rect))
    for (j, UA) in enumerate((0, 10)), (i, control) in enumerate(controls)
        r=only(filter(x->x.id=="ua$(UA)_$(group)_$(control)_gurobi", rows))
        r.model_pass&&!ismissing(r.relative_gap)||continue
        scatter!(
            c,
            [i+3(j-1)],
            [100max(0, r.relative_gap)];
            color,
            marker,
            markersize = 13,
            label = i==1&&j==1 ? (group==groups[1] ? "Healthy" : "All faults; allowance") : nothing,
        )
    end
end
hlines!(c, [0.01]; color = :red, linestyle = :dash, label = "A2 limit")
Legend(fig[2, 3], c; orientation = :horizontal, tellwidth = false, tellheight = true, fontsize = 13)
d=Axis(
    fig[3, 1];
    title = "D  UA10 - UA0 cost identity (fixed flow)",
    xticks = (1:2, ["Healthy", "All faults; allowance"]),
    ylabel = "Expected cost change (USD)",
)
for (i, group) in enumerate(groups)
    base=only(
        filter(
            x->x.UA_W_K==0&&x.safety_group==group&&x.control=="prescribed"&&x.solver=="Gurobi",
            energy,
        ),
    )
    loss=only(
        filter(
            x->x.UA_W_K==10&&x.safety_group==group&&x.control=="prescribed"&&x.solver=="Gurobi",
            energy,
        ),
    )
    for (off, key, color, label) in (
        (-0.23, :loss_effect_USD, :darkorange, "Heat loss / CHP effect"),
        (0.0, :battery_cost_USD, :steelblue, "Battery throughput"),
        (0.23, :cost_USD, :black, "Total cost"),
    )
        barplot!(
            d,
            [i+off],
            [getproperty(loss, key)-getproperty(base, key)];
            color,
            width = 0.19,
            label = i==1 ? label : nothing,
        )
    end
end
hlines!(d, [0.0]; color = :gray)
Legend(fig[4, 1], d; orientation = :vertical, tellwidth = false, tellheight = true, fontsize = 13)
e=Axis(
    fig[3, 2];
    title = "E  Normal flow; UA10 healthy-line case",
    xlabel = "Normal time step (1 h)",
    ylabel = "Mass flow (kg/s)",
    xticks = 1:4,
)
for (control, color, label) in zip(controls, [:gray, :steelblue, :darkorange], ticks)
    id="ua10_healthy_zero_loss_$(control)_gurobi"
    fs=sort(filter(x->x.id==id&&x.stage=="normal", flows); by = x->x.time)
    isempty(fs)||scatterlines!(e, [x.time for x in fs], [x.flow_kg_s for x in fs]; color, label)
end
Legend(fig[4, 2], e; orientation = :vertical, tellwidth = false, tellheight = true, fontsize = 13)
f=Axis(
    fig[3, 3];
    title = "F  Largest residual of accepted candidates",
    yscale = log10,
    xticks = (1:3, ["Normal", "Inherited / electric", "Heat replay"]),
    ylabel = "Residual / A1 threshold",
)
accepted=Set(r.id for r in rows if r.model_pass)
for (UA, color, offset) in ((0, :steelblue, -0.08), (10, :darkorange, 0.08)),
    (i, cat) in enumerate((:normal, :shared, :heat))

    rr=filter(
        x->x.id in accepted&&startswith(x.id, "ua$(UA)_")&&(
            cat==:normal ? startswith(x.stage, "normal") :
            cat==:heat ? startswith(x.stage, "recovery_thermal") :
            startswith(x.stage, "recovery_shared")||startswith(x.stage, "recovery_boundary")
        ),
        res,
    )
    isempty(rr)||scatter!(
        f,
        [i+offset],
        [max(1e-12, maximum(x.residual/x.tolerance for x in rr))];
        color,
        markersize = 14,
    )
end
hlines!(f, [1.0]; color = :red, linestyle = :dash, label = "A1 limit")
ylims!(f, 1e-12, 10)
axislegend(f; position = :rt, fontsize = 13)
passed=count(r->r.model_pass, rows)
complete=count(r->r.cost_complete, rows)
infeasible=count(r->r.status=="infeasible_certified", rows)
noresult=count(r->!r.model_pass&&r.status!="infeasible_certified", rows)
Label(
    fig[5, 1:3],
    "Synthetic input; $passed/24 accepted, $complete/24 cost-certified, $infeasible infeasible, $noresult other/no accepted candidate.\n" *
    "All new runs enforce per-period battery exclusivity. UA applies to each whole supply/return pipe.\n" *
    "Bounds concern the adopted quadrature model, not exact-PDE optimality. Full hydraulic, AC and thesis-scale certification remain open.\n" *
    "No-unserved-energy all-fault cases are retained in the source tables. Residual display floor: 1e-12.";
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
for p in sources
    cp(joinpath(report, p), joinpath(out, p))
end
cp(joinpath(audit, "energy-cost.csv"), joinpath(out, "energy-cost.csv"))
save(joinpath(out, "F30-lossy-flow.png"), fig; px_per_unit = 1)
save(joinpath(out, "F30-lossy-flow.svg"), fig)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "schema"=>"r7-lossy-flow-figure-v1",
    "origin"=>"synthetic",
    "figure"=>"F30",
    "run_ids"=>[r.run_id for r in rows],
    "plot_source_sha256"=>hashfile(@__FILE__),
    "units"=>["USD", "MWh", "kg/s", "W/K", "percent", "residual / tolerance"],
    "report_hashes"=>Dict(p=>hashfile(joinpath(report, p)) for p in sources),
    "audit_hashes"=>Dict("energy-cost.csv"=>hashfile(joinpath(audit, "energy-cost.csv"))),
    "outputs"=>Dict(
        p=>hashfile(joinpath(out, p)) for p in ("F30-lossy-flow.png", "F30-lossy-flow.svg")
    ),
)
open(joinpath(out, "figure.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("F30 generated from saved original results and independent cost audit; no optimization.")
