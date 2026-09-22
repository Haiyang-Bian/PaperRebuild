# 仅从冻结原值重算全部迭代，保存配对结果；不优化或获取商业许可。
module R9DistributedEvidence
using TOML, SHA, CSV
include("r9_distributed_study.jl")
include("r9_fixed_evidence.jl")
const S=R9DistributedStudy
const O=R9FixedEvidence
const ROOT=dirname(@__DIR__)
const TraceRow=NamedTuple{
    (
        :method,
        :iteration,
        :cost_CNY,
        :model_pass,
        :original_pass,
        :primal,
        :dual,
        :model_ratio,
        :original_ratio,
        :elapsed_sec,
    ),
    Tuple{String,Int,Float64,Bool,Bool,Float64,Float64,Float64,Float64,Float64},
}
const ResidualRow=NamedTuple{
    (:method, :equation, :scope, :entity, :t, :residual, :unit, :tolerance, :pass),
    Tuple{String,String,String,String,Int,Float64,String,Float64,Bool},
}

ratio(v, scope) =
    maximum((x["residual"]/x["tolerance"] for x in v["rows"] if x["scope"]==scope); init = 0.0)

function replay(study)
    meta=S.check(study)
    lib=S.library(joinpath(study, "code"))
    source=S.call(lib, :r9_trading_science_hashes)
    summaries=NamedTuple[]
    iterations=TraceRow[]
    residuals=ResidualRow[]
    separate=get(meta["protocol"], "objective_record", "reported")=="separate"
    objective_reports=NamedTuple[]
    for entry in meta["methods"]
        id=entry["id"]
        folder=S.safe(study, "runs/"*id)
        receipt=TOML.parsefile(joinpath(folder, "receipt.toml"))
        receipt["entry"]==entry &&
        receipt["manifest_sha256"]==S.hashfile(joinpath(study, "manifest.toml")) ||
            error("Method identity")
        !receipt["central_solution_injected"] || error("Reference injection changed")
        mode_contract_pass=true
        if entry["domain"]=="fixed_modes"
            modes=TOML.parsefile(joinpath(study, "fixed-modes.toml"))
            direction=S.call(lib, :r4_matrix, modes["heat_direction"])
            valves=S.call(lib, :r4_matrix, modes["u_H"])
            mode_contract_pass=all(direction .<= valves)
        end
        if !haskey(receipt, "record")
            receipt["status"]=="startup_or_archive_error" && haskey(receipt, "error_type") ||
                error("A completed method lost its record")
            push!(
                summaries,
                (;
                    method = id,
                    case = entry["case"],
                    domain = entry["domain"],
                    algorithm = entry["method"],
                    solver = entry["solver"],
                    status = receipt["status"],
                    record_pass = false,
                    mode_contract_pass,
                    iterations = missing,
                    consensus_A4_pass = false,
                    model_candidate = false,
                    original_candidate = false,
                    best_model_cost_CNY = NaN,
                    best_original_cost_CNY = NaN,
                    last_cost_CNY = NaN,
                    selected_index = 0,
                    model_ratio = NaN,
                    original_ratio = NaN,
                    solver_bound_CNY = NaN,
                    solver_gap = NaN,
                    cost_optimization_complete = false,
                    method_elapsed_sec = get(receipt, "method_elapsed_sec", NaN),
                    process_elapsed_sec = receipt["process_elapsed_sec"],
                    process_budget_pass = receipt["process_budget_pass"],
                ),
            )
            separate && push!(
                objective_reports,
                (;
                    method = id,
                    checked_blocks = missing,
                    mismatch_blocks = missing,
                    reported_scalar_pass = missing,
                    max_relative_error = NaN,
                    subproblem_accuracy_certified = false,
                    scope = "record_unavailable",
                ),
            )
            continue
        end
        receipt["raw_result_sha256"]==S.hashfile(joinpath(folder, "raw-result.toml")) ||
            error("Raw bytes changed")
        receipt["record_manifest_sha256"]==S.hashfile(joinpath(folder, "record/hashes.toml")) ||
            error("Archive identity")
        raw=TOML.parsefile(joinpath(folder, "raw-result.toml"))
        raw["source_hashes_at_solve"]==source || error("Science snapshot changed")
        raw["input_sha256"]==meta["files"]["inputs/"*entry["case"]*".toml"] ||
            error("Input differs")
        reader=entry["method"]=="central" ? :r9_trading_read_current : :r9_distributed_read_current
        loaded=S.call(lib, reader, joinpath(folder, "record"))
        r, c, v=loaded.result, loaded.case, loaded.validation
        if separate
            n=entry["method"]=="admm" ? v["solver_objective_reports_checked"] : 0
            push!(
                objective_reports,
                (;
                    method = id,
                    checked_blocks = n,
                    mismatch_blocks = entry["method"]=="admm" ?
                                      v["solver_objective_report_mismatch_count"] : missing,
                    reported_scalar_pass = n>0 ? v["solver_objective_reports_pass"] : missing,
                    max_relative_error = n>0 ? v["max_solver_objective_report_relative_error"] :
                                         NaN,
                    subproblem_accuracy_certified = false,
                    scope = entry["method"]=="admm" ? "native_report_vs_saved_primal_at_1e-9" :
                            "not_applicable",
                ),
            )
        end
        r["status"]==raw["status"]==receipt["status"] || error("Status changed")
        isequal(v, receipt["validation"]) || error("Receipt validation changed")
        transformed=deepcopy(raw)
        transformed["run_id"]="record"
        if entry["method"]=="central"
            for (i, s) in enumerate(transformed["stages"])
                s["validation"]=S.call(lib, :r9_trading_summary, s["validation"])
                s["residual_file"]="residuals/stage-"*lpad(string(i), 2, '0')*".csv"
            end
        end
        isequal(transformed, r) || error("Archive differs from original result")
        for key in ("method", "process")
            receipt[key*"_budget_pass"]==(
                receipt[key*"_elapsed_sec"]<=meta["protocol"]["budget_sec"]
            ) || error("Wall budget changed")
        end
        selected=nothing
        bestcost, physicalcost, lastcost, bound, gap=NaN, NaN, NaN, NaN, NaN
        selected_index=0
        a4=false
        model=false
        physical=false
        n=0
        modelratio, originalratio=NaN, NaN
        if entry["method"]=="central"
            index=r["primary_stage_index"]
            if index>0 && haskey(r["stages"][index], "values")
                s=r["stages"][index]
                selected=S.call(lib, :validate_r9_trading_solution, c, s)
                model=selected["model_pass"]
                physical=model&&selected["electric_original_pass"]
                lastcost=r["system_cost_CNY"]
                bestcost=model ? lastcost : NaN
                physicalcost=physical ? lastcost : NaN
                bound=get(s, "objective_bound", NaN)
                gap=get(s, "relative_gap", NaN)
                selected_index=index
            end
        else
            n=length(r["trace"])
            a4=v["consensus_A4_pass"]
            model=v["best_model_found"]
            physical=v["best_physical_found"]
            bestcost=v["best_model_cost_CNY"]
            physicalcost=v["best_physical_cost_CNY"]
            lastcost=v["last_cost_CNY"]
            selected_index=r["best_physical_iteration"]>0 ? r["best_physical_iteration"] :
                           r["best_model_iteration"]>0 ? r["best_model_iteration"] : n
            for row in r["trace"]
                candidate=S.call(lib, :r9_distributed_candidate, c, row["agents"], row["operator"])
                cv=candidate["validation"]
                push!(
                    iterations,
                    (
                        id,
                        row["iteration"],
                        candidate["operating_cost_CNY"],
                        cv["model_pass"],
                        cv["model_pass"]&&cv["electric_original_pass"],
                        row["primal"],
                        row["dual"],
                        ratio(cv, "model"),
                        ratio(cv, "electric_original"),
                        row["elapsed_sec"],
                    ),
                )
                row["iteration"]==selected_index && (selected=cv)
            end
        end
        if selected!==nothing
            modelratio=ratio(selected, "model")
            originalratio=ratio(selected, "electric_original")
            for x in selected["rows"]
                push!(
                    residuals,
                    (
                        id,
                        x["equation"],
                        x["scope"],
                        x["entity"],
                        x["t"],
                        x["residual"],
                        x["unit"],
                        x["tolerance"],
                        x["pass"],
                    ),
                )
            end
        end
        push!(
            summaries,
            (;
                method = id,
                case = entry["case"],
                domain = entry["domain"],
                algorithm = entry["method"],
                solver = entry["solver"],
                status = r["status"],
                record_pass = true,
                mode_contract_pass,
                iterations = n,
                consensus_A4_pass = a4,
                model_candidate = model,
                original_candidate = physical,
                best_model_cost_CNY = bestcost,
                best_original_cost_CNY = physicalcost,
                last_cost_CNY = lastcost,
                selected_index,
                model_ratio = modelratio,
                original_ratio = originalratio,
                solver_bound_CNY = bound,
                solver_gap = gap,
                cost_optimization_complete = r["cost_optimization_complete"],
                method_elapsed_sec = receipt["method_elapsed_sec"],
                process_elapsed_sec = receipt["process_elapsed_sec"],
                process_budget_pass = receipt["process_budget_pass"],
            ),
        )
    end
    comparisons=NamedTuple[]
    for row in filter(x->x.algorithm=="admm", summaries)
        peer=only(
            x for
            x in summaries if x.algorithm=="central" && x.case==row.case && x.domain==row.domain
        )
        usable=row.model_candidate&&peer.model_candidate
        push!(
            comparisons,
            (;
                case = row.case,
                domain = row.domain,
                central = peer.method,
                distributed = row.method,
                same_model = true,
                candidate_comparison_available = usable,
                distributed_minus_central_CNY = usable ?
                                                row.best_model_cost_CNY-peer.best_model_cost_CNY :
                                                NaN,
                reference_relative_gap = usable&&isfinite(peer.solver_bound_CNY) ?
                                         max(0.0, row.best_model_cost_CNY-peer.solver_bound_CNY)/max(
                    1.0,
                    abs(row.best_model_cost_CNY),
                ) : NaN,
                reference_bound_excess = usable&&isfinite(peer.solver_bound_CNY) ?
                                         max(0.0, peer.solver_bound_CNY-row.best_model_cost_CNY)/max(
                    1.0,
                    abs(row.best_model_cost_CNY),
                ) : NaN,
                candidate_difference_is_not_optimality_gap = true,
            ),
        )
    end
    result=(; summary = summaries, iterations, residuals, comparisons)
    separate ? (; result..., objective_reports) : result
