"""
    validate_r4_discrete(case, result)

从每个原始模式结果重新核验共识、模型、控制哈希与成本重构，独立选择最低费用候选。
中央穷举只有覆盖所有模式且各项具有有效下界或不可行证据时，才能合并最小下界。
分布枚举仅报告可行候选；不把集中参考、局部增广目标界或未执行模式当作证书。
原电网通过只针对本批稳态模型，不证明动态热网。测试R4 discrete audit。
"""
function validate_r4_discrete(c::R4Case, r)
    r["schema"]=="r4-discrete-run-v1" && r["input_sha256"]==c.sha256 || error("枚举输入错误")
    method=r["method"]
    method in ("distributed", "central_enumeration") || error("方法错误")
    patterns=r4_battery_patterns(c)
    rows=r["records"]
    r["pattern_count"]==length(patterns)==length(rows) || error("模式清单不完整")
    attempted=0
    raw_pass=0
    accepted=0
    physical=0
    converged=0
    best=0
    bestphysical=0
    cost=Inf
    physicalcost=Inf
    bounds=Float64[]
    bounded=method=="central_enumeration"
    mode_rows=Dict{String,Any}[]
    for (index, entry) in enumerate(rows)
        entry["index"]==index && entry["modes"]==patterns[index] || error("模式顺序或取值改变")
        if !haskey(entry, "raw")
            entry["status"]=="not_run_budget" || error("缺失模式结果")
            bounded=false
            push!(
                mode_rows,
                Dict("index"=>index, "model_pass"=>false, "electric_original_pass"=>false),
            )
            continue
        end
        attempted+=1
        raw=entry["raw"]
        entry["status"]==raw["status"] || error("原始状态改变")
        if method=="distributed"
            raw["modes"]==patterns[index] && raw["purpose"]=="swm" || error("分布模式错误")
            isequal(validate_r4_distributed(c, raw), raw["validation"]) || error("分布验收改变")
            original=get(raw, "candidate", nothing)
            consensus=raw["validation"]["consensus_A4_pass"]
            converged+=raw["status"]=="consensus_converged"
        else
            isequal(validate_r4_solution(c, raw), raw["validation"]) || error("中央验收改变")
            original=haskey(raw, "values") ? raw : nothing
            consensus=true
            converged+=raw["status"]=="solver_optimal"
            if raw["status"]=="infeasible_certified"
                all(x["termination"]=="INFEASIBLE" for x in raw["solves"]) ||
                    error("不可行证据不足")
            elseif haskey(raw, "objective_bound") && isfinite(raw["objective_bound"])
                push!(bounds, raw["objective_bound"])
            else
                bounded=false
            end
        end
        mp=false
        pp=false
        actual=NaN
        if original!==nothing
            maximum(abs, original["values"]["z"]-patterns[index])<=1e-6 ||
                error("控制不符合冻结模式")
            rec=reconstruct_r4_cost(c, original)
            isequal(rec, entry["reconstruction"]) || error("重构控制、费用或判定改变")
            raw_pass+=rec["raw_validation"]["model_pass"]
            candidate=rec["candidate"]
            mp=consensus&&candidate["validation"]["model_pass"]
            pp=mp&&candidate["validation"]["electric_original_pass"]
            actual=candidate["operating_cost"]
            accepted+=mp
            physical+=pp
            if mp&&actual<cost
                best=index
                cost=actual
            end
            if pp&&actual<physicalcost
                bestphysical=index
                physicalcost=actual
            end
        elseif haskey(entry, "reconstruction")
            error("无原始候选却有重构")
        end
        push!(
            mode_rows,
            Dict(
                "index"=>index,
                "model_pass"=>mp,
                "electric_original_pass"=>pp,
                "operating_cost"=>actual,
            ),
        )
    end
    lower=bounded&&!isempty(bounds) ? minimum(bounds) : NaN
    gap=isfinite(cost)&&isfinite(lower) ? abs(cost-lower)/max(1, abs(cost)) : NaN
    return Dict(
        "record_pass"=>true,
        "all_modes_attempted"=>attempted==length(patterns),
        "attempted_modes"=>attempted,
        "raw_model_pass_count"=>raw_pass,
        "accepted_model_count"=>accepted,
        "electric_original_pass_count"=>physical,
        "mode_solver_converged_count"=>converged,
        "best_model_index"=>best,
        "best_physical_index"=>bestphysical,
        "best_model_cost"=>cost,
        "best_physical_cost"=>physicalcost,
        "objective_bound"=>lower,
        "relative_gap"=>gap,
        "cost_optimization_complete"=>bounded&&isfinite(gap)&&gap<=1e-4,
        "mode_checks"=>mode_rows,
    )
end
