using PaperRebuild, TOML, CSV, SHA

# 全部旧运行只读补证；新见证足以在没有results/runs的克隆中独立复核。
function audit_r5_dispatch_duality(study_path, dest)
    ispath(dest)&&error("不覆盖对偶审计")
    study=TOML.parsefile(study_path)
    study["complete"]&&length(study["records"])==24||error("父批次范围不完整")
    paths=PaperRebuild.r5_dispatch_science_paths()
    paths["src/verification/r5_dispatch_duality.jl"]=PaperRebuild.R5_DISPATCH_DUALITY_FILE
    paths["src/formulations/r5_dispatch_dual.jl"]=PaperRebuild.R5_DISPATCH_DUAL_MODEL_FILE
    source_hashes=Dict(k=>bytes2hex(sha256(read(p))) for (k, p) in paths)
    summary=NamedTuple[]
    residuals=NamedTuple[]
    sensitivity=NamedTuple[]
    witness_hashes=Dict{String,String}()
    mkpath(joinpath(dest, "witnesses"))
    for entry in study["records"]
        id=entry["id"]
        occursin(r"^[A-Za-z0-9_-]+$", id)||error("父运行标识错误")
        parent=joinpath(dirname(study_path), id)
        x=read_r5_dispatch_run(parent)
        parent_hash=bytes2hex(sha256(read(joinpath(parent, "result.toml"))))
        parent_hash==entry["result_sha256"]&&x.case.sha256==entry["case_sha256"]||error(
            "父运行与清单不同",
        )
        k=validate_r5_dispatch_duals(x.case, x.result)
        total=r5_dispatch_sensitivity(x.case, x.result; objective = :total)
        recourse=r5_dispatch_sensitivity(x.case, x.result)
        push!(
            summary,
            (
                record_id = id,
                run_id = x.result["run_id"],
                case_sha256 = x.case.sha256,
                original_status = x.result["status"],
                audit_status = k["status"],
                model_pass = k["model_pass"],
                kkt_pass = k["kkt_pass"],
                total_relative_gap = get(k, "relative_gap", NaN),
                recourse_relative_gap = get(k, "recourse_relative_gap", NaN),
                max_normalized_residual = isempty(k["rows"]) ? NaN :
                                          maximum(z["normalized"] for z in k["rows"]),
            ),
        )
        for row in k["rows"]
            push!(
                residuals,
                (
                    record_id = id,
                    run_id = x.result["run_id"],
                    id = row["id"],
                    kind = row["kind"],
                    residual = row["residual"],
                    tolerance = row["tolerance"],
                    normalized = row["normalized"],
                    pass = row["pass"],
                ),
            )
        end
        if total["trusted"]
            for key in sort!(collect(keys(total["gradient"]))), t in 1:x.case.data["T"]
                push!(
                    sensitivity,
                    (
                        record_id = id,
                        run_id = x.result["run_id"],
                        parameter = key,
                        t = t,
                        total_USD_per_MW = total["gradient"][key][t],
                        recourse_USD_per_MW = recourse["gradient"][key][t],
                        day_ahead_USD_per_MW = total["contributions"]["day_ahead"][key][t],
                        capacity_budget_USD_per_MW = key=="P_DA_MW" ? 0.0 :
                                                     total["contributions"]["capacity_budget"][t],
                    ),
                )
            end
        end
        allowed=(
            "schema",
            "version",
            "case_sha256",
            "run_id",
            "status",
            "solver_objective",
            "values",
            "raw_constraint_duals",
            "raw_bound_duals",
        )
        result=Dict(key=>x.result[key] for key in allowed if haskey(x.result, key))
        witness=Dict(
            "schema"=>"r5-dispatch-duality-witness-v1",
            "origin"=>"synthetic",
            "record_id"=>id,
            "case"=>x.case.data,
            "result"=>result,
            "parent_result_sha256"=>parent_hash,
            "original_validation_sha256"=>bytes2hex(
                sha256(PaperRebuild.r5_dispatch_validation_text(x.result["validation"])),
            ),
        )
        file="witnesses/"*id*".toml"
        write(joinpath(dest, split(file, '/')...), PaperRebuild.r5_market_text(witness))
        witness_hashes[file]=bytes2hex(sha256(read(joinpath(dest, split(file, '/')...))))
    end
    CSV.write(joinpath(dest, "comparison.csv"), summary)
    CSV.write(joinpath(dest, "kkt-residuals.csv"), residuals)
    CSV.write(joinpath(dest, "sensitivity.csv"), sensitivity)
    root=normpath(joinpath(@__DIR__, ".."))
    meta=Dict(
        "schema"=>"r5-dispatch-duality-audit-v1",
        "origin"=>"synthetic",
        "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
        "source_sha256"=>source_hashes,
        "parent_batch"=>study["batch_id"],
        "parent_study_sha256"=>bytes2hex(sha256(read(study_path))),
        "parent_config_sha256"=>study["config_sha256"],
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "records"=>length(summary),
        "kkt_pass"=>count(x->x.kkt_pass, summary),
        "solver_reexecuted"=>false,
        "witness_sha256"=>witness_hashes,
        "kkt_tolerance"=>1e-6,
        "gap_tolerance"=>1e-4,
        "scope"=>"Read-only numerical KKT and fixed-comfort LP subgradients; historical validation unchanged.",
    )
    all(bytes2hex(sha256(read(paths[k])))==v for (k, v) in source_hashes)||error("审计期间源码改变")
    write(joinpath(dest, "audit.toml"), PaperRebuild.r5_market_text(meta))
    println(
        "Recourse KKT audit: ",
        meta["kkt_pass"],
        "/",
        meta["records"],
        "; residuals=",
        length(residuals),
        "; no solves.",
    )
end
length(ARGS)==2||error("参数：已完成父批次study.toml 新审计目录")
audit_r5_dispatch_duality(abspath(ARGS[1]), abspath(ARGS[2]))
