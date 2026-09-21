# 第7.5节预优化输入审计：先验数值沿既有缺失数据协议，不调用优化器。
using PaperRebuild, TOML, Test, SHA
const PR = PaperRebuild
const ROOT = dirname(@__DIR__)
length(ARGS)==1 || error("usage: audit_r9_resilience_input.jl NEW_REPORT_TOML")
out=abspath(only(ARGS))
ispath(out) && error("不覆盖已有输入审计")
bundle = load_r9_sources(joinpath(ROOT, "docs/reading/ch07"))
source = bundle.data["inputs.toml"]
top = bundle.data["topology.toml"]
review = TOML.parsefile(joinpath(ROOT, "docs/reading/ch07/resilience-review.toml"))
p = TOML.parsefile(joinpath(ROOT, "configs/r9/reserve-protocol.toml"))
h = p["heat"]
sets = only(x for x in review["finding"] if x["id"] == "R9-RS02")
keys = ["nodes_figure_7_12", "nodes_figure_7_14"]
critical = [
    [
        i in sets[key] ? source["resilience"]["critical_active_capacity_MW"]/length(sets[key]) :
        0.0 for i in 1:44
    ] for key in keys
]
base = max.(critical...)
total = source["base"]["electric_peak_MVA"] * p["electric"]["power_factor"]
remainder = total - sum(base)
remainder > 0 || error("两套重要节点容量无法嵌入共同总负荷")
load = base + [i == 44 ? 0.0 : remainder/43 for i in 1:44]

edges = top["heat"]["edges"]
order, _ = PR.r9_tree_order(38, edges, 1)
cp, rho = h["cp_J_kgK"], h["rho_kg_m3"]
ambient, inlet = h["ambient_reference_K"], h["source_reference_K"]
href = source["base"]["heat_peak_MW"] * h["reference_fraction"] / 36
heat = [i in (1, 15) ? 0.0 : href for i in 1:38]
port = heat / (cp/1e6 * h["reference_delta_K"])
srcflow = zeros(38)
srcflow[15] = h["source15_reference_MW"]/(cp/1e6*h["reference_delta_K"])
sub = port - srcflow
for j in reverse(order[2:end])
    i = only(i for (i, k) in edges if k==j)
    sub[i] += sub[j]
end
srcflow[1] = sub[1]
flows = [sub[j] for (i, j) in edges]
all(>(0), flows) || error("声明的正常参考不是严格正流")
volume = flows ./ rho ./ h["velocity_m_s"] .* h["length_m"]
diameter = sqrt.(4 .* flows ./ rho ./ h["velocity_m_s"] ./ pi)
UA = 2pi*h["insulation_W_mK"] .* h["length_m"] ./ log1p.(2h["insulation_thickness_m"] ./ diameter)
decay = exp.(-UA ./ (cp .* flows))
S, R = zeros(38), zeros(38)
sout, rout = zeros(37), zeros(37)
for i in order
    incoming = findall(x->x[2]==i, edges)
    m = srcflow[i]+sum(flows[a] for a in incoming; init = 0.0)
    S[i] = (srcflow[i]*inlet+sum(flows[a]*sout[a] for a in incoming; init = 0.0))/m
    for (a, (j, k)) in enumerate(edges)
        j==i && (sout[a]=ambient+(S[i]-ambient)*decay[a])
    end
end
loadreturn = [port[i]>0 ? S[i]-heat[i]/(cp/1e6*port[i]) : 0.0 for i in 1:38]
for i in reverse(order)
    outgoing = findall(x->x[1]==i, edges)
    m = port[i]+sum(flows[a] for a in outgoing; init = 0.0)
    R[i] = (port[i]*loadreturn[i]+sum(flows[a]*rout[a] for a in outgoing; init = 0.0))/m
    for (a, (j, k)) in enumerate(edges)
        k==i && (rout[a]=ambient+(R[i]-ambient)*decay[a])
    end
