using CSV, TOML, SHA, CairoMakie
length(ARGS)==2 || error("usage: plot_r7_normal_flow.jl REPORT NEW_FIGURES")
src, out=abspath.(ARGS);
ispath(out)&&error("不覆盖连续流量图件")
registry=TOML.parsefile(joinpath(src, "report-hashes.toml"))["files"]
files=["summary.csv", "trajectories.csv", "rule.toml"]
hashfile(p) = bytes2hex(sha256(read(p)))
for p in files
    hashfile(joinpath(src, p))==registry[p] || error("连续流量图源改变")
end
summary=collect(CSV.File(joinpath(src, "summary.csv")))
trajectories=collect(CSV.File(joinpath(src, "trajectories.csv")))
number(x) = x isa Real ? Float64(x) : parse(Float64, x)
groups=["original_hand", "reserve", "varying_prices"]
names=["Original hand", "Reserve", "Varying prices"]
fig=Figure(size = (1450, 1050), fontsize = 18)
Label(
    fig[0, :],
    "F28 | Continuous positive normal flow (synthetic, zero heat loss)";
    fontsize = 23,
    tellwidth = false,
)
a=Axis(
    fig[1, 1];
    title = "A  Same input: normal operating cost",
    xticks = (1:3, names),
    ylabel = "Expected cost (USD)",
)
for (j, control, color) in ((1, "prescribed", :steelblue), (2, "continuous", :darkorange))
    for (i, g) in enumerate(groups)
        r=only(filter(x->x.group==g&&x.solver=="Gurobi"&&x.control==control, summary))
        if r.model_pass
            value_=number(r.cost_USD)
            x=i+(j==1 ? -0.09 : 0.09)
            scatter!(a, [x], [value_]; color, markersize = 14, label = i==1 ? control : nothing)
            if !ismissing(r.lower_bound_USD)
                lines!(a, [x, x], [number(r.lower_bound_USD), value_]; color, linewidth = 3)
            end
            text!(
                a,
                x,
                value_+(j==1 ? 4 : 15);
                text = string(round(value_; digits = 3)),
                align = (:center, :bottom),
                fontsize = 14,
            )
        else
            text!(
                a,
                i,
                20+20j;
                text = string(r.status),
                align = (:center, :bottom),
                rotation = pi/2,
                fontsize = 12,
            )
        end
    end
end
axislegend(a; position = :lt)
passed=filter(r->r.model_pass, summary)
isempty(passed)||ylims!(a, 0, maximum(number(r.cost_USD) for r in passed)+45)
b=Axis(
    fig[1, 2];
    title = "B  Selected continuous flow (shared scenarios)",
    xlabel = "Interval (h)",
    ylabel = "Mass flow (kg/s)",
    xticks = 1:4,
)
for (g, color) in zip(groups, [:darkorange, :forestgreen, :purple])
    rows=sort(
        filter(
            r->r.group==g&&r.control=="continuous"&&r.solver=="Gurobi"&&r.scenario==1&&r.pipe==1,
            trajectories,
        );
        by = x->x.time_h,
    )
    isempty(rows)||scatterlines!(
        b,
        [r.time_h for r in rows],
        number.([r.flow_kg_s for r in rows]);
        color,
        label = names[findfirst(==(g), groups)],
    )
end
hlines!(b, [5.0]; color = :steelblue, linestyle = :dash, label = "Prescribed 5 kg/s")
axislegend(b; position = :lt)
c=Axis(
    fig[2, 1];
    title = "C  Supply outlet: varying-price input, scenario 1",
    xlabel = "Interval (h)",
    ylabel = "Temperature (K)",
    xticks = 1:4,
)
e=Axis(
    fig[2, 2];
    title = "D  Supply inventory: same input and scenario",
    xlabel = "End of interval (h)",
    ylabel = "Relative heat (MWh)",
    xticks = 1:4,
)
for (control, color) in (("prescribed", :steelblue), ("continuous", :darkorange))
    rows=sort(
        filter(
            r->r.group=="varying_prices"&&r.control==control&&r.solver=="Gurobi"&&r.scenario==1&&r.pipe==1,
            trajectories,
        );
        by = x->x.time_h,
    )
    if !isempty(rows)
        t=[r.time_h for r in rows]
        scatterlines!(c, t, number.([r.outlet_S_K for r in rows]); color, label = control)
        scatterlines!(e, t, number.([r.inventory_S_MWh for r in rows]); color, label = control)
    end
end
axislegend(c; position = :lb);
axislegend(e; position = :rb)
Label(
    fig[3, :],
    "Prescribed and continuous domains use identical physics and inputs. Bounds shown only where available.\nNo disaster guarantee; no claim for nonzero heat loss, reverse flow or continuous node dynamics.";
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
for p in files
    cp(joinpath(src, p), joinpath(out, p))
end
save(joinpath(out, "F28-normal-flow.png"), fig; px_per_unit = 1)
save(joinpath(out, "F28-normal-flow.svg"), fig)
config=Dict(
    "schema"=>"r7-normal-flow-figures-v1",
    "figure"=>"F28",
    "origin"=>"synthetic",
    "run_ids"=>String.(getproperty.(summary, :run_id)),
    "source_hashes"=>Dict(p=>registry[p] for p in files),
    "units"=>["USD", "kg/s", "K", "MWh", "h"],
    "script_sha256"=>hashfile(@__FILE__),
    "source_of_values"=>"saved_results_no_solver",
)
open(joinpath(out, "figure-config.toml"), "w") do io
    TOML.print(io, config; sorted = true)
end
manifest=Dict(f=>hashfile(joinpath(out, f)) for f in readdir(out))
open(joinpath(out, "files.toml"), "w") do io
    TOML.print(io, Dict("files"=>manifest); sorted = true)
end
println("F28 drawn from frozen values only.")
