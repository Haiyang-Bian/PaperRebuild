include("r3_setup.jl")
root="results/runs/r3-v3-audit-20260917T104953"
a=TOML.parsefile(joinpath(root, "failure.toml"));
c=load_r2_case(joinpath(root, "case.toml"))
r=only(x["record"] for x in a["selected"] if x["role"]=="minimum_cost")
v=deepcopy(r["values"]);
d, h=c.data, c.data["heat"]
o=PaperRebuild.r3_operation_from_dict(r["operation"])
# 本冻结反例为按节点编号的有向树；按时段、上游到下游唯一确定CT供水。
all(e["from"]<e["to"] for e in h["pipes"]) || error("需显式拓扑排序")
for t in 1:d["T"], j in eachindex(h["nodes"])
    n=h["nodes"][j]
    incoming=[
        (v["m_pipe"][p][t], v["tau_S_out"][p][t]) for (p, e) in enumerate(h["pipes"]) if e["to"]==j
    ]
    n["role"]=="source" && push!(incoming, (v["m_port"][j][t], o.source_temperature_K))
    mix=sum(m*T for (m, T) in incoming)/sum(first, incoming)
    v["tau_S_mix"][j][t]=mix
    v["tau_S_port"][j][t]=n["role"]=="source" ? o.source_temperature_K : mix
    for (p, e) in enumerate(h["pipes"])
        e["from"]==j || continue
        v["tau_S_in"][p][t]=mix
        replay=PaperRebuild.r3_mass_replay(c, v, p, t, "S")
        v["tau_S_star"][p][t]=replay.star
        v["tau_S_out"][p][t]=replay.out
    end
end
rows=Any[]
for (j, n) in enumerate(h["nodes"]), t in 1:d["T"]
    n["role"]=="load" || continue
    cap=h["cp_J_kgK"]/1e6*v["m_port"][j][t]*(v["tau_S_port"][j][t]-h["R_bounds_K"][1])
    tail=t>o.core_periods
    imposed=tail ? h["cp_J_kgK"]/1e6*v["m_port"][j][t]*(v["tau_S_port"][j][t]-n["return_K"]) : NaN
    delta=n["H_MW"][t]-cap
    push!(
        rows,
        Dict(
            "node"=>j,
            "t"=>t,
            "H_required_MW"=>n["H_MW"][t],
            "H_max_at_saved_supply_MW"=>cap,
            "deficit_MW"=>delta,
            "supply_K"=>v["tau_S_port"][j][t],
            "return_K"=>v["tau_R_port"][j][t],
            "return_lower_K"=>h["R_bounds_K"][1],
            "flow_kg_s"=>v["m_port"][j][t],
            "tail"=>tail,
            "tail_equality_mismatch_MW"=>tail ? imposed-n["H_MW"][t] : 0.0,
        ),
    )
    tail && abs(imposed-n["H_MW"][t])>1e-9 && println(last(rows))
end
target=joinpath("results", "runs", "r3-v3-heat-bound-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
mkpath(target)
open(joinpath(target, "bound.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "input_sha256"=>c.sha256,
            "scope"=>"fixed_CT_supply_unique_causal_replay",
            "rows"=>rows,
        );
        sorted = true,
    )
end
println(target)
