const R6_SUPPORT_EVALUATION_FILE=@__FILE__

"""
    r6_support_label(policy, trajectory)

按训练时冻结的整日RMS距离选择最近代表，等距时取原顺序最早项，返回其已保存的舒适开关。
R6-E4是有限支持策略的项目外推；不能因此继承训练概率保证。不使用验证/测试结果重新拟合。
"""
function r6_support_label(p::R6Policy, v::AbstractMatrix)
    r6_assert_policy(p)
    p.data["evaluation_version"]=="r6_support_nearest_v1" || error("策略外推版本错误")
    T=p.data["physical"]["dispatch"]["T"]
    size(v)==(2, T)&&all(isfinite, v)&&all(x->0<=x<=1, v[1, :])&&all(x->-1<=x<=1, v[2, :]) ||
        error("新日轨迹范围错误")
    support=p.data["support"]
    isempty(support) && error("训练支持缺失")
    length(unique(s["id"] for s in support))==length(support) || error("训练支持ID重复")
    for s in support
        length(s["pv_fraction"])==T==length(s["activation_signed"]) &&
        all(x->isfinite(x)&&0<=x<=1, s["pv_fraction"]) &&
        all(x->isfinite(x)&&-1<=x<=1, s["activation_signed"]) || error("训练支持范围错误")
        s["label"] in (0, 1) && isfinite(s["raw_z"]) && abs(s["raw_z"]-s["label"])<=1e-8 ||
            error("训练舒适开关错误")
    end
    distances=[
        sqrt(
            sum(
                (v[1, t]-s["pv_fraction"][t])^2+((v[2, t]-s["activation_signed"][t])/2)^2 for
                t in 1:T
            )/(2T),
        ) for s in support
    ]
    i=argmin(distances)
    z=support[i]["label"]
    z in (0, 1)&&abs(support[i]["raw_z"]-z)<=1e-8 || error("训练开关被修改")
    Dict{String,Any}(
        "index"=>i,
        "scenario_id"=>support[i]["id"],
        "label"=>z,
        "distance"=>distances[i],
        "all_distances"=>distances,
        "tie_rule"=>"first_in_frozen_order",
    )
end

"""
    evaluate_r6_policy_day(policy, trajectory; id, optimizer, budget_sec=60)

正式R6样本外操作：继承最近训练代表的z，固定日前成交后最小化该分支实时费用。
z=0保留舒适域，z=1仅退到共同物理温度域；不暗中切换标签或调用舒适优先诊断。
共享预算包含输入构造、求解和检查；失败/超时留为未知。仍为完整未来轨迹两阶段评价。
"""
function evaluate_r6_policy_day(
    p::R6Policy,
    v::AbstractMatrix;
    id::AbstractString,
    optimizer,
    budget_sec = 60.0,
)
    start=time()
    isfinite(budget_sec)&&0<budget_sec<=600 || error("评价预算须有限且不超过600秒")
    c=r6_evaluation_day(p, v; id)
    label=r6_support_label(p, v)
    domain=p.data["physical"]["temperature_domain"]
    stage=label["label"]==0 ? :hard : :physical
    r=Dict{String,Any}(
        "schema"=>"r6-support-day-result-v1",
        "version"=>"r6_support_nearest_v1",
        "run_id"=>"r6-support-day-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "policy_sha256"=>p.sha256,
        "case_sha256"=>c.sha256,
        "trajectory_id"=>String(id),
        "trajectory_sha256"=>bytes2hex(sha256(r5_market_text(Dict("values"=>r5_market_rows(v))))),
        "label"=>label,
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r6_evaluation_science_hashes(),
    )
    r["stage"]=r6_evaluation_stage(c, domain, stage, nothing, optimizer, start+budget_sec)
    r["status"]=r["stage"]["status"]
    r["validation"]=validate_r6_policy_day(p, v, r)
    r["elapsed_sec"]=time()-start
    r["budget_overrun_sec"]=max(0, time()-start-budget_sec)
    r["source_hashes_at_solve"]==r6_evaluation_science_hashes() || error("策略日评价期间源码变化")
    r
end

"""
    validate_r6_policy_day(policy, trajectory, result)

重新匹配训练代表、独立回代分支物理/KKT/费用与实际室温事件；标签不等于实际违约。
未能完成所声明操作时记unknown，仍须保留在风险分母。另存实际调用量分母，不改原5-4容量分母。
"""
function validate_r6_policy_day(p::R6Policy, v::AbstractMatrix, r)
    c=r6_evaluation_day(p, v; id = r["trajectory_id"])
    label=r6_support_label(p, v)
    r["schema"]=="r6-support-day-result-v1" &&
    r["version"]==p.data["evaluation_version"] &&
    r["policy_sha256"]==p.sha256 &&
    r["case_sha256"]==c.sha256 &&
    r["label"]==label &&
    r["trajectory_sha256"]==bytes2hex(sha256(r5_market_text(Dict("values"=>r5_market_rows(v))))) ||
        error("样本外策略/轨迹身份不符")
    r["stage"]["stage"]==(label["label"]==0 ? "hard" : "physical") ||
        error("不能切换已冻结的舒适分支")
    r["status"]==r["stage"]["status"] || error("日状态与实际阶段不同")
    x=r6_recourse_check(c, p.data["physical"]["temperature_domain"], r["stage"])
    out=Dict{String,Any}(
        "stage"=>x,
        "model_pass"=>x["model_pass"],
        "policy_complete"=>x["cost_complete"],
        "cost_complete"=>x["cost_complete"],
        "comfort_outcome"=>"unknown",
        "trained_label"=>label["label"],
    )
    x["model_pass"] || return out
    out["peak_excess_K"]=x["peak_excess_K"]
    out["comfort_outcome"]=x["cost_complete"] ? (x["peak_excess_K"]<=1e-4 ? "pass" : "violation") :
                           "unknown"
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
        out[key]=x["physics"][key]
    end
    out["called_energy_MWh"]=c.data["dt_h"]*sum(abs, out["request_MW"])
    out["call_relative_mismatch"]=out["called_energy_MWh"]>0 ?
                                  out["mismatch_MWh"]/out["called_energy_MWh"] : NaN
    out["delivery_budget_pass"]=x["physics"]["delivery_pass"]
    out
end
