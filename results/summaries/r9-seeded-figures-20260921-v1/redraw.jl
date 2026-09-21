# 只读取已封存的求解结果；不导入求解器、不重新优化。
using CairoMakie, TOML, SHA, CSV
length(ARGS)==3 || error("usage: SEEDED_EVIDENCE COMMON_EVIDENCE NEW_FIGURES")
evidence, common, out=abspath.(ARGS)
ispath(out) && error("Preserve previous figure")
hashfile(p) = bytes2hex(sha256(read(p)))
m=TOML.parsefile(joinpath(evidence, "delivery.toml"))
parent=TOML.parsefile(joinpath(common, "delivery.toml"))
for (root, manifest) in ((evidence, m), (common, parent)), (p, h) in manifest["files"]
    hashfile(joinpath(root, p))==h || error("Changed figure input")
end
baseline=TOML.parsefile(joinpath(common, "run/validation-3A.toml"))["worst_net_cost"]
rows=NamedTuple[]
trajectories=NamedTuple[]
residuals=NamedTuple[]
for scheme in ("3A", "3B", "3C")
    s=TOML.parsefile(joinpath(evidence, scheme, "status.toml"))
    r=TOML.parsefile(joinpath(evidence, scheme, "run/result.toml"))
    v=TOML.parsefile(joinpath(evidence, scheme, "run/validation.toml"))
    checked=v["model_pass"] && v["risk_pass"] && v["cost_pass"]
    push!(
        rows,
        (;
            scheme,
            status = s["status"],
            has_candidate = s["has_candidate"],
            checked,
            elapsed_sec = s["elapsed_sec"],
            budget_pass = s["budget_pass"],
            feasible_cost_CNY = checked ? v["worst_net_cost"] : NaN,
            solver_lower_CNY = get(r, "solver_objective_bound", NaN),
            valid_bound = get(v, "valid_bound", false) &&
                          abs(get(r, "solver_objective_bound", Inf))<1e90,
            relative_gap = get(v, "relative_gap", NaN),
            optimality_pass = v["optimality_pass"],
            run_id = r["run_id"],
        ),
    )
    if haskey(r, "first_stage")
        x=r["first_stage"]
        for t in eachindex(x["P_DA_MW"])
            push!(
                trajectories,
                (;
                    scheme,
                    hour = t,
                    P_DA_MW = x["P_DA_MW"][t],
                    R_up_MW = x["R_up_MW"][t],
                    R_down_MW = x["R_down_MW"][t],
                    checked,
                ),
            )
        end
    end
    for (key, g) in get(v, "groups", Dict())
        push!(
            residuals,
            (;
                scheme,
                group = key,
                count = g["count"],
                failed = g["failed"],
                normalized = g["max_normalized"],
            ),
        )
    end
end
fig=Figure(size = (1280, 1200), fontsize = 18)
Label(
    fig[0, 1:2],
    "F45 | Synthetic 100-scenario models | Explicit feasible initialization",
    fontsize = 24,
)
a=Axis(
    fig[1, 1],
    xticks = (1:3, ["3A", "3B", "3C"]),
    ylabel = "Cost (CNY/day)",
    title = "Verified upper bound and solver lower bound",
)
hlines!(a, [baseline]; color = :gray, linestyle = :dash, label = "Common feasible seed")
for (i, r) in enumerate(rows)
    r.checked && scatter!(
        a,
        [i],
        [r.feasible_cost_CNY];
        color = :seagreen,
        markersize = 16,
        label = r.scheme*" verified candidate",
    )
    r.valid_bound && scatter!(
        a,
        [i],
        [r.solver_lower_CNY];
        color = :steelblue,
        marker = :utriangle,
        markersize = 15,
        label = r.scheme*" valid lower bound",
    )
    !r.checked && text!(
        a,
        i,
        baseline;
        text = "No verified candidate",
        rotation = pi/2,
        align = (:right, :center),
        fontsize = 13,
    )
