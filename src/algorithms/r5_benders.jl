const R5_BENDERS_SOLVE_FILE=@__FILE__

"""
    solve_r5_benders_subproblem(case, scenario, first_stage; branch=0, elastic=false,
                               optimizer, budget_sec=60, deadline=nothing)

在共享截止时间内构造并求解固定分支LP，保存完整原值、原始对偶及独立检查，不写文件。
deadline仅可缩短budget_sec；全部建模和核查计入耗时。无解、超时、许可或数值错误分别保留。
不自动切换到弹性模型；调用者显式指定elastic，不能把诊断成功当作原问题成功。
"""
function solve_r5_benders_subproblem(
    c::R5RiskCase,
    scenario::Integer,
    x;
    branch = 0,
    elastic = false,
    optimizer,
    budget_sec = 60.0,
    deadline = nothing,
)
    r5_risk_assert_case(c)
    r5_benders_xcheck(c, x)
    branch in (0, 1) || error("舒适分支必须为0或1")
    1<=scenario<=length(c.data["commitment"]["scenarios"]) || error("情景索引越界")
    isfinite(budget_sec)&&0<budget_sec<=600 || error("子问题预算须大于0且不超过600秒")
    deadline===nothing || isfinite(deadline) || error("截止时间必须有限")
    start=time()
    stop=deadline===nothing ? start+budget_sec : min(deadline, start+budget_sec)
    r=Dict{String,Any}(
        "schema"=>"r5-benders-subproblem-v1",
        "version"=>"r5_benders_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-benders-sub-"*string(uuid4()),
        "scenario"=>scenario,
        "first_stage"=>deepcopy(x),
        "branch"=>Int(branch),
        "elastic"=>elastic,
        "objective_type"=>elastic ? "normalized_relation_violation" : "scenario_recourse_net_cost",
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>r5_benders_science_hashes(),
        "has_candidate"=>false,
    )
    try
        if time()>=stop
            r["status"]="budget_exhausted_before_solve"
        else
            b=build_r5_benders_subproblem(c, scenario, x; branch, elastic, optimizer)
            r["model_type"], r["model_types"]=b.model_type, b.model_types
            merge!(r, r5_risk_optimize!(b.model, stop))
            if r["has_candidate"]
                r["flat_values"]=Dict(k=>value(v) for (k, v) in b.variables)
                r["dual_status"]=string(dual_status(b.model))
                if has_duals(b.model)
                    r["raw_duals"]=Dict(k=>dual(v) for (k, v) in b.rows)
                end
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r["validation"]=validate_r5_benders_subproblem(c, r)
    r["source_hashes_at_return"]=r5_benders_science_hashes()
    r["source_unchanged"]=r["source_hashes_at_solve"]==r["source_hashes_at_return"]
    r["elapsed_sec"]=time()-start
    r["budget_overrun_sec"]=max(0.0, time()-stop)
    r
end
