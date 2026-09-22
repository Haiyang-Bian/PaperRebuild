# 摘要/逐日表/冻结输入/图源的只读一致性检查；不能替代原变量的数值回放。
using Test
module R9HeldoutArtifactCheck
using Test, CSV, TOML, SHA, Random
include("r9_reserve_evaluation.jl")
const E=R9ReserveEvaluationStudy
hashfile(p) = bytes2hex(sha256(read(p)))
function manifest(dir)
    m=TOML.parsefile(joinpath(dir, "artifacts.toml"))["files"]
    actual=Dict(
        replace(relpath(joinpath(d, f), dir), '\\'=>'/')=>hashfile(joinpath(d, f)) for
        (d, _, names) in walkdir(dir) for f in names
    )
    delete!(actual, "artifacts.toml")
    actual==m || error("交付字节清单不符")
    all(k->!isabspath(k) && !occursin(':', k) && !(".." in split(k, '/')), keys(m)) ||
        error("交付路径越界")
    all(k->filesize(joinpath(dir, k))<=5*1024^2, keys(m)) || error("交付文件超过5 MiB")
    m
end

function check(frozen, report, figure = nothing)
    manifest(report)
    ctx=E.openfreeze(frozen)
    s=TOML.parsefile(joinpath(report, "summary.toml"))
    s["schema"]=="r9-heldout-report-v2" || error("报告版本")
    s["freeze_sha256"]==ctx.hash && s["origin"]=="synthetic" && s["currency"]=="CNY" ||
        error("报告来源")
    s["raw_numeric_replay_performed"] && !s["optimization_performed"] || error("报告职责")
    s["raw_records_required_for_independent_numeric_replay"] || error("原值需要性丢失")
    !s["original_ac_power_flow_certified"] && !s["nonzero_reserve_service_certified"] ||
        error("越界物理/收益声明")
    hashfile(joinpath(report, "report-source.jl"))==s["reporter_sha256"] || error("报告器字节改变")
    statsfile=joinpath(report, "statistics-source.toml")
    hashfile(statsfile)==s["statistics_source_sha256"]=="6142568e35d6fc3d649e0d42749f27b088334f4ff2a3d098f4d906f5a166c058" ||
        error("原整日统计协议来源")
    statistics=TOML.parsefile(statsfile)["statistics"]
    rows=collect(CSV.File(joinpath(report, "daily.csv")))
    ids=String[d["id"] for d in ctx.days]
    owners=sort(unique(ctx.m["slots"][k]["compute_owner"] for k in keys(ctx.policies)))
    s["distinct_operations"]==length(owners)==length(s["operations"]) || error("独立操作数量")
    length(rows)==length(owners)*length(ids) || error("完整日数量")
    raw=TOML.parsefile(joinpath(report, "raw-files.toml"))["files"]
    expected_raw=Set{String}()
    for owner in owners
        rr=filter(r->r.owner==owner, rows)
        String[r.id for r in rr]==ids || error("日身份/顺序改变")
        length(unique(r.run_id for r in rr if r.status!="not_executed"))==count(
            r->r.status!="not_executed",
            rr,
        ) || error("重复运行身份")
        vals=[
            Dict{String,Any}(
                "currency"=>"CNY",
                "model_pass"=>r.model_pass,
                "kkt_pass"=>r.kkt_pass,
                "cost_complete"=>r.cost_complete,
                "comfort_outcome"=>r.comfort_outcome,
                "operating_net_cost"=>r.net_cost_CNY,
            ) for r in rr
        ]
        computed=E.call(
            ctx.lib,
            :summarize_r9_reserve_days,
            ids,
            vals;
            currency = "CNY",
            epsilon = ctx.m["protocol"]["epsilon"],
            confidence = ctx.m["protocol"]["confidence"],
        )
        recorded=s["operations"][owner]
        all(k->isequal(computed[k], recorded[k]), keys(computed)) || error("风险/费用摘要不符")
        completed=count(r->r.status!="not_executed", rr)
        interval=recorded["mean_cost_interval"]
        interval["currency"]=="CNY" &&
        interval["n"]==length(ids) &&
        !interval["is_optimality_bound"] || error("费用区间含义")
        interval["seed"]==statistics["bootstrap_seed"] &&
        interval["replicates"]==statistics["bootstrap_replicates"] &&
        interval["confidence"]==statistics["confidence"] || error("自助规则改变")
        if all(r->r.cost_complete, rr)
            interval["status"]=="complete" || error("费用区间状态")
            costs=[r.net_cost_CNY for r in rr]
            rng=Random.Xoshiro(statistics["bootstrap_seed"])
            means=[
                sum(costs[rand(rng, eachindex(costs))] for _ in eachindex(costs))/length(costs) for
                _ in 1:statistics["bootstrap_replicates"]
            ]
            lo=E.call(ctx.lib, :r6_quantile, means, (1-statistics["confidence"])/2)
            hi=E.call(ctx.lib, :r6_quantile, means, (1+statistics["confidence"])/2)
            interval["mean_CNY"]==sum(costs)/length(costs) &&
            interval["lower_CNY"]==lo &&
            interval["upper_CNY"]==hi || error("费用区间重算")
        else
            interval["status"]=="missing_costs" &&
            !haskey(interval, "lower_CNY") &&
            !haskey(interval, "mean_CNY") || error("缺失日产生总体费用区间")
        end
        recorded["saved_day_records"]==completed &&
        recorded["all_days_executed"]==(completed==length(ids)) &&
        recorded["formal_test_complete"]==(completed==length(ids)) || error("执行完整性不符")
        for r in rr
            if r.status=="not_executed"
                r.comfort_outcome=="unknown" && !r.cost_complete && isnan(r.net_cost_CNY) ||
                    error("未执行日被记成功")
            else
                ismissing(r.run_id) && error("已执行日缺少运行ID")
                isfinite(r.elapsed_sec) &&
                r.elapsed_sec>=0 &&
                r.budget_overrun_sec==max(0.0, r.elapsed_sec-ctx.m["protocol"]["day_budget_sec"]) ||
                    error("逐日预算记录")
                for file in ("policy.toml", "trajectory.toml", "result.toml", "files.toml")
                    push!(expected_raw, owner*"/"*r.id*"/"*file)
                end
            end
            if r.cost_complete
                isfinite(r.physical_max_normalized) && 0<=r.physical_max_normalized<=1 ||
                    error("物理残差")
                isfinite(r.lp_kkt_max_normalized) && 0<=r.lp_kkt_max_normalized<=1 ||
                    error("KKT残差")
                0<=r.lp_gap_normalized<=1 || error("LP间隙")
                isapprox(
                    r.net_cost_CNY,
                    r.day_ahead_cost_CNY+r.device_cost_CNY+r.real_time_settlement_CNY+r.delivery_penalty_CNY;
                    rtol = 1e-12,
                    atol = 1e-8,
                ) || error("费用分项")
                r.comfort_outcome==(r.peak_excess_K<=1e-4 ? "pass" : "violation") ||
                    error("实际室温事件")
                r.trained_label in (0, 1) && r.called_energy_MWh>=0 && r.mismatch_MWh>=0 ||
                    error("分支/调用数据")
            end
        end
    end
    Set(keys(raw))==expected_raw && all(h->occursin(r"^[0-9a-f]{64}$", h), values(raw)) ||
        error("原值文件清单")
    for (name, old) in ctx.m["slots"]
        slot=s["slots"][name]
        all(k->isequal(slot[k], old[k]), keys(old)) || error("父训练记录改变")
        if old["test_operation_defined"]
            slot["summary_owner"]==old["compute_owner"] &&
            slot["performs_unique_day_computation"]==(name==old["compute_owner"]) ||
                error("重复计算声明")
        else
            slot["out_of_sample_status"]=="training_candidate_unavailable" &&
            !slot["risk_estimate_defined"] || error("无候选方案被补造")
        end
    end
    br=TOML.parsefile(joinpath(report, "batch-records.toml"))
    batches=br["batches"]
    timing=s["timing"]
    all(b->b["freeze_sha256"]==ctx.hash, batches) || error("批次身份")
    timing["batch_count"]==length(batches) &&
    timing["recorded_new_days"]==sum(b["new_days"] for b in batches; init = 0) || error("批次数量")
    timing["batch_elapsed_sec"]==sum(b["elapsed_sec"] for b in batches; init = 0.0) &&
    timing["batch_setup_sec"]==sum(b["setup_sec"] for b in batches; init = 0.0) || error("批次时间")
    !timing["training_time_included"] && !timing["independent_replay_time_included"] ||
        error("时间口径")
    if figure!==nothing
        manifest(figure)
        fc=TOML.parsefile(joinpath(figure, "figure-config.toml"))
        fc["source_artifacts_sha256"]==hashfile(joinpath(report, "artifacts.toml")) &&
        fc["freeze_sha256"]==ctx.hash || error("图源身份")
        fc["synthetic_replacement_inputs"] && !fc["optimization_performed"] || error("图表职责")
        read(joinpath(figure, "source.csv"))==read(joinpath(report, "daily.csv")) &&
        read(joinpath(figure, "summary.toml"))==read(joinpath(report, "summary.toml")) ||
            error("图源数值改变")
        fc["distinct_operations"]==length(owners) &&
        fc["operation_sha256"]==ctx.m["slots"][only(owners)]["operation_sha256"] ||
            error("图表独立操作")
        fc["run_ids"]==String[r.run_id for r in rows if !ismissing(r.run_id)] || error("图表运行身份")
    end
    true
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (2, 3) || error("usage: check_r9_heldout_artifacts.jl FREEZE REPORT [FIGURES]")
    @testset "R9 held-out summary, distinct operations and F51" begin
        @test R9HeldoutArtifactCheck.check(abspath.(ARGS)...)
    end
end
