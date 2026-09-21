# 只读原始日记录，重建完整残差后输出CNY统计；未运行日与操作失败均保留，不重新求解。
module R9HeldoutReport
using TOML, SHA, CSV, Dates
include("r9_reserve_evaluation.jl")
const E=R9ReserveEvaluationStudy
const S=E.S
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")

function report(frozen, runs, out)
    ispath(out) && error("不覆盖原评价报告")
    ctx=E.openfreeze(frozen)
    TOML.parsefile(joinpath(runs, "identity.toml"))["freeze_sha256"]==ctx.hash ||
        error("原始运行身份不同")
    ids=[d["id"] for d in ctx.days]
    rows=NamedTuple[]
    summaries=Dict{String,Any}()
    rawhashes=Dict{String,String}()
    owners=sort(unique(ctx.m["slots"][s]["compute_owner"] for s in keys(ctx.policies)))
    for owner in owners
        vals=Dict{String,Any}[]
        completed=0
        for i in eachindex(ids)
            dir=joinpath(runs, owner, ids[i])
            r=nothing
            if ispath(dir)
                # 数值重读同时检查原文件集合、哈希、单位、完整KKT及实际室温事件。
                got=E.call(ctx.lib, :read_r9_reserve_day, dir)
                E.day_identity(ctx, owner, i, got)
                r=got.result
                v=E.call(ctx.lib, :r9_compact_day_validation, got.validation)
                for f in readdir(dir)
                    rawhashes[owner*"/"*ids[i]*"/"*f]=hashfile(joinpath(dir, f))
                end
                completed+=1
            else
                v=Dict{String,Any}(
                    "currency"=>"CNY",
                    "model_pass"=>false,
                    "kkt_pass"=>false,
                    "cost_complete"=>false,
                    "comfort_outcome"=>"unknown",
                )
            end
            push!(vals, v)
            push!(
                rows,
                (
                    owner = owner,
                    id = ids[i],
                    run_id = r===nothing ? "" : r["run_id"],
                    status = r===nothing ? "not_executed" : r["status"],
                    model_pass = v["model_pass"],
                    kkt_pass = v["kkt_pass"],
                    cost_complete = v["cost_complete"],
                    comfort_outcome = v["comfort_outcome"],
                    peak_excess_K = get(v, "peak_excess_K", NaN),
                    net_cost_CNY = get(v, "operating_net_cost", NaN),
                    called_energy_MWh = get(v, "called_energy_MWh", NaN),
                    mismatch_MWh = get(v, "mismatch_MWh", NaN),
                    elapsed_sec = r===nothing ? NaN : r["elapsed_sec"],
                    budget_overrun_sec = r===nothing ? NaN : r["budget_overrun_sec"],
                ),
            )
            i%50==0 && (println(owner, " replayed prefix=", i, " saved=", completed); flush(stdout))
        end
        summary=E.call(
            ctx.lib,
            :summarize_r9_reserve_days,
            ids,
            vals;
            currency = "CNY",
            epsilon = ctx.m["protocol"]["epsilon"],
            confidence = ctx.m["protocol"]["confidence"],
        )
        summary["saved_day_records"]=completed
        summary["all_days_executed"]=completed==length(ids)
        summary["formal_test_complete"]=completed==length(ids)
        summaries[owner]=summary
        GC.gc()
    end
    slots=deepcopy(ctx.m["slots"])
    for (scheme, slot) in slots
        if slot["test_operation_defined"]
            slot["summary_owner"]=slot["compute_owner"]
            slot["performs_unique_day_computation"]=slot["compute_owner"]==scheme
        else
            slot["out_of_sample_status"]="training_candidate_unavailable"
            slot["risk_estimate_defined"]=false
        end
    end
    mkpath(out)
    CSV.write(joinpath(out, "daily.csv"), rows)
    toml(
        joinpath(out, "summary.toml"),
        Dict(
            "schema"=>"r9-heldout-report-v1",
            "origin"=>"synthetic",
            "currency"=>"CNY",
            "freeze_sha256"=>ctx.hash,
            "created_utc"=>string(now(UTC)),
            "slots"=>slots,
            "operations"=>summaries,
            "raw_numeric_replay_performed"=>true,
            "optimization_performed"=>false,
            "scope"=>"frozen_complete_future_operation_not_online_control_or_original_author_inputs",
            "raw_records_required_for_independent_numeric_replay"=>true,
            "distinct_operations"=>length(owners),
        ),
    )
    toml(joinpath(out, "raw-files.toml"), Dict("files"=>rawhashes))
    cp(@__FILE__, joinpath(out, "report-source.jl"))
    toml(
        joinpath(out, "artifacts.toml"),
        Dict("files"=>Dict(f=>hashfile(joinpath(out, f)) for f in readdir(out))),
    )
    println("Saved independent numerical report; distinct operations=", length(owners))
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3 || error("usage: report_r9_evaluation.jl FREEZE RAW_RUNS NEW_REPORT")
    R9HeldoutReport.report(abspath.(ARGS)...)
end
