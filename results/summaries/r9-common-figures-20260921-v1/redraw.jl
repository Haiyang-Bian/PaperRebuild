# 从已封存数值重绘；不加载科学求解器，也不重算优化。
using CairoMakie, TOML, SHA, CSV
length(ARGS)==3 || error("usage: FROZEN_INPUT SEALED_EVIDENCE NEW_FIGURES")
input, evidence, out=abspath.(ARGS)
ispath(out) && error("Preserve previous figures")
hashfile(p) = bytes2hex(sha256(read(p)))
m=TOML.parsefile(joinpath(evidence, "delivery.toml"))
m["input_manifest_sha256"]==hashfile(joinpath(input, "manifest.toml")) || error("Input identity")
for rel in ("run/witness.toml", "run/status.toml", "run/validation-3A.toml")
    hashfile(joinpath(evidence, rel))==m["files"][rel] || error("Changed figure source")
end
frozen=TOML.parsefile(joinpath(input, "manifest.toml"))
hashfile(joinpath(input, "study/template.toml"))==frozen["files"]["study/template.toml"] ||
    error("Changed template")
c=TOML.parsefile(joinpath(input, "study/template.toml"))
w=TOML.parsefile(joinpath(evidence, "run/witness.toml"))
v=TOML.parsefile(joinpath(evidence, "run/validation-3A.toml"))
v["model_pass"] && v["risk_pass"] && v["cost_pass"] || error("Unverified source")
T=length(w["first_stage"]["P_DA_MW"])
temps=w["values"]["τ_IN"]
buildings=c["buildings"]
length(temps)==length(buildings)==36 && T==24 && c["dt_h"]==1.0 || error("Unexpected figure scope")
lower=minimum(b["T_min_K"] for b in buildings)
upper=maximum(b["T_max_K"] for b in buildings)
all(b["T_min_K"]==lower && b["T_max_K"]==upper for b in buildings) ||
    error("Use per-building limits")
trajectory=[
    (;
        hour = t,
        P_PCC_MW = only(w["values"]["P_PCC"])[t],
        R_up_MW = w["first_stage"]["R_up_MW"][t],
        R_down_MW = w["first_stage"]["R_down_MW"][t],
        T_min_K = minimum(b[t] for b in temps),
        T_max_K = maximum(b[t] for b in temps),
        lower_K = lower,
        upper_K = upper,
    ) for t in 1:T
]
residuals=[
    (;
        group = k,
        normalized = x["max_normalized"],
        display = max(x["max_normalized"], 1e-12),
        count = x["count"],
        failed = x["failed"],
    ) for (k, x) in sort(collect(v["groups"]); by = first)
]
fig=Figure(size = (1300, 1150), fontsize = 18)
Label(fig[0, 1], "F44 | Synthetic common feasible witness | 44/38 nodes, 24 h", fontsize = 24)
a=Axis(
    fig[1, 1],
    xlabel = "Hour",
    ylabel = "Grid import (MW)",
    title = "Same controls in all 100 scenarios; zero-reserve / zero-PV equalities",
)
lines!(a, 1:T, [r.P_PCC_MW for r in trajectory]; color = :steelblue, linewidth = 3)
b=Axis(
    fig[2, 1],
    xlabel = "Hour",
    ylabel = "Indoor temperature (K)",
    title = "Range over 36 buildings; original comfort limits",
)
band!(
    b,
    1:T,
    [r.T_min_K for r in trajectory],
    [r.T_max_K for r in trajectory];
    color = (:darkorange, 0.35),
)
lines!(b, 1:T, [r.T_min_K for r in trajectory]; color = :darkorange, label = "Building range")
lines!(b, 1:T, [r.T_max_K for r in trajectory]; color = :darkorange)
hlines!(b, [lower, upper]; color = :black, linestyle = :dash, label = "Comfort bounds")
ylims!(b, lower-0.5, upper+0.5)
axislegend(b; position = :rt)
# 仅显示用的正下限；原始零值与所有数值仍写入图源表。
groups=["electric", "heat", "comfort", "delivery", "cost"]
maxima=[
    maximum(
        (r.normalized for r in residuals if startswith(r.group, "physical/"*g*"/"));
        init = 0.0,
    ) for g in groups
]
d=Axis(
    fig[3, 1],
    ylabel = "Residual / A1 tolerance",
    yscale = log10,
    xticks = (1:length(groups), groups),
    title = "Maximum across every original scenario (3A; 3B/3C checked separately)",
)
scatter!(d, 1:length(groups), max.(maxima, 1e-12); color = :seagreen, markersize = 14)
hlines!(d, [1.0]; color = :firebrick, linestyle = :dash, label = "A1 acceptance threshold")
ylims!(d, 1e-12, 10)
axislegend(d; position = :rt)
Label(
    fig[4, 1],
    "Feasible cost upper bound: "*string(round(v["worst_net_cost"]; digits = 6))*" CNY/day. No risk-optimality or held-out claim.",
    fontsize = 16,
)
Label(fig[5, 1], w["run_id"], fontsize = 14)
mkpath(out)
CSV.write(joinpath(out, "trajectories.csv"), trajectory)
CSV.write(joinpath(out, "residuals.csv"), residuals)
for ext in ("png", "pdf")
    save(joinpath(out, "F44-common-witness."*ext), fig)
end
cp(@__FILE__, joinpath(out, "redraw.jl"))
meta=Dict(
    "schema"=>"r9-common-figure-v1",
    "origin"=>"synthetic",
    "run_id"=>w["run_id"],
    "input_sha256"=>hashfile(joinpath(input, "manifest.toml")),
    "evidence_sha256"=>hashfile(joinpath(evidence, "delivery.toml")),
    "optimization_performed"=>false,
    "residual_display_floor"=>1e-12,
    "units"=>["MW", "K", "h", "CNY/day", "residual/tolerance"],
    "files"=>Dict(name=>hashfile(joinpath(out, name)) for name in readdir(out)),
)
open(io->TOML.print(io, meta; sorted = true), joinpath(out, "figure-source.toml"), "w")
println("F44 rendered from saved original controls; no optimization.")