end

function archive(study, out)
    ispath(out) && error("Do not overwrite evidence")
    data=replay(study)
    mkpath(joinpath(out, "objects"))
    files=Dict{String,String}()
    for (dir, dirs, names) in walkdir(study)
        any(x->islink(joinpath(dir, x)), [dirs; names]) && error("Symlinks forbidden")
        for name in names
            path=joinpath(dir, name)
            rel=replace(relpath(path, study), '\\'=>'/')
            startswith(rel, "logs/") && continue
            files[rel]=O.object(out, read(path))
        end
    end
    derived=Dict{String,String}()
    for (name, rows) in pairs(data), (rel, content) in O.table_parts(name, rows)
        write(joinpath(out, rel), content)
        derived[rel]=S.hashfile(joinpath(out, rel))
    end
    for rel in (
        "scripts/r9_distributed_evidence.jl",
        "scripts/r9_distributed_study.jl",
        "scripts/r9_trading_study.jl",
        "scripts/r9_fixed_evidence.jl",
    )
        target=joinpath(out, "code", rel)
        mkpath(dirname(target))
        cp(joinpath(ROOT, rel), target)
        derived["code/"*rel]=S.hashfile(target)
    end
    S.toml(
        joinpath(out, "evidence.toml"),
        Dict(
            "schema"=>"r9-distributed-evidence-v1",
            "study"=>basename(study),
            "origin"=>"synthetic",
            "study_manifest_sha256"=>S.hashfile(joinpath(study, "manifest.toml")),
            "study_files"=>files,
            "derived_files"=>derived,
            "solver_used_for_replay"=>false,
            "complete_thermal_certification"=>false,
            "bargaining"=>false,
        ),
    )
    println(
        "Archived ",
        length(data.summary),
        " methods and ",
        length(data.iterations),
        " independently replayable iterations; missing records remain unknown; no optimization.",
    )
