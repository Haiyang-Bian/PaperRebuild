# 只读原始日记录，重建完整残差后输出CNY统计；未运行日与操作失败均保留，不重新求解。
module R9HeldoutReport
using TOML, SHA, CSV, Dates, Random
include("r9_reserve_evaluation.jl")
const E=R9ReserveEvaluationStudy
const S=E.S
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")

# 读取重建残差摘要；没有候选的日返回NaN，不能用零值伪装通过。
function group_max(v, section, group = nothing)
    section_value = get(get(v, "stage", Dict()), section, Dict())
    groups = get(section_value, "row_groups", Dict())
    isempty(groups) && return NaN
    group === nothing && return maximum(g["max_normalized"] for g in values(groups))
    get(get(groups, group, Dict()), "max_normalized", NaN)
end

function cost_mean_interval(costs, statistics)
    # 费用均值的描述性区间复用原轨迹协议的2000次整日抽样与原种子；币种始终为CNY。
    seed, nrep = statistics["bootstrap_seed"], statistics["bootstrap_replicates"]
    confidence = statistics["confidence"]
    out = Dict{String,Any}(
        "currency"=>"CNY",
        "n"=>length(costs),
        "seed"=>seed,
        "replicates"=>nrep,
        "confidence"=>confidence,
        "method"=>"whole_day_percentile_bootstrap",
        "status"=>all(isfinite, costs) ? "complete" : "missing_costs",
        "is_optimality_bound"=>false,
    )
    all(isfinite, costs) || return out
    rng=Random.Xoshiro(seed)
    means=sort([
        sum(costs[rand(rng, eachindex(costs))] for _ in eachindex(costs))/length(costs) for
        _ in 1:nrep
    ])
    q(p) = begin
        x=1+(length(means)-1)*p
        lo, hi=floor(Int, x), ceil(Int, x)
        means[lo]+(x-lo)*(means[hi]-means[lo])
    end
    out["mean_CNY"]=sum(costs)/length(costs)
    out["lower_CNY"]=q((1-confidence)/2)
    out["upper_CNY"]=q((1+confidence)/2)
    out
end

function report(
    frozen,
    runs,
    out;
    common = joinpath(E.ROOT, "results/summaries/r9-common-input-20260921-v2"),
)
    ispath(out) && error("不覆盖原评价报告")
    ctx=E.openfreeze(frozen)
    hashfile(joinpath(common, "manifest.toml"))==ctx.m["protocol"]["parents"]["common_sha256"] ||
        error("统计规则父清单改变")
    statsrel="study/code/configs/r9/reserve-trajectories.toml"
    statsfile=joinpath(common, statsrel)
    hashfile(statsfile)==TOML.parsefile(joinpath(common, "manifest.toml"))["files"][statsrel] ||
        error("原整日统计协议改变")
    statistics=TOML.parsefile(statsfile)["statistics"]
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
                    trained_label = get(v, "trained_label", -1),
                    day_ahead_cost_CNY = get(v, "day_ahead_cost", NaN),
                    device_cost_CNY = get(v, "device_cost", NaN),
                    real_time_settlement_CNY = get(v, "real_time_settlement", NaN),
                    delivery_penalty_CNY = get(v, "delivery_penalty", NaN),
                    physical_max_normalized = group_max(v, "physics"),
                    lp_kkt_max_normalized = group_max(v, "lp"),
                    lp_gap_normalized = group_max(v, "lp", "gap/1"),
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
        summary["mean_cost_interval"]=cost_mean_interval(
            [v["cost_complete"] ? v["operating_net_cost"] : NaN for v in vals],
            statistics,
        )
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
    batch_files=Dict{String,String}("identity.toml"=>hashfile(joinpath(runs, "identity.toml")))
    batches=Dict{String,Any}[]
    for file in sort(readdir(joinpath(runs, "batches")))
        endswith(file, ".toml") || error("批次元数据文件类型改变")
        path=joinpath(runs, "batches", file)
        b=TOML.parsefile(path)
        b["freeze_sha256"]==ctx.hash || error("批次元数据身份不同")
        push!(batches, b)
        batch_files["batches/"*file]=hashfile(path)
    end
    # 装载/存档与逐日建模求解核验的时间分别列出；不是算法速度优势或训练端到端时间。
    timing=Dict(
        "batch_count"=>length(batches),
        "recorded_new_days"=>sum(b["new_days"] for b in batches; init = 0),
        "batch_elapsed_sec"=>sum(b["elapsed_sec"] for b in batches; init = 0.0),
        "batch_setup_sec"=>sum(b["setup_sec"] for b in batches; init = 0.0),
        "recorded_day_evaluation_sec"=>sum(
            r.elapsed_sec for r in rows if isfinite(r.elapsed_sec);
            init = 0.0,
        ),
        "day_budget_overruns"=>count(
            r->isfinite(r.budget_overrun_sec) && r.budget_overrun_sec>0,
            rows,
        ),
        "training_time_included"=>false,
        "independent_replay_time_included"=>false,
    )
    mkpath(out)
    CSV.write(joinpath(out, "daily.csv"), rows)
    toml(
        joinpath(out, "summary.toml"),
        Dict(
            "schema"=>"r9-heldout-report-v2",
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
            "timing"=>timing,
            "reporter_sha256"=>hashfile(@__FILE__),
            "adopted_physics"=>"linear_electric_fixed_flow_heat_building_dynamics",
            "original_ac_power_flow_certified"=>false,
            "nonzero_reserve_service_certified"=>false,
            "statistics_source_sha256"=>hashfile(statsfile),
        ),
    )
    toml(joinpath(out, "raw-files.toml"), Dict("files"=>rawhashes))
    toml(joinpath(out, "batch-records.toml"), Dict("files"=>batch_files, "batches"=>batches))
    cp(@__FILE__, joinpath(out, "report-source.jl"))
    cp(statsfile, joinpath(out, "statistics-source.toml"))
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
