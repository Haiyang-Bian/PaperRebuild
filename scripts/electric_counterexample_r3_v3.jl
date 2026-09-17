include("r3_setup.jl")
push!(LOAD_PATH, joinpath(@__DIR__, "..", "tools", "solvers"))
using Gurobi
c=load_r2_case("results/summaries/r3-v3/audit/case.toml")
a=TOML.parsefile("results/summaries/r3-v3/audit/failure.toml")
s=only(x["record"] for x in a["selected"] if x["role"]=="minimum_cost")
d, e=c.data, c.data["electric"];
t=3;
N=length(e["nodes"]);
B=length(e["edges"]);
base=e["base_MVA"]
injection=[
    sum(
        (g["kind"]=="EB" ? -1 : 1)*s["values"]["P_device"][i][t] for
        (i, g) in enumerate(d["devices"]) if g["electric_node"]==n;
        init = 0.0,
    )-e["nodes"][n]["P_MW"][t] for n in 1:N
]
out=Dict{String,Any}(
    "input_sha256"=>c.sha256,
    "parent_flow_sha256"=>s["flow_sha256"],
    "t"=>t,
    "frozen_net_injection_MW"=>injection,
    "scope"=>"single_period_fixed_device_outputs_electrical_only",
    "runs"=>Any[],
)
factory=r3_gurobi_factory(Gurobi)
for form in ("socp", "physical_nonnegative_grid", "physical_export_counterfactual")
    model=Model(factory)
    set_silent(model)
    for (key, value) in (
        "NonConvex"=>2,
        "Threads"=>1,
        "Seed"=>0,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "TimeLimit"=>60.0,
    )
        set_optimizer_attribute(model, key, value)
    end
    limit=e["grid_max_MW"]/base
    @variable(model, -limit<=P[1:B]<=limit)
    @variable(model, -limit<=Q[1:B]<=limit)
    @variable(model, e["v_min_pu"]^2<=v[1:N]<=e["v_max_pu"]^2)
    @variable(model, 0<=ell[b=1:B]<=e["edges"][b]["ell_max_pu"])
    @variable(model, 0<=grid<=e["grid_max_MW"])
    @variable(model, -e["grid_max_MW"]<=qgrid<=e["grid_max_MW"])
    form=="physical_export_counterfactual" && set_lower_bound(grid, -e["grid_max_MW"])
    fix(v[1], 1; force = true)
    for (b, edge) in enumerate(e["edges"])
        i, j, r, x=edge["from"], edge["to"], edge["r_pu"], edge["x_pu"]
        @constraint(model, v[j]==v[i]-2(r*P[b]+x*Q[b])+(r^2+x^2)*ell[b])
        @constraint(model, [v[i]+ell[b], 2P[b], 2Q[b], ell[b]-v[i]] in SecondOrderCone())
        form=="socp" || @constraint(model, v[i]*ell[b]==P[b]^2+Q[b]^2)
    end
    for n in 1:N
        inc=findall(x->x["to"]==n, e["edges"])
        outgoing=findall(x->x["from"]==n, e["edges"])
        @constraint(
            model,
            injection[n]/base+(n==1 ? grid/base : 0)+sum(
                P[b]-e["edges"][b]["r_pu"]*ell[b] for b in inc;
                init = 0.0,
            )==sum(P[b] for b in outgoing; init = 0.0)
        )
        @constraint(
            model,
            (n==1 ? qgrid/base : 0)-e["nodes"][n]["Q_Mvar"][t]/base+sum(
                Q[b]-e["edges"][b]["x_pu"]*ell[b] for b in inc;
                init = 0.0,
            )==sum(Q[b] for b in outgoing; init = 0.0)
        )
    end
    @objective(model, Min, sum(ell))
    optimize!(model)
    row=Dict{String,Any}("form"=>form, "termination"=>string(termination_status(model)))
    if has_values(model)
        row["grid_MW"]=value(grid)
        row["loss_MW"]=sum(base*e["edges"][b]["r_pu"]*value(ell[b]) for b in 1:B)
        row["P_pu"]=value.(P)
        row["Q_pu"]=value.(Q)
        row["v_pu2"]=value.(v)
        row["ell_pu2"]=value.(ell)
        row["original_equality_residual"]=maximum(
            abs(value(v[x["from"]])*value(ell[b])-value(P[b])^2-value(Q[b])^2) for
            (b, x) in enumerate(e["edges"])
        )
        row["primal_max_violation"]=maximum(values(primal_feasibility_report(model)); init = 0.0)
    end
    push!(out["runs"], row)
    println(row)
end
target="results/runs/r3-v3-electric-"*Dates.format(now(UTC), "yyyymmddTHHMMSS");
mkpath(target)
open(io->TOML.print(io, out; sorted = true), joinpath(target, "counterexample.toml"), "w")
println(target)
