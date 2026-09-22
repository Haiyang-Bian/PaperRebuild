const R9_EVALUATION_SOLVE_FILE = @__FILE__

"""
    evaluate_r9_reserve_day(policy, trajectory; id, optimizer, budget_sec=60)

R9-OS3：固定锁定成交及最近代表的舒适分支，求解一个完整日的连续补救费用问题。
复用已核查R6补救核，不调用舒适优先修正，不改变标签；物理失败、缺许可及超时均保存。
共享截止时间包含输入和建模；独立核验计入总耗时并单列预算超出。完整未来轨迹不是在线控制。
"""
function evaluate_r9_reserve_day(
    p::R9ReservePolicy,
    x::AbstractMatrix;
    id::AbstractString,
    optimizer,
    budget_sec = 60.0,
)
    started = time()
    isfinite(budget_sec) && 0 < budget_sec <= 600 || error("逐日预算须为(0,600]秒")
    c = r9_reserve_evaluation_day(p, x; id)
    label = r9_reserve_support_label(p, x)
    r = Dict{String,Any}(
        "schema"=>"r9-reserve-day-v1",
        "version"=>"r9_nearest_recourse_v1",
        "run_id"=>"r9-day-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "currency"=>p.data["currency"],
        "policy_sha256"=>p.sha256,
        "operation_sha256"=>p.operation_sha256,
        "case_sha256"=>c.sha256,
        "trajectory_id"=>String(id),
        "trajectory_sha256"=>r9_evaluation_hash(Dict("values"=>r5_market_rows(x))),
        "label"=>label,
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r9_evaluation_science_hashes(),
    )
    stage = label["label"] == 0 ? :hard : :physical
    r["stage"] = r6_evaluation_stage(
        c,
        p.data["temperature_domain"],
        stage,
        nothing,
        optimizer,
        started+budget_sec,
    )
    r["status"] = r["stage"]["status"]
    r["validation"] = r9_compact_day_validation(validate_r9_reserve_day(p, x, r))
    r["validation_storage"] = "recomputed_group_summary_v1"
    r["elapsed_sec"] = time()-started
    r["budget_overrun_sec"] = max(0.0, r["elapsed_sec"]-budget_sec)
    r["source_hashes_at_solve"] == r9_evaluation_science_hashes() || error("逐日运行期间源码改变")
    r
end

"""
    validate_r9_reserve_day(policy, trajectory, result)

从原输入重新匹配代表、重算分支物理/KKT/费用和实际舒适事件，核验固定成交与日身份。
只有规定操作完成才分类pass/violation；未知日保留在风险分母。交付能量及原容量归一化口径单列，
零备用的风险表现不能解释成备用交付能力。R9-OS3/OS4；不求解或写文件。
"""
function validate_r9_reserve_day(p::R9ReservePolicy, x::AbstractMatrix, r)
    c = r9_reserve_evaluation_day(p, x; id = r["trajectory_id"])
    label = r9_reserve_support_label(p, x)
    r["schema"] == "r9-reserve-day-v1" &&
    r["version"] == p.data["evaluation_version"] &&
    r["policy_sha256"] == p.sha256 &&
    r["operation_sha256"] == p.operation_sha256 &&
    r["case_sha256"] == c.sha256 &&
    r["currency"] == p.data["currency"] &&
    r["label"] == label &&
    r["trajectory_sha256"] == r9_evaluation_hash(Dict("values"=>r5_market_rows(x))) ||
        error("逐日输入或操作身份不符")
    r["stage"]["stage"] == (label["label"] == 0 ? "hard" : "physical") &&
    r["status"] == r["stage"]["status"] || error("日状态或冻结舒适分支改变")
    check = r6_recourse_check(c, p.data["temperature_domain"], r["stage"])
    out = Dict{String,Any}(
        "stage"=>check,
        "model_pass"=>check["model_pass"],
        "kkt_pass"=>check["kkt_pass"],
        "cost_complete"=>check["cost_complete"],
        "policy_complete"=>check["cost_complete"],
        "comfort_outcome"=>"unknown",
        "currency"=>p.data["currency"],
        "trained_label"=>label["label"],
    )
    check["model_pass"] || return out
    out["peak_excess_K"] = check["peak_excess_K"]
    out["comfort_outcome"] =
        check["cost_complete"] ? (check["peak_excess_K"] <= 1e-4 ? "pass" : "violation") : "unknown"
    for key in (
        "operating_net_cost",
        "day_ahead_cost",
        "device_cost",
        "real_time_settlement",
        "delivery_penalty",
        "request_MW",
        "delivered_MW",
        "mismatch_MWh",
        "mismatch_limit_MWh",
    )
        out[key] = check["physics"][key]
    end
    out["called_energy_MWh"] = c.data["dt_h"]*sum(abs, out["request_MW"])
    out["call_relative_mismatch"] =
        out["called_energy_MWh"] > 0 ? out["mismatch_MWh"]/out["called_energy_MWh"] : NaN
    out["delivery_budget_pass"] = check["physics"]["delivery_pass"]
    out
end
