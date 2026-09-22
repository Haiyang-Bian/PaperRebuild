using CSV, TOML, SHA, CairoMakie
length(ARGS)==3 || error("usage: plot_r8_energy.jl REPORT AUDIT NEW_FIGURES")
report, audit, out=abspath.(ARGS)
ispath(out)&&error("不覆盖能流图件")
hashfile(p) = bytes2hex(sha256(read(p)))
reg=TOML.parsefile(joinpath(report, "report-hashes.toml"))["files"]
for p in ("summary.csv", "hand-witness.csv", "rule.toml")
    hashfile(joinpath(report, p))==reg[p] || error("图源改变")
end
a=TOML.parsefile(joinpath(audit, "audit.toml"))
a["report_manifest_sha256"]==hashfile(joinpath(report, "report-hashes.toml")) ||
    error("审计归属错误")
all(hashfile(joinpath(audit, p))==h for (p, h) in a["files"]) || error("审计改变")
summary=collect(CSV.File(joinpath(report, "summary.csv")))
traces=collect(CSV.File(joinpath(audit, "trajectories.csv"); types = Dict(:fault=>String)))
hand=collect(CSV.File(joinpath(report, "hand-witness.csv")))
res=vcat([collect(CSV.File(joinpath(audit, p))) for p in a["residual_parts"]]...)
fig=Figure(size = (1760, 1440), fontsize = 19)
Label(fig[0, 1:2], "F32 | Intertemporal heat storage versus steady energy flow"; fontsize = 28)
Label(
    fig[1, 1:2],
    "Synthetic four-hour outage | fixed 5 kg/s detailed flow | shared resources, loads and prices";
    fontsize = 18,
)
colors=Dict("detailed"=>:steelblue, "energy"=>:darkorange)
names=Dict("detailed"=>"Detailed transport", "energy"=>"Steady energy flow")
ax=Axis(
    fig[2, 1],
    title = "Independent worst-event recovery",
    ylabel = "Expected unserved energy (MWh)",
    xticks = (1:4, ["UA0 / economic", "UA0 / penalty", "UA10 / economic", "UA10 / penalty"]),
    xticklabelrotation = 0.13,
)
bx=Axis(
    fig[2, 2],
    title = "Normal costs under the economic objective",
    ylabel = "Expected normal cost (USD)",
    xticks = ([1, 2], ["UA = 0 W/K", "UA = 10 W/K"]),
)
for model in ("detailed", "energy")
    offset=model=="detailed" ? -0.14 : 0.14
    for (k, (ua, mode)) in
        enumerate(((0, "economic"), (0, "penalty"), (10, "economic"), (10, "penalty")))
        r=only(
            filter(
                r->r.family=="shift_four"&&r.UA_W_K==ua&&r.mode==mode&&r.model==model&&r.solver=="Gurobi",
                summary,
            ),
        )
        r.evaluation_pass || error("不能将未核验评估绘制为风险")
        scatter!(
            ax,
            [k+offset],
            [r.worst_upper_MWh];
            color = colors[model],
            markersize = 15,
            label = k==1 ? names[model] : nothing,
        )
    end
    for (k, ua) in enumerate((0, 10))
        r=only(
            filter(
                r->r.family=="shift_four"&&r.UA_W_K==ua&&r.mode=="economic"&&r.model==model&&r.solver=="Gurobi",
                summary,
            ),
        )
        barplot!(
            bx,
            [k+offset],
            [r.normal_cost_USD];
            width = 0.25,
            color = colors[model],
            label = k==1 ? names[model] : nothing,
        )
        text!(
            bx,
            k+offset,
            r.normal_cost_USD;
            text = string(round(r.normal_cost_USD; digits = 4)),
            align = (:center, :bottom),
            offset = (0, 8),
            fontsize = 16,
        )
    end
