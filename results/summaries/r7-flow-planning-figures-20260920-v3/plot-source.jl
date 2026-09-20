using CSV, TOML, SHA, CairoMakie
length(ARGS)==2 || error("usage: plot_r7_flow_planning.jl REPORT NEW_FIGURES")
src, out=abspath.(ARGS)
ispath(out)&&error("不覆盖联合规划图件")
hashfile(p) = bytes2hex(sha256(read(p)))
files=["summary.csv", "events.csv", "trajectories.csv", "residuals.csv", "rule.toml"]
registry=TOML.parsefile(joinpath(src, "report-hashes.toml"))["files"]
all(hashfile(joinpath(src, p))==registry[p] for p in files) || error("联合规划图源已变")
summary=collect(CSV.File(joinpath(src, "summary.csv")))
events=collect(CSV.File(joinpath(src, "events.csv")))
flows=collect(CSV.File(joinpath(src, "trajectories.csv")))
residuals=collect(CSV.File(joinpath(src, "residuals.csv")))
groups=["healthy_zero_loss", "all_faults_heat_limit"]
labels=["Healthy line; zero loss", "All faults; heat-loss allowance"]
controls=["prescribed", "recovery_continuous", "joint_continuous"]
ticks=["Fixed", "Recovery flow", "Both flows"]
colors=[:steelblue, :darkorange]
fig=Figure(size = (1500, 1050), fontsize = 18)
Label(
    fig[0, :],
    "F29 | One normal plan, variable recovery flow (synthetic, pipe UA = 0)";
    fontsize = 23,
    tellwidth = false,
)
a=Axis(
    fig[1, 1];
    title = "A  Normal cost within each safety boundary",
    xticks = (1:3, ticks),
    ylabel = "Expected cost (USD)",
)
b=Axis(
    fig[1, 2];
    title = "B  Largest loss of the saved recovery witnesses",
    xticks = (1:3, ticks),
    ylabel = "Expected unserved energy (MWh)",
)
for (g, label, color) in zip(groups, labels, colors)
    for (i, control) in enumerate(controls)
        r=only(filter(x->x.group==g&&x.control==control&&x.solver=="Gurobi", summary))
        r.model_pass||continue
        scatter!(a, [i], [r.cost_USD]; color, markersize = 15, label = i==1 ? label : nothing)
        ismissing(r.lower_bound_USD)||lines!(
            a,
            [i, i],
            [r.lower_bound_USD, r.cost_USD];
            color,
            linewidth = 3,
        )
        text!(
            a,
            i,
            r.cost_USD+0.05;
            text = string(round(r.cost_USD; digits = 5)),
            align = (:center, :bottom),
            fontsize = 14,
            color,
        )
        er=filter(x->x.id==r.id, events)
        loss=maximum(x.loss_MWh for x in er)
        scatter!(b, [i], [loss]; color, markersize = 15, label = i==1 ? label : nothing)
    end
end
axislegend(a; position = :rc, fontsize = 13)
xlims!(a, 0.7, 3.3)
xlims!(b, 0.7, 3.3)
hlines!(b, [0.0, 0.4]; color = :gray, linestyle = :dash)
ylims!(b, -0.04, 0.5)
c=Axis(
    fig[2, 1];
    title = "C  Shared flow: all faults, 0.4 MWh allowance",
    xlabel = "Normal hour / event hour",
    ylabel = "Mass flow (kg/s)",
    xticks = 1:4,
)
id="all_faults_heat_limit_joint_continuous_gurobi"
nr=sort(filter(x->x.id==id&&x.stage=="normal", flows); by = x->x.time)
isempty(nr)||scatterlines!(
    c,
    [x.time for x in nr],
    [x.flow_kg_s for x in nr];
    color = :forestgreen,
    label = "Normal plan",
)
for (fault, color, marker) in (("0", :steelblue, :circle), ("1", :darkorange, :rect))
    rr=sort(filter(x->x.id==id&&x.stage=="recovery"&&string(x.fault)==fault, flows); by = x->x.time)
    isempty(rr)||scatter!(
        c,
        [x.time for x in rr],
        [x.flow_kg_s for x in rr];
        color,
        marker,
        markersize = 17,
        label = fault=="0" ? "Recovery: healthy internal line" : "Recovery: failed internal line",
    )
end
Legend(fig[3, :], c; orientation = :horizontal, fontsize = 13, tellwidth = false)
d=Axis(
    fig[2, 2];
    title = "D  Largest normalized residual by constraint block",
    yscale = log10,
    xticks = (1:3, ["Normal", "Boundary / electric", "Thermal replay"]),
    ylabel = "Residual / A1 threshold",
)
for (i, category) in enumerate((:normal, :shared, :thermal))
    r=filter(
        x->x.id==id&&(
            category==:normal ? startswith(x.stage, "normal") :
            category==:thermal ? startswith(x.stage, "recovery_thermal") :
            startswith(x.stage, "recovery_shared")||startswith(x.stage, "recovery_boundary")
        ),
        residuals,
    )
    isempty(r)||scatter!(
        d,
        [i],
        [max(1e-12, maximum(x.residual/x.tolerance for x in r))];
        color = :forestgreen,
        markersize = 14,
    )
end
hlines!(d, [1.0]; color = :red, linestyle = :dash, label = "A1 limit")
ylims!(d, 1e-12, 10)
xlims!(d, 0.5, 3.5)
axislegend(d; position = :rt, fontsize = 13)
infeasible=count(x->x.group=="all_faults_zero_loss"&&x.status=="infeasible_certified", summary)
Label(
    fig[4, :],
    "All-fault zero-loss requirement: $infeasible of 4 runs proved infeasible in the declared domain.\n" *
    "Recovery points are alternative events, not one consecutive trajectory. Residual display floor: 1e-12.\n" *
    "Witness losses are feasible values, not minimum-loss claims. No full hydraulic, AC or thesis-scale certification.\n" *
    "Two adopted-model candidates fail the additional nonsimultaneous battery check; original summed-power domain retained.";
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
for p in files
    cp(joinpath(src, p), joinpath(out, p))
end
save(joinpath(out, "F29-shared-flow.png"), fig; px_per_unit = 1)
save(joinpath(out, "F29-shared-flow.svg"), fig)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
config=Dict(
    "schema"=>"r7-shared-flow-figure-v1",
    "origin"=>"synthetic",
    "figure"=>"F29",
    "run_ids"=>[x.run_id for x in summary],
    "plot_source_sha256"=>hashfile(@__FILE__),
    "units"=>["USD", "MWh", "kg/s", "residual / tolerance"],
    "report_hashes"=>Dict(p=>hashfile(joinpath(src, p)) for p in files),
    "outputs"=>Dict(
        p=>hashfile(joinpath(out, p)) for p in ("F29-shared-flow.png", "F29-shared-flow.svg")
    ),
)
open(joinpath(out, "figure.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
println("F29 saved from original records; no re-optimization.")
