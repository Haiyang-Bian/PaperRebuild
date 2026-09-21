# 已冻结十六方法的原值重验和可移植分片封存。不重优化，不申请商业许可。
module R9NetworkEvidence
using TOML, SHA, CSV
include("r9_network_study.jl")
include("r9_fixed_evidence.jl")
const S=R9NetworkStudy
const O=R9FixedEvidence
const ROOT=dirname(@__DIR__)

function replay(study)
    meta=S.check(study)
    lib=S.library(joinpath(study, "code"))
    source=S.call(lib, :r9_trading_science_hashes)
    summaries, stages, topologies, trajectories, residuals=NamedTuple[],
    NamedTuple[],
    NamedTuple[],
    NamedTuple[],
    NamedTuple[]
    for entry in meta["methods"]
        id=entry["id"]
        folder=S.safe(study, "runs/"*id)
        receipt=TOML.parsefile(joinpath(folder, "receipt.toml"))
        receipt["entry"]==entry &&
        receipt["manifest_sha256"]==S.hashfile(joinpath(study, "manifest.toml")) ||
            error("Method provenance changed")
        receipt["solver_options"]==meta["protocol"]["gurobi"] &&
        !receipt["initial_primal_injection"] &&
        !receipt["uses_projected_gradient"] &&
        !receipt["distributed_algorithm"] &&
        !receipt["bargaining"] &&
        receipt["origin"]=="synthetic" || error("Method rules")
        receipt["raw_result_sha256"]==S.hashfile(joinpath(folder, "raw-result.toml")) ||
            error("Raw hash")
        receipt["record_manifest_sha256"]==S.hashfile(joinpath(folder, "record/hashes.toml")) ||
            error("Archive identity")
        raw=TOML.parsefile(joinpath(folder, "raw-result.toml"))
        raw["source_hashes_at_solve"]==source || error("Frozen science changed")
        raw["input_sha256"]==entry["input_sha256"] || error("Run input changed")
        checked=S.call(lib, :r9_trading_read_current, joinpath(folder, "record"))
        r, c=checked.result, checked.case
        r["status"]==raw["status"]==receipt["status"] || error("Status changed")
        transformed=deepcopy(raw)
        transformed["run_id"]="record"
        for (i, stage) in enumerate(transformed["stages"])
            stage["validation"]=S.call(lib, :r9_trading_summary, stage["validation"])
            stage["residual_file"]="residuals/stage-"*lpad(string(i), 2, '0')*".csv"
        end
        isequal(transformed, r) || error("Saved controls differ from original result")
        v=checked.validation
        for key in ("method", "process")
            receipt[key*"_budget_pass"]==(receipt[key*"_elapsed_sec"]<=receipt["budget_sec"]) ||
                error("Receipt wall budget changed")
        end
        primary=r["primary_stage_index"]
        cand=primary>0 && haskey(r["stages"][primary], "values")
        costs=nothing
        switches=NaN
        maxmodel, maxoriginal=NaN, NaN
        bound, objective, gap=NaN, NaN, NaN
        if primary>0
            s=r["stages"][primary]
            bound=get(s, "objective_bound", NaN)
            objective=get(s, "solver_objective", NaN)
            gap=get(s, "relative_gap", NaN)
            if cand
                values=s["values"]
                costs=S.call(lib, :r9_trading_costs, c, values)
                net=S.call(lib, :validate_r9_network, c, values)
                switches=net["switching_CNY"]
                cv=S.call(lib, :validate_r9_trading_solution, c, s)
                maxmodel=maximum(
                    x["residual"]/x["tolerance"] for x in cv["rows"] if x["scope"]=="model";
                    init = 0.0,
                )
                maxoriginal=maximum(
                    x["residual"]/x["tolerance"] for
                    x in cv["rows"] if x["scope"]=="electric_original";
                    init = 0.0,
                )
                for x in cv["rows"]
                    push!(
                        residuals,
                        (
                            method = id,
                            equation = x["equation"],
                            scope = x["scope"],
                            entity = x["entity"],
                            t = x["t"],
                            residual = x["residual"],
                            unit = x["unit"],
                            tolerance = x["tolerance"],
                            pass = x["pass"],
                        ),
                    )
                end
                for (side, key, ukey, akey, nt) in (
                    ("electric", "edges", "u_E", "a_E", c.data["T"]),
                    ("heat", "pipes", "u_H", "a_H", 1),
                )
                    for (j, edge) in enumerate(c.data[side][key]), t in 1:nt
                        push!(
                            topologies,
                            (
                                method = id,
                                side = side,
                                edge = j,
                                from = edge["from"],
                                to = edge["to"],
                                t = t,
                                on = values[ukey][j][t],
                                action = values[akey][j][t],
                                initial = c.data["network_control"][side*"_initial"][j],
                            ),
                        )
                    end
                end
                for t in 1:c.data["T"]
                    generation=sum(x[t] for x in values["H_gen"])
                    demand=sum(x[t] for x in values["H_D"]) +
                           sum(x[t] for x in c.data["heat"]["H_background_MW"]) +
                           sum(x[t] for x in values["H_cons"])
                    heatloss=sum(
                        pipe["loss_MW"]*values["u_H"][j][1] for
                        (j, pipe) in enumerate(c.data["heat"]["pipes"])
                    )
                    gridloss=c.data["electric"]["base_MVA"]*sum(
                        edge["r_pu"]*values["ell"][j][t] for
                        (j, edge) in enumerate(c.data["electric"]["edges"])
                    )
                    push!(
                        trajectories,
                        (
                            method = id,
                            t = t,
                            dt_h = c.data["dt_h"],
                            P_grid_MW = values["P_grid"][t],
                            grid_loss_MW = gridloss,
                            H_generation_MW = generation,
                            H_demand_and_charge_MW = demand,
                            heat_loss_MW = heatloss,
                            heat_balance_MW = generation-demand-heatloss,
                        ),
                    )
                end
            end
        end
        push!(
            summaries,
            (
                method = id,
                design = entry["design"],
                policy = entry["policy"],
                operation = entry["operation"],
                electric = entry["electric"],
                input_sha256 = entry["input_sha256"],
                status = r["status"],
                has_candidate = cand,
                local_plans_pass = v["local_plans_pass"],
                model_pass = v["model_pass"],
                electric_original_pass = v["electric_original_pass"],
                heat_pass = v["heat_energy_mass_pass"],
                ledger_pass = v["ledger_pass"],
                adopted_physical_pass = v["adopted_physical_pass"],
                cost_optimization_complete = r["cost_optimization_complete"],
                solver_objective_CNY = objective,
                system_cost_CNY = get(r, "system_cost_CNY", NaN),
                bound_CNY = bound,
                relative_gap = gap,
                device_cost_CNY = costs===nothing ? NaN : sum(costs.resource)-switches,
                discomfort_CNY = costs===nothing ? NaN : sum(costs.discomfort),
                external_CNY = costs===nothing ? NaN : costs.external,
                switching_CNY = switches,
                max_model_normalized_residual = maxmodel,
                max_original_normalized_residual = maxoriginal,
                method_elapsed_sec = receipt["method_elapsed_sec"],
                process_elapsed_sec = receipt["process_elapsed_sec"],
                method_budget_pass = receipt["method_budget_pass"],
                process_budget_pass = receipt["process_budget_pass"],
            ),
        )
        for (i, s) in enumerate(r["stages"])
            push!(
                stages,
                (
                    method = id,
                    stage_index = i,
                    stage = s["stage"],
                    actor = s["actor"],
                    termination = s["termination"],
                    model_pass = s["validation"]["model_pass"],
                    objective_kind = s["objective_kind"],
                    objective = get(s, "solver_objective", NaN),
                ),
            )
        end
    end
    comparisons=NamedTuple[]
    for a in summaries, b in summaries
        a.design==b.design &&
        a.operation==b.operation &&
        a.electric==b.electric &&
        a.policy=="fixed" &&
        b.policy=="joint" || continue
        valid=a.adopted_physical_pass &&
              b.adopted_physical_pass &&
              a.process_budget_pass &&
              b.process_budget_pass
        push!(
            comparisons,
            (
                design = a.design,
                operation = a.operation,
                electric = a.electric,
                fixed_method = a.method,
                joint_method = b.method,
                physical_comparison_available = valid,
                fixed_minus_joint_CNY = valid ? a.system_cost_CNY-b.system_cost_CNY : NaN,
                candidate_difference_not_optimality_gap = true,
            ),
        )
    end
    (; summary = summaries, stages, topologies, trajectories, residuals, comparisons)