end
ylims!(ax, -0.01, 0.24)
ylims!(bx, 0, 240)
axislegend(ax; position = :lt, labelsize = 16)
axislegend(bx; position = :lt, labelsize = 16)
cx=Axis(
    fig[3, 1],
    title = "Heat delivery: one declared recovery witness",
    xlabel = "Outage hour",
    ylabel = "Heat power (MW)",
    xticks = 1:4,
)
dx=Axis(
    fig[3, 2],
    title = "Electric boiler use in that witness",
    xlabel = "Outage hour",
    ylabel = "Electrical input (MW)",
    xticks = 1:4,
)
ex=Axis(
    fig[4, 1],
    title = "Stored heat from independent parcel replay",
    xlabel = "Outage hour",
    ylabel = "Change from initial inventory (MWh)",
    xticks = 0:4,
)
selected=NamedTuple[]
chosen=Dict{String,String}()
for model in ("detailed", "energy")
    rows=filter(
        r->r.model==model&&r.UA_W_K==0&&r.mode=="economic"&&r.solver=="Gurobi"&&r.scenario==1,
        traces,
    )
    fault=first(sort!(unique(string(r.fault) for r in rows)))
    rows=sort(filter(r->string(r.fault)==fault, rows); by = r->r.t)
    length(rows)==4||error("选定的四小时见证不完整")
    chosen[model]=rows[1].id*"/event1/fault"*fault*"/scenario1"
    lines!(
        cx,
        [r.t for r in rows],
        [r.source_MW for r in rows];
        color = colors[model],
        linewidth = 3,
        label = names[model]*" source",
    )
    scatter!(
        cx,
        [r.t for r in rows],
        [r.source_MW for r in rows];
        color = colors[model],
        markersize = 10,
    )
    lines!(
        dx,
        [r.t for r in rows],
        [r.EB_MW for r in rows];
        color = colors[model],
        linewidth = 3,
        label = names[model],
    )
    if model=="detailed"
        lines!(
            ex,
            0:4,
            [0.0; [r.stored_above_initial_MWh for r in rows]];
            color = colors[model],
            linewidth = 3,
            label = "Optimized recovery (free end state)",
        )
    end
    append!(selected, NamedTuple.(rows))
end
hlines!(cx, [0.4]; color = :black, linestyle = :dash, label = "Heat demand")
lines!(
    ex,
    0:4,
    [0.0; [r.stored_above_initial_MWh for r in hand]];
    color = :seagreen,
    linestyle = :dash,
    linewidth = 3,
    label = "Separate analytic cyclic witness",
)
hlines!(ex, [0.0]; color = :gray, linestyle = :dot)
axislegend(cx; position = :rt, labelsize = 15)
axislegend(dx; position = :rt, labelsize = 16)
axislegend(ex; position = :lb, labelsize = 15)
fx=Axis(
    fig[4, 2],
    title = "All candidate constraints, unchanged A1",
    xlabel = "Frozen record index",
    ylabel = "Maximum residual / A1 tolerance",
    yscale = log10,
)
points=NamedTuple[]
for (i, r) in enumerate(summary)
    rr=filter(z->z.id==r.id, res)
    isempty(rr)&&continue
    ratio=maximum(z.tolerance>0 ? z.residual/z.tolerance : z.residual==0 ? 0.0 : Inf for z in rr)
    push!(points, (index = i, id = r.id, run_id = r.run_id, residual_ratio = ratio))
    scatter!(
        fx,
        [i],
        [max(1e-12, ratio)];
        color = ratio<=1 ? :seagreen : :firebrick,
        markersize = 9,
    )
end
hlines!(fx, [1.0]; color = :firebrick, linestyle = :dash)
ylims!(fx, 1e-12, 10)
Label(
    fig[5, 1:2],
    "Zero-unserved thresholds: detailed feasible; steady infeasible. UA10 also changes the loss representation.";
    fontsize = 17,
)
Label(
    fig[6, 1:2],
    "Trajectories: Gurobi economic plan, UA0, first declared fault, scenario 1. No cyclic recovery boundary imposed.";
    fontsize = 17,
)
Label(
    fig[7, 1:2],
    "The green trajectory is an independent hand construction, not another optimized run. Missing residual points are not zero.";
    fontsize = 16,
)
mkpath(out)
save(joinpath(out, "F32-r8-energy.png"), fig; px_per_unit = 1.5)
for p in ("summary.csv", "hand-witness.csv")
    cp(joinpath(report, p), joinpath(out, p))
end
CSV.write(joinpath(out, "selected-trajectories.csv"), selected)
CSV.write(joinpath(out, "residual-points.csv"), points)
cp(@__FILE__, joinpath(out, "plot-source.jl"))
write(
    joinpath(out, "figure.toml"),
    sprint(
        io->TOML.print(
            io,
            Dict(
                "figure"=>"F32",
                "origin"=>"synthetic",
                "report_manifest_sha256"=>hashfile(joinpath(report, "report-hashes.toml")),
                "audit_sha256"=>hashfile(joinpath(audit, "audit.toml")),
                "run_ids"=>String[r.run_id for r in summary],
                "selected_witnesses"=>chosen,
                "layout_size"=>[1760, 1440],
                "pixels_per_layout_unit"=>1.5,
                "size_pixels"=>[2640, 2160],
                "units"=>["USD", "MWh", "MW", "W/K", "dimensionless residual ratio"],
                "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out)),
            );
            sorted = true,
        ),
    ),
)
println("F32 generated from immutable results and the separately labelled analytic witness.")
