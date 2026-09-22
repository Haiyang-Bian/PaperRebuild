const R6_EVALUATION_SOLVE_FILE=@__FILE__

function r6_evaluation_stage(c, domain, stage, cap, optimizer, deadline)
    r=Dict{String,Any}("stage"=>string(stage), "case_sha256"=>c.sha256, "has_candidate"=>false)
    cap===nothing || (r["peak_cap_K"]=cap)
    try
        if time()>=deadline
            r["status"]="budget_exhausted_before_build"
            return r
        end
        b=build_r6_recourse(c, domain; stage, peak_cap = cap, optimizer)
        r["model_types"]=b.model_types
        merge!(r, r5_risk_optimize!(b.model, deadline))
        if r["has_candidate"]
            r["flat_values"]=Dict(k=>value(v) for (k, v) in b.variables)
            has_duals(b.model) && (r["raw_duals"]=Dict(k=>dual(ref) for (k, ref) in b.rows))
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r
end

"""
    evaluate_r6_day(day, temperature_domain; optimizer, spec=R6EvaluationSpec(), budget_sec=60)
    evaluate_r6_day(policy, trajectory; id, optimizer, ...)

执行独立舒适能力诊断的共享截止时间：硬舒适费用→仅明确不可行时最小越界→该最小面费用。
保留各阶段原始解/对偶/目标，未知不改成成功；没有改动成交、硬容量、温度物理域或初末条件。
首接口用于解析例与已冻结单日，第二接口从核验策略派生日输入。R6-E1/E2；不写文件。
"""
function evaluate_r6_day(
    c::R5DispatchCase,
    domain;
    optimizer,
    spec = R6EvaluationSpec(),
    budget_sec = 60.0,
    deadline = nothing,
)
    start=time()
    r6_assert_evaluation(spec)
    r6_physical_day(c, domain)
    isfinite(budget_sec)&&0<budget_sec<=600 || error("单日预算须有限且不超过600秒")
    deadline=deadline===nothing ? start+budget_sec : min(deadline, start+budget_sec)
    isfinite(deadline) || error("截止时间必须有限")
    r=Dict{String,Any}(
        "schema"=>"r6-day-result-v1",
        "version"=>spec.data["version"],
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "source_hashes_at_solve"=>r6_evaluation_science_hashes(),
        "run_id"=>"r6-day-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "spec_sha256"=>spec.sha256,
        "temperature_domain_sha256"=>bytes2hex(sha256(r5_market_text(domain))),
        "budget_sec"=>Float64(budget_sec),
        "stages"=>Dict{String,Any}(),
        "status"=>"not_started",
    )
    hard=r6_evaluation_stage(c, domain, :hard, nothing, optimizer, deadline)
    r["stages"]["hard"]=hard
    hv=r6_recourse_check(c, domain, hard)
    if hv["model_pass"]
        r["selected_stage"]="hard"
        r["status"]=hv["cost_complete"] ? "hard_comfort_cost_complete" :
                    "hard_candidate_cost_incomplete"
    elseif hard["status"]=="solver_infeasible"
        peak=r6_evaluation_stage(c, domain, :peak, nothing, optimizer, deadline)
        r["stages"]["peak"]=peak
        pv=r6_recourse_check(c, domain, peak)
        r["status"]=peak["status"]=="solver_infeasible" ? "physical_model_infeasible" :
                    "peak_optimization_incomplete"
        if pv["model_pass"]
            r["selected_stage"]="peak"
            if pv["peak_complete"] && pv["peak_excess_K"]<=spec.data["lexicographic_allowance_K"]
                r["status"]="hard_soft_feasibility_conflict"
            elseif pv["peak_complete"]
                cap=peak["flat_values"]["peak"]+spec.data["lexicographic_allowance_K"]
                cost=r6_evaluation_stage(c, domain, :cost, cap, optimizer, deadline)
                r["stages"]["cost"]=cost
                cv=r6_recourse_check(c, domain, cost)
                if cv["model_pass"]
                    r["selected_stage"]="cost"
                    r["status"]=cv["cost_complete"] ? "minimum_violation_cost_complete" :
                                "minimum_violation_cost_incomplete"
                else
                    r["status"]="peak_candidate_cost_stage_failed"
                end
            end
        end
    else
        r["status"]="hard_stage_"*hard["status"]
    end
    r["validation"]=validate_r6_evaluation(c, domain, r; spec)
    r["elapsed_sec"]=time()-start
    r["budget_overrun_sec"]=max(0, time()-deadline)
    r["source_hashes_at_solve"]==r6_evaluation_science_hashes() || error("单日评价期间源码变化")
    r
end

function evaluate_r6_day(
    p::R6Policy,
    trajectory::AbstractMatrix;
    id::AbstractString,
    budget_sec = 60.0,
    kwargs...,
)
    start=time()
    c=r6_evaluation_day(p, trajectory; id)
    r=evaluate_r6_day(
        c,
        p.data["physical"]["temperature_domain"];
        budget_sec,
        deadline = start+budget_sec,
        kwargs...,
    )
    r["policy_sha256"]=p.sha256
    r["trajectory_id"]=String(id)
    r["trajectory_sha256"]=bytes2hex(
        sha256(r5_market_text(Dict("values"=>r5_market_rows(trajectory)))),
    )
    r["elapsed_sec"]=time()-start
    r["budget_overrun_sec"]=max(0, time()-start-budget_sec)
    r
end
