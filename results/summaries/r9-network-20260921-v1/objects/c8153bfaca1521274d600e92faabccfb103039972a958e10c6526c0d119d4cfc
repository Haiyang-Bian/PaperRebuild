const R6_STUDY_VERIFY_FILE=@__FILE__

"""
    r6_summarize_days(ids, validations; epsilon, confidence=0.95)

从逐日独立验算聚合联合室温事件、缺失费用与已完成日的费用分布。R6-F1。
未知保留在概率分母；费用不完整时只给observed条件统计，不生成总体均费或排名。
标签不能替代实际事件；调用和越界指标仅汇总确有合格候选的日子，并明确计数。
"""
function r6_summarize_days(ids, vals; epsilon, confidence = 0.95)
    length(ids)==length(vals)>0 && length(unique(ids))==length(ids) || error("日身份或数量错误")
    events=Symbol[]
    costs=Float64[]
    peak=Float64[]
    delivered=0.0
    call=0.0
    models=0
    for v in vals
        event=Symbol(v["comfort_outcome"])
        event in (:pass, :violation, :unknown) || error("日事件错误")
        model=v["model_pass"]
        complete=v["cost_complete"]
        complete isa Bool && model isa Bool || error("日状态须为布尔值")
        complete && !model && error("无可行模型不能宣称费用完成")
        event!=:unknown && !complete && error("未完成策略不能写成已观察事件")
        complete && event==:unknown && error("已完成策略缺少事件")
        push!(events, event)
        models+=model
        if complete
            c=v["operating_net_cost"]
            isfinite(c) || error("完整费用不是有限数")
            push!(costs, c)
        end
        if model
            e=v["peak_excess_K"]
            isfinite(e)&&e>=0 || error("温度违反幅度错误")
            push!(peak, e)
            v["delivery_budget_pass"] || error("合格日模型未通过交付硬约束")
            call+=v["called_energy_MWh"]
            delivered+=v["mismatch_MWh"]
        end
    end
    risk=r6_risk_evidence(events; epsilon, confidence)
    n=length(ids)
    allcost=length(costs)==n
    Dict{String,Any}(
        "schema"=>"r6-day-summary-v1",
        "n"=>n,
        "risk"=>risk,
        "ids_sha256"=>bytes2hex(sha256(r5_market_text(Dict("ids"=>String.(ids))))),
        "model_pass_days"=>models,
        "complete_cost_days"=>length(costs),
        "missing_cost_days"=>n-length(costs),
        "all_costs_complete"=>allcost,
        "mean_net_cost_USD"=>allcost ? sum(costs)/n : NaN,
        "observed_mean_net_cost_USD"=>isempty(costs) ? NaN : sum(costs)/length(costs),
        "observed_cost_quantiles_USD"=>isempty(costs) ? Dict{String,Float64}() :
                                       Dict(
            "q05"=>r6_quantile(costs, 0.05),
            "q50"=>r6_quantile(costs, 0.5),
            "q95"=>r6_quantile(costs, 0.95),
        ),
        "model_max_excess_K"=>isempty(peak) ? NaN : maximum(peak),
        "model_days_called_MWh"=>call,
        "model_days_mismatch_MWh"=>delivered,
        "model_days_relative_mismatch"=>call>0 ? delivered/call : NaN,
        "scope"=>"fixed_policy_complete_future_synthetic_days",
    )
end

"""
    select_r6_methods(spec, validation_records)

仅接受14项完整500日验证汇总，按R6-F2冻结六项测试策略。
合格集按总体均费选最小；1e-8 USD内同分取较小半径。无合格者按保守风险上界、缺失费用数、
完整均费、半径顺序回退，validated=false。验证选择后的区间不作最终保证，须独立测试。
"""
function select_r6_methods(s::R6StudySpec, records)
    r6_assert_study(s)
    candidates=r6_study_candidates(s)
    Set(keys(records))==Set(c["id"] for c in candidates) || error("验证候选清单不完整")
    identity=String[]
    for c in candidates
        r=records[c["id"]]
        r["split"]=="validation" && r["candidate"]==c || error("选择只能用对应候选的验证集")
        v=r["summary"]
        v["n"]==s.data["validation_days"] && v["risk"]["n"]==v["n"] || error("验证样本数不足")
        v["risk"]["epsilon"]==s.data["epsilon"] &&
        v["risk"]["one_sided_confidence"]==s.data["confidence"] || error("验证风险口径不同")
        v["all_costs_complete"]==(v["missing_cost_days"]==0) || error("费用完成字段冲突")
        0<=v["missing_cost_days"]<=v["n"] &&
        v["complete_cost_days"]+v["missing_cost_days"]==v["n"] || error("费用计数不一致")
        risk=v["risk"]
        counts=[risk["passed"], risk["violations"], risk["unknown"]]
        all(x->x isa Integer&&x>=0, counts)&&sum(counts)==v["n"] || error("风险计数错误")
        expected=r6_risk_evidence(
            vcat(fill(:pass, counts[1]), fill(:violation, counts[2]), fill(:unknown, counts[3]));
            epsilon = s.data["epsilon"],
            confidence = s.data["confidence"],
        )
        isequal(expected, risk) || error("风险上界不是原始计数的A5结果")
        v["all_costs_complete"] && !isfinite(v["mean_net_cost_USD"]) && error("完整均费缺失")
        push!(identity, v["ids_sha256"])
    end
    length(unique(identity))==1 || error("候选未使用相同验证日")
    selected=Dict{String,Any}[]
    for method in s.data["methods"]
        group=filter(c->c["method"]==method, candidates)
        val(c) = records[c["id"]]["summary"]
        eligible=filter(
            c->val(c)["all_costs_complete"] && val(c)["risk"]["upper"]<=s.data["epsilon"],
            group,
        )
        good=!isempty(eligible)
        if good
            low=minimum(val(c)["mean_net_cost_USD"] for c in eligible)
            tied=filter(c->val(c)["mean_net_cost_USD"]<=low+s.data["cost_tie_USD"], eligible)
            chosen=first(sort(tied; by = c->(c["radius"], c["order"])))
        else
            key(c) = (
                val(c)["risk"]["upper"],
                val(c)["missing_cost_days"],
                val(c)["all_costs_complete"] ? val(c)["mean_net_cost_USD"] : Inf,
                c["radius"],
                c["order"],
            )
            chosen=first(sort(group; by = key))
        end
        push!(
            selected,
            Dict(
                "method"=>method,
                "candidate_id"=>chosen["id"],
                "radius"=>chosen["radius"],
                "validated"=>good,
                "status"=>good ? "validation_eligible_minimum_cost" :
                          "fallback_not_validation_supported",
                "validation_summary"=>deepcopy(val(chosen)),
            ),
        )
    end
    Dict{String,Any}(
        "schema"=>"r6-selection-v1",
        "spec_sha256"=>s.sha256,
        "selected"=>selected,
        "validation_records_sha256"=>bytes2hex(sha256(r5_market_text(records))),
        "source_split"=>"validation",
        "test_used"=>false,
    )
end