end

function check(out)
    m=TOML.parsefile(joinpath(out, "evidence.toml"))
    m["schema"]=="r9-distributed-evidence-v1" &&
    m["origin"]=="synthetic" &&
    !m["solver_used_for_replay"] &&
    !m["complete_thermal_certification"] &&
    !m["bargaining"] || error("Evidence scope")
    for (rel, h) in m["derived_files"]
        S.hashfile(S.safe(out, rel))==h || error("Derived bytes changed")
    end
    mktempdir() do folder
        for (rel, h) in m["study_files"]
            path=S.safe(folder, rel)
            mkpath(dirname(path))
            write(path, O.bytes(out, h))
        end
        S.hashfile(joinpath(folder, "manifest.toml"))==m["study_manifest_sha256"] ||
            error("Study identity changed")
        data=replay(folder)
        for (name, rows) in pairs(data), (rel, bytes) in O.table_parts(name, rows)
            bytes==read(S.safe(out, rel)) || error("Table semantics changed: "*rel)
        end
        println(
            "Independent frozen replay: ",
            length(data.summary),
            " methods; ",
            length(data.iterations),
            " iterations.",
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
        error("usage: r9_distributed_evidence.jl archive STUDY NEW_EVIDENCE | check EVIDENCE")
    end
end
end
