include("r3_setup.jl")
using CSV
length(ARGS)==1 || error("usage: report_r3_baseline.jl STUDY_TOML")
studyfile=only(ARGS)
study=TOML.parsefile(studyfile)
root=dirname(studyfile)
dest=joinpath("results", "summaries", "r3-baseline", study["batch"]*"-"*string(uuid4())[1:8])
mkpath(dest)
cp(studyfile, joinpath(dest, "study.toml"))
cp(joinpath(root, "frozen.toml"), joinpath(dest, "frozen.toml"))
function tablewrite(path, rows; compress = false)
    isempty(rows) && return
    keys0=sort!(unique(vcat([collect(keys(r)) for r in rows]...)))
    columns=Tuple(Symbol.(keys0))
    CSV.write(
        path,
        [NamedTuple{columns}(Tuple(get(r, k, missing) for k in keys0)) for r in rows];
        compress,
    )
end
ratio(rows, scope) = maximum((x.residual/x.tolerance for x in rows if x.scope==scope); init = 0.0)
rows=Dict{String,Any}[]
stops=Dict{String,Any}[]
candidates=Dict{String,Any}[]
stage_rows=Dict{String,Any}[]
curves=Dict{String,Any}[]
trials=Dict{String,Any}[]
trajectories=Dict{String,Any}[]
provenance=Dict{String,Any}[]
for e in study["runs"]
    println("REPORT ", e["id"])
    flush(stdout)
    directory=normpath(joinpath(root, e["directory"]))
    loaded=read_r3_run(directory)
    c, r=loaded.case, loaded.result
    c.sha256==e["input_sha256"] || error("批次输入哈希不同")
    metric=PaperRebuild.r3_baseline_row(loaded)
    row=merge(
        Dict(string(k)=>v for (k, v) in pairs(metric)),
        Dict(k=>e[k] for k in ("id", "group", "case_group", "initial_label", "boundary", "method")),
    )
    row["accepted_updates"]=count(x["accepted"] for x in get(r, "iterations", Any[]))
    row["selected_stage"]=r["final_stage"]>0 ? r["final_stage"] : get(r, "best_subproblem_stage", 0)
    if r["final_stage"]==0 && row["selected_stage"]>0
        reconstructed=findfirst(
            s->s["stage"]=="baseline_pressure_check" &&
               get(s, "source_stage", 0)==row["selected_stage"],
            r["stages"],
        )
        isnothing(reconstructed) || (row["selected_stage"]=reconstructed)
    end
    evidence=r["algorithm"]=="r3_paper_structure_v1" ? r3_stopping_evidence(c, r) : Any[]
    for ep in (1e-6, 1e-4, 1e-2)
        hit=findfirst(x->get(x, "paper_form_epsilon_"*string(ep), false), evidence)
        row["epsilon_"*string(ep)*"_first_update"]=isnothing(hit) ? -1 : evidence[hit]["iteration"]
    end
    push!(rows, row)
    append!(stops, [merge(Dict("id"=>e["id"]), x) for x in evidence])
    for x in evidence
        s=r["stages"][x["stage"]]
        function costpart(a, b)
            x["mode"]=="dispatch" || return NaN
            v=s["values"]
            return c.data["dt_h"]*(
                sum(c.data["grid_price"][a:b] .* v["P_grid"][a:b]) + sum(
                    g["cost_per_MWh"]*sum(v["P_device"][j][a:b]) for
                    (j, g) in enumerate(c.data["devices"])
                )
            )
        end
        push!(
            curves,
            Dict(
                "id"=>e["id"],
                "update"=>x["iteration"],
                "stage"=>x["stage"],
                "mode"=>x["mode"],
                "cost"=>get(x, "cost", NaN),
                "core_cost"=>costpart(1, metric.core_periods),
                "tail_cost"=>costpart(metric.core_periods+1, c.data["T"]),
                "diagnostic"=>x["mode"]=="diagnostic" ? get(s, "solver_objective", NaN) : NaN,
            ),
        )
    end
    for it in get(r, "iterations", Any[]), tr in it["trials"]
        push!(
            trials,
            Dict(
                "id"=>e["id"],
                "iteration"=>it["iteration"],
                "backtrack"=>tr["backtrack"],
                "accepted"=>tr["accepted"],
                "reason"=>get(tr, "reason", ""),
                "gamma"=>tr["gamma"],
                "merit"=>get(tr, "merit", NaN),
                "direction_norm"=>get(tr, "direction_norm", NaN),
                "projected_gradient_norm"=>get(it, "projected_gradient_norm", NaN),
            ),
        )
    end
    selected=Set{Int}()
    for entry in get(r, "candidate_bank", Any[])
        push!(selected, entry["stage"])
        s=r["stages"][entry["stage"]]
        check=only(x for x in r["strict_checks"] if x["source_stage"]==entry["stage"])
        strict=r["stages"][check["stage"]]
        push!(selected, check["stage"])
        push!(
            candidates,
            Dict(
                "id"=>e["id"],
                "stage"=>entry["stage"],
                "roles"=>join(entry["roles"], ";"),
                "flow_sha256"=>entry["flow_sha256"],
                "model_cost"=>s["operating_cost"],
                "raw_physical_pass"=>s["physics_pass"],
                "strict_stage"=>check["stage"],
                "strict_status"=>strict["status"],
                "strict_physical_pass"=>strict["physics_pass"],
                "strict_cost"=>get(strict, "operating_cost", NaN),
            ),
        )
    end
    r["final_stage"]>0 && push!(selected, r["final_stage"])
    row["selected_stage"]>0 && push!(selected, row["selected_stage"])
    residuals=Dict{String,Any}[]
    for (i, s) in enumerate(r["stages"])
        report=loaded.validation.stages[i]
        for rr in report.rows
            push!(
                residuals,
                merge(
                    Dict("id"=>e["id"], "stage"=>i, "name"=>s["stage"]),
                    Dict(string(k)=>v for (k, v) in pairs(rr)),
                ),
            )
        end
        terminal=filter(x->startswith(x.equation, "R3-terminal"), report.rows)
        push!(
            stage_rows,
            Dict(
                "id"=>e["id"],
                "stage"=>i,
                "name"=>s["stage"],
                "status"=>s["status"],
                "model_pass"=>report.model_pass,
                "physical_pass"=>report.physical_pass,
                "objective_kind"=>get(s, "objective_kind", "none"),
                "cost"=>get(s, "operating_cost", NaN),
                "model_ratio"=>isempty(report.rows) ? NaN : ratio(report.rows, "model"),
                "physics_ratio"=>isempty(report.rows) ? NaN : ratio(report.rows, "physics"),
                "terminal_checked"=>!isempty(terminal),
                "terminal_pass"=>!isempty(terminal)&&all(x.pass for x in terminal),
                "terminal_ratio"=>isempty(terminal) ? NaN :
                                  maximum(x.residual/x.tolerance for x in terminal),
            ),
        )
        i in selected && haskey(s, "values") || continue
        v=s["values"]
        for t in 1:c.data["T"], (j, n) in enumerate(c.data["heat"]["nodes"])
            n["role"]=="load" || continue
            delivered=c.data["heat"]["cp_J_kgK"]/1e6*v["m_port"][j][t]*(
                v["tau_S_port"][j][t]-v["tau_R_port"][j][t]
            )
            push!(
                trajectories,
                Dict(
                    "id"=>e["id"],
                    "stage"=>i,
                    "node"=>j,
                    "time_h"=>t*c.data["dt_h"],
                    "t"=>t,
                    "tail"=>t>metric.core_periods,
                    "physical_pass"=>report.physical_pass,
                    "supply_K"=>v["tau_S_port"][j][t],
                    "return_K"=>v["tau_R_port"][j][t],
                    "flow_kg_s"=>v["m_port"][j][t],
                    "demand_MW"=>n["H_MW"][t],
                    "delivered_MW"=>delivered,
                    "delivery_error_W"=>1e6*(delivered-n["H_MW"][t]),
                ),
            )
        end
    end
    # 每个公式、实体及时段的完整残差，压缩只改变存储，不采样。
    tablewrite(joinpath(dest, e["id"]*"-F04.csv.gz"), residuals; compress = true)
    push!(
        provenance,
        Dict(
            "id"=>e["id"],
            "run_sha256"=>loaded.metadata["artifacts"]["run.toml"],
            "input_sha256"=>c.sha256,
            "source_hashes"=>loaded.metadata["source_hashes"],
        ),
    )
    tablewrite(joinpath(dest, "comparison.csv"), rows)
    GC.gc()
end
for (name, data) in (
    ("stopping", stops),
    ("candidates", candidates),
    ("F04-stages", stage_rows),
    ("F05-source", trajectories),
    ("F06-source", curves),
    ("F06-trials", trials),
)
    tablewrite(joinpath(dest, name*".csv"), data)
end
open(joinpath(dest, "provenance.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "origin"=>"synthetic",
            "study_sha256"=>bytes2hex(sha256(read(studyfile))),
            "config_sha256"=>study["config_sha256"],
            "runs"=>provenance,
        );
        sorted = true,
    )
end
println("OUTPUT ", dest)