end
axislegend(a; position = :rb, labelsize = 12)
b=Axis(
    fig[1, 2],
    xticks = (1:3, ["3A", "3B", "3C"]),
    ylabel = "Complete process (s)",
    title = "600 s shared deadline, including validation",
)
barplot!(b, 1:3, [r.elapsed_sec for r in rows]; color = :steelblue)
hlines!(b, [600]; color = :firebrick, linestyle = :dash)
c=Axis(
    fig[2, 1:2],
    xlabel = "Hour",
    ylabel = "Reserve (MW)",
    title = "Actual returned candidate; up = solid, down = dashed",
)
colors=[:seagreen, :steelblue, :darkorange]
for (i, scheme) in enumerate(("3A", "3B", "3C"))
    pts=filter(r->r.scheme==scheme, trajectories)
    isempty(pts) && continue
    lines!(c, [r.hour for r in pts], [r.R_up_MW for r in pts]; color = colors[i], label = scheme)
    lines!(
        c,
        [r.hour for r in pts],
        [r.R_down_MW for r in pts];
        color = colors[i],
        linestyle = :dash,
    )
end
isempty(trajectories) || axislegend(c; position = :rt)
small_reserves=!isempty(trajectories) &&
               maximum(max(abs(r.R_up_MW), abs(r.R_down_MW)) for r in trajectories)<=1e-9
small_reserves && ylims!(c, -0.01, 0.01)
d=Axis(
    fig[3, 1:2],
    ylabel = "Maximum residual / tolerance",
    yscale = log10,
    xticks = (1:3, ["3A", "3B", "3C"]),
    title = "Original independent checks; A1/A2 unchanged",
)
for (i, scheme) in enumerate(("3A", "3B", "3C"))
    rs=filter(r->r.scheme==scheme, residuals)
    isempty(rs) && continue
    scatter!(
        d,
        [i],
        [max(1e-12, maximum(r.normalized for r in rs))];
        color = colors[i],
        markersize = 15,
    )
end
hlines!(d, [1]; color = :firebrick, linestyle = :dash)
Label(
    fig[4, 1:2],
    "Same physical inputs. Seed + LP method + time allocation are combined changes; no isolated speedup claim.",
    fontsize = 14,
)
Label(fig[5, 1:2], join([r.scheme*": "*r.status*" | "*r.run_id for r in rows], "\n"), fontsize = 12)
mkpath(out)
CSV.write(joinpath(out, "summary.csv"), rows)
if isempty(trajectories)
    write(joinpath(out, "commitments.csv"), "scheme,hour,P_DA_MW,R_up_MW,R_down_MW,checked\n")
else
    CSV.write(joinpath(out, "commitments.csv"), trajectories)
end
if isempty(residuals)
    write(joinpath(out, "residuals.csv"), "scheme,group,count,failed,normalized\n")
else
    CSV.write(joinpath(out, "residuals.csv"), residuals)
end
for ext in ("png", "pdf")
    save(joinpath(out, "F45-seeded-risk."*ext), fig)
end
cp(@__FILE__, joinpath(out, "redraw.jl"))
meta=Dict(
    "schema"=>"r9-seeded-figure-v1",
    "origin"=>"synthetic",
    "optimization_performed"=>false,
    "evidence_sha256"=>hashfile(joinpath(evidence, "delivery.toml")),
    "common_sha256"=>hashfile(joinpath(common, "delivery.toml")),
    "units"=>["CNY/day", "MW", "h", "s", "residual/tolerance"],
    "residual_display_floor"=>1e-12,
    "small_reserve_display_band"=>small_reserves,
    "run_ids"=>[r.run_id for r in rows],
    "files"=>Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out)),
)
open(io->TOML.print(io, meta; sorted = true), joinpath(out, "figure-source.toml"), "w")
println("F45 redrawn from saved original values; no optimization.")
