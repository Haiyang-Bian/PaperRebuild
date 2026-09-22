using PaperRebuild, JuMP, Gurobi, TOML, SHA, UUIDs
include("r7_normal_flow_study.jl")
length(ARGS)==2 || error("usage: probe_r7_flow_balance.jl FROZEN_INPUTS NEW_PROBE")
input, dest=abspath.(ARGS);
ispath(dest)&&error("不覆盖能量等价强化探针")
items, _=flow_inputs(input; current = true)
item=only(filter(x->x["group"]=="original_hand"&&x["control"]=="continuous", items))
c=R7NormalCase(item["case"]);
s=item["spec"]
started=time();
deadline=started+60
b=build_r7_normal_flow(c, s; optimizer = flow_optimizer("Gurobi"), deadline)
d=c.data;
h=d["heat"];
v=b.variables
# 无损、固定管容量和节点质量/焓守恒的线性推论，不缩小原非线性可行域。
for t in 1:d["periods"], w in eachindex(d["probabilities"])
    @constraint(
        b.model,
        d["dt_h"]*(sum(v["H"][:, t, w])-sum(h["load_MW"][j][t] for j in 1:h["nodes"])) ==
        sum(v["E_pipe_S"][:, t+1, w]-v["E_pipe_S"][:, t, w])+sum(
            v["E_pipe_R"][:, t+1, w]-v["E_pipe_R"][:, t, w],
        )
    )
end
r=Dict{String,Any}(
    "schema"=>"r7-normal-flow-result-v1",
    "version"=>s["version"],
    "run_id"=>"r7-flow-balance-"*string(uuid4()),
    "case_sha256"=>c.sha256,
    "spec_sha256"=>PaperRebuild.r7_digest(s),
    "objective_kind"=>"expected_normal_cost_USD",
    "source_hashes_at_solve"=>PaperRebuild.r7_normal_flow_science_hashes(),
    "julia_version"=>string(VERSION),
    "budget_sec"=>60.0,
    "status"=>"budget_exhausted",
    "full_preplan_optimality_verified"=>false,
    "formulation_variant"=>"explicit_redundant_network_energy_v1",
    "extra_constraint_source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "flow_fixed"=>false,
    "model_class"=>b.model_class,
    "model_types"=>b.model_types,
)
if time()<deadline
    set_silent(b.model)
    set_time_limit_sec(b.model, deadline-time())
    optimize!(b.model)
    ts=termination_status(b.model)
    pr=primal_status(b.model)
    r["termination_status"]=string(ts)
    r["primal_status"]=string(pr)
    r["solver_name"]=solver_name(b.model)
    r["raw_status"]=raw_status(b.model)
    r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                ts==MOI.TIME_LIMIT ? "time_limit_no_solution" : string(ts)
    if has_values(b.model)&&pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
        r["values"]=Dict(k=>PaperRebuild.r7_pack(value.(a)) for (k, a) in b.variables)
        r["chp_values"]=Dict(
            id=>Dict(k=>PaperRebuild.r7_pack(value.(a)) for (k, a) in block.variables) for
            (id, block) in b.chp
        )
        r["flow_values"]=Dict(k=>PaperRebuild.r7_pack(value.(a)) for (k, a) in b.flow)
        r["solver_objective_USD"]=objective_value(b.model)
        r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
    end
    bound=objective_bound(b.model)
    isfinite(bound)&&(r["lower_bound_USD"]=bound)
end
r["validation"]=validate_r7_normal_flow(c, s, r);
r["candidate_accepted"]=r["validation"]["model_pass"]
r["domain_cost_complete"]=r["validation"]["optimality_pass"];
r["elapsed_sec"]=time()-started
mkpath(dest);
save_r7_normal_flow(c, s, r, joinpath(dest, "record"));
cp(@__FILE__, joinpath(dest, "probe-source.jl"))
cp(joinpath(input, "inputs.toml"), joinpath(dest, "parent-inputs.toml"))
write(joinpath(dest, "files.toml"), PaperRebuild.r7_text(Dict("files"=>flow_manifest(dest))))
println(
    r["status"],
    " pass=",
    r["candidate_accepted"],
    " gap=",
    get(r["validation"], "relative_gap", "missing"),
    " elapsed=",
    r["elapsed_sec"],
)