end

function restore(out, files, target)
    for (rel, hash) in files
        path=S.safe(target, rel)
        mkpath(dirname(path))
        write(path, O.bytes(out, hash))
    end
end

function archive(study, out)
    ispath(out) && error("Do not overwrite public evidence")
    data=replay(study)
    mkpath(joinpath(out, "objects"))
    files=Dict{String,String}()
    for (dir, dirs, names) in walkdir(study)
        any(x->islink(joinpath(dir, x)), [dirs; names]) && error("Do not pack symlinks")
        for name in names
            path=joinpath(dir, name)
            rel=replace(relpath(path, study), '\\'=>'/')
            startswith(rel, "logs/") && continue # 商用日志含机器/许可信息，仅保留本地。
            files[rel]=O.object(out, read(path))
        end
    end
    meta=Dict(
        "schema"=>"r9-network-evidence-v1",
        "study"=>basename(study),
        "origin"=>"synthetic",
        "study_manifest_sha256"=>S.hashfile(joinpath(study, "manifest.toml")),
        "study_files"=>files,
        "complete_thermal_certification"=>false,
        "bargaining"=>false,
        "solver_used_for_replay"=>false,
    )
    derived=Dict{String,String}()
    for (name, rows) in pairs(data)
        for (rel, content) in O.table_parts(name, rows)
            write(joinpath(out, rel), content)
            derived[rel]=S.hashfile(joinpath(out, rel))
        end
    end
    for rel in (
        "scripts/r9_network_evidence.jl",
        "scripts/r9_network_study.jl",
        "scripts/r9_trading_study.jl",
        "scripts/r9_fixed_evidence.jl",
    )
        path=joinpath(out, "code", rel)
        mkpath(dirname(path))
        cp(joinpath(ROOT, rel), path)
        derived["code/"*rel]=S.hashfile(path)
    end
    meta["derived_files"]=derived
    S.toml(joinpath(out, "evidence.toml"), meta)
    println(
        "Archived ",
        length(data.summary),
        " methods; ",
        count(x->x.adopted_physical_pass, data.summary),
        " adopted-physics candidates. No rerun.",
    )