end
sourceheat = cp/1e6 .* srcflow .* (inlet .- R)
loss = sum(cp/1e6*flows[a]*(S[i]-sout[a]+R[j]-rout[a]) for (a, (i, j)) in enumerate(edges))
observations = Dict{String,Any}[]
@testset "R9 declared load allocation and preoptimization steady input" begin
    @test sum(load) ≈ total atol=1e-10
    for k in eachindex(keys)
        @test sum(critical[k]) ≈ 13.75 atol=1e-10
        @test all(load .>= critical[k])
    end
    @test load[44]==0.0
    @test all(h["S_bounds_K"][1] .<= S .<= h["S_bounds_K"][2])
    @test all(h["R_bounds_K"][1] .<= R .<= h["R_bounds_K"][2])
    @test sum(sourceheat) ≈ sum(heat)+loss atol=1e-10
    @test 3.4 <= sourceheat[1]/1.2 <= 6.0
    @test sourceheat[15] <= 1.2
    for (a, (i, j)) in enumerate(edges), side in ("S", "R")
        Tin = side=="S" ? S[i] : R[j]
        Tout = ambient+(Tin-ambient)*decay[a]
        M = rho*volume[a]
        exact =
            PR.R7PipeState([PR.R7PipeSegment(M, ambient, Tin-ambient, UA[a]/(M*cp*flows[a]), true)])
        reference = h[side*"_bounds_K"][1]
        inventory = r7_pipe_inventory(exact; cp_J_kgK = cp, reference_K = reference)
        uniform = r7_pipe_state([M], [inventory.mean_K])
        expstep = r7_pipe_step(
            exact;
            mass_flow_kg_s = flows[a],
            inlet_K = Tin,
            ambient_K = ambient,
            dt_h = 0.25,
            cp_J_kgK = cp,
            UA_W_K = UA[a],
            reference_K = reference,
        )
        conststep = r7_pipe_step(
            uniform;
            mass_flow_kg_s = flows[a],
            inlet_K = Tin,
            ambient_K = ambient,
            dt_h = 0.25,
            cp_J_kgK = cp,
            UA_W_K = UA[a],
            reference_K = reference,
        )
        @test expstep.outlet_mean_K ≈ Tout atol=1e-10
        @test r7_pipe_inventory(expstep.state; cp_J_kgK = cp, reference_K = reference).relative_heat_MWh ≈
              inventory.relative_heat_MWh atol=1e-10
        push!(
            observations,
            Dict(
                "pipe"=>a,
                "side"=>side,
                "mass_kg"=>M,
                "UA_W_K"=>UA[a],
                "inlet_K"=>Tin,
                "outlet_K"=>Tout,
                "mean_K"=>inventory.mean_K,
                "uniform_first_outlet_error_K"=>conststep.outlet_mean_K-Tout,
            ),
        )
    end
end
report = Dict(
    "origin"=>"preoptimization_project_input_audit_not_frozen_scale_case",
    "optimization_performed"=>false,
    "source_hashes"=>bundle.hashes,
    "scale_input_frozen"=>false,
    "dt_h"=>0.25,
    "units"=>Dict("power"=>"MW", "temperature"=>"K", "mass"=>"kg", "UA"=>"W/K"),
    "engineering_protocol"=>"configs/r9/reserve-protocol.toml",
    "engineering_protocol_sha256"=>bytes2hex(
        sha256(read(joinpath(ROOT, "configs/r9/reserve-protocol.toml"))),
    ),
    "audit_script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "pipe_replay_sha256"=>bytes2hex(sha256(read(joinpath(ROOT, "src/networks/r7_pipe_state.jl")))),
    "critical_allocation_rule"=>"equal_within_each_source_set; common_total_is_pointwise_max_plus_equal_remaining_nonroot_load",
    "total_peak_MW"=>total,
    "total_node_peak_MW"=>load,
    "critical_set_keys"=>keys,
    "critical_node_peak_MW"=>critical,
    "source1_heat_MW"=>sourceheat[1],
    "source15_heat_MW"=>sourceheat[15],
    "reference_CHP2_MW"=>sourceheat[1]/1.2,
    "heat_loss_MW"=>loss,
    "profiles"=>observations,
    "maximum_uniform_outlet_error_K"=>maximum(
        abs(x["uniform_first_outlet_error_K"]) for x in observations
    ),
)
mkpath(dirname(out))
open(out, "w") do io
    TOML.print(io, report; sorted = true)
end
println("reference CHP2 MW: ", report["reference_CHP2_MW"])
println("source15 heat MW: ", report["source15_heat_MW"])
println("uniform-initial first outlet maximum error K: ", report["maximum_uniform_outlet_error_K"])