end

function check(out)
    meta=TOML.parsefile(joinpath(out, "evidence.toml"))
    meta["schema"]=="r9-network-evidence-v1" &&
    meta["origin"]=="synthetic" &&
    !meta["complete_thermal_certification"] &&
    !meta["bargaining"] &&
    !meta["solver_used_for_replay"] || error("Evidence scope")
    for (rel, h) in meta["derived_files"]
        S.hashfile(S.safe(out, rel))==h || error("Derived bytes changed")
    end
    mktempdir() do dir
        restore(out, meta["study_files"], dir)
        S.hashfile(joinpath(dir, "manifest.toml"))==meta["study_manifest_sha256"] ||
            error("Study identity")
        data=replay(dir)
        for (name, rows) in pairs(data), (rel, content) in O.table_parts(name, rows)
            content==read(S.safe(out, rel)) || error("Table semantics changed: "*rel)
        end
        println(
            "Frozen original-value replay passed: ",
            length(data.summary),
            " methods, ",
            length(data.stages),
            " stages, ",
            length(data.residuals),
            " residuals.",
        )
    end
    true
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    if length(ARGS)==3 && ARGS[1]=="archive"
        archive(abspath(ARGS[2]), abspath(ARGS[3]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        check(abspath(ARGS[2]))
    else
        error("usage: r9_network_evidence.jl archive STUDY NEW_SUMMARY | check SUMMARY")
    end
end
end
