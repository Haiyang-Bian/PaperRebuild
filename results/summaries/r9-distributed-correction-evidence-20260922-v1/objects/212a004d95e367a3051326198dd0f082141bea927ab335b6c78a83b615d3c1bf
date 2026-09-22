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
    numerical_scale = 1.0,
)
    r5_risk_assert_case(c)
    r5_benders_xcheck(c, x)
    scale=r5_benders_check_scale(numerical_scale)
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
        "numerical_scale"=>scale,
    )
    try
        if time()>=stop
            r["status"]="budget_exhausted_before_solve"
        else
            b=build_r5_benders_subproblem(
                c,
                scenario,
                x;
                branch,
                elastic,
                optimizer,
                numerical_scale = scale,
            )
            r["model_type"], r["model_types"]=b.model_type, b.model_types
            merge!(r, r5_risk_optimize!(b.model, stop))
            if r["has_candidate"]
                r["flat_values"]=Dict(k=>value(v) for (k, v) in b.variables)
                r["solver_raw_values"]=Dict(k=>value(v) for (k, v) in b.solver_variables)
                r["dual_status"]=string(dual_status(b.model))
                if has_duals(b.model)
                    r["solver_raw_duals"]=Dict(k=>dual(v) for (k, v) in b.rows)
                    r["raw_duals"]=Dict(k=>v*scale for (k, v) in r["solver_raw_duals"])
                    r["dual_transform"]="lambda_original = numerical_scale * solver_raw_dual; original solver values retained"
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

function r5_benders_master_result(b, deadline)
    r=Dict{String,Any}(
        "critical"=>b.critical,
        "scope"=>b.scope,
        "cut_source_ids"=>b.cut_source_ids,
        "model_type"=>b.model_type,
        "model_types"=>b.model_types,
    )
    merge!(r, r5_risk_optimize!(b.model, deadline))
    if r["has_candidate"]
        r["first_stage"]=Dict(k=>value.(v) for (k, v) in b.first_stage)
        r["z"]=value.(b.z)
        r["theta"]=value.(b.theta)
        r["embedded_duals"]=Dict(
            k=>Dict("lambda"=>value(v.lambda), "nu"=>value.(v.nu)) for (k, v) in b.duals
        )
        r["critical_values"]=Dict(
            k=>Dict(j=>value(y) for (j, y) in v) for (k, v) in b.critical_variables
        )
    end
    r
end

function r5_benders_evaluate(c, master, source_ids, sources; optimizer, deadline)
    candidate=Dict{String,Any}(
        "first_stage"=>deepcopy(master["first_stage"]),
        "z"=>copy(master["z"]),
        "source_ids"=>deepcopy(source_ids),
        "oracles"=>Dict{String,Any}(),
    )
    policy=r5_risk_policy(c, r5_benders_policy_view(c, candidate, sources))
    p=[s["probability"] for s in c.data["commitment"]["scenarios"]]
    for (label, score) in (
        ("cost", policy.costs),
        ("risk", Float64.(round.(Int, candidate["z"]))),
        ("actual", Float64.(policy.events)),
    )
        remaining=deadline-time()
        remaining>0||break
        candidate["oracles"][label]=r5_worst_distribution(
            p,
            c.data["ambiguity"]["distance"],
            score,
            c.data["ambiguity"]["radius"];
            optimizer,
            budget_sec = remaining,
            quantity = label=="cost" ? :cost : :probability,
        )
    end
    candidate["validation"]=r5_benders_candidate_check(c, candidate, sources)
    candidate
end

"""
    solve_r5_benders(case; optimizer, subproblem_optimizer=optimizer, oracle_optimizer=subproblem_optimizer,
                     spec=R5BendersSpec(), budget_sec=600)

执行固定价格有限支持条件Benders：主问题、全部情景补救、必要的诊断/关键情景、费用与风险运输回查。
输入只有案例和规则，不接受直接参考解；cut/critical为完整策略域，paper_critical单列原5-102受限域。
所有建模、子问题、对手与验算共用截止时间；默认最多200轮。原始目标、界及失败状态逐阶段保留。
最终仅从完整可行策略形成上界；受限域间隙不认证完整风险模型。独立参考求解须由调用者另行执行。
默认spec为R5BendersSpec(cut_arithmetic=:rational_box, diagnostic_scale=1024.0)，显式传入旧Spec保留原行为。
"""
function solve_r5_benders(
    c::R5RiskCase;
    optimizer,
    subproblem_optimizer = optimizer,
    oracle_optimizer = subproblem_optimizer,
    spec = R5BendersSpec(cut_arithmetic = :rational_box, diagnostic_scale = 1024.0),
    budget_sec = 600.0,
)
    r5_risk_assert_case(c)
    isfinite(budget_sec)&&0<budget_sec<=600||error("Benders总预算须大于0且不超过600秒")
    start=time()
    deadline=start+budget_sec
    r=Dict{String,Any}(
        "schema"=>"r5-benders-result-v1",
        "version"=>"r5_benders_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-benders-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "spec"=>r5_benders_spec(spec),
        "budget_sec"=>Float64(budget_sec),
        "objective_type"=>"worst_expected_IES_net_cost_fixed_prices",
        "source_hashes_at_solve"=>r5_benders_science_hashes(),
        "iterations"=>Dict{String,Any}[],
        "subproblems"=>Dict{String,Any}(),
        "cuts"=>Dict{String,Any}(),
        "cut_order"=>String[],
        "status"=>"iteration_limit",
    )
    critical=Int[]
    seen=Set{String}()
    best=Inf
    selected=0
    lower=-Inf
    sc=c.data["commitment"]["scenarios"]
    function add_cut!(src, step)
        cut=r5_benders_cut(c, src; arithmetic = spec.cut_arithmetic)
        key=r5_benders_cut_key(cut)
        key in seen&&return false
        src["elastic"]&&!cut["productive"]&&return false
        push!(seen, key)
        id=src["run_id"]
        r["cuts"][id]=cut
        push!(r["cut_order"], id)
        push!(step["new_cut_ids"], id)
        true
    end
    try
        for iteration in 1:spec.max_iterations
            if time()>=deadline
                r["status"]="budget_exhausted"
                break
            end
            step=Dict{String,Any}(
                "iteration"=>iteration,
                "new_cut_ids"=>String[],
                "critical_after"=>copy(critical),
                "cost_source_ids"=>Dict{String,String}(),
                "diagnostic_source_ids"=>Dict{String,String}(),
            )
            push!(r["iterations"], step)
            tick=time()
            sources=[r["subproblems"][id] for id in r["cut_order"]]
            b=build_r5_benders_master(c; optimizer, spec, subproblems = sources, critical)
            master=r5_benders_master_result(b, deadline)
            step["master"]=master
            master["validation"]=r5_benders_master_check(c, spec, master, b.cuts)
            if !master["has_candidate"]
                r["status"]=master["status"]=="solver_infeasible" ?
                            (
                    b.scope=="full_risk_domain" ? "full_domain_infeasible" :
                    "restricted_domain_infeasible"
                ) : "master_"*master["status"]
                if master["status"]=="solver_infeasible"&&isfinite(best)
                    r["status"]="master_infeasibility_conflicts_with_candidate"
                end
                step["elapsed_sec"]=time()-tick
                break
            elseif !master["validation"]["pass"]
                r["status"]="master_validation_failed"
                step["elapsed_sec"]=time()-tick
                break
            end
            if master["validation"]["bound_valid"]&&b.scope=="full_risk_domain"
                lower=max(lower, master["solver_objective_bound"])
            end
            # 不因最坏概率为零跳过情景；只有子问题明确不可行才执行phase-I。
            untrusted=false
            unresolved=false
            ranking=Tuple{Float64,Int}[]
            for (s, item) in enumerate(sc)
                remaining=deadline-time()
                remaining>0||break
                src=solve_r5_benders_subproblem(
                    c,
                    s,
                    master["first_stage"];
                    branch = round(Int, master["z"][s]),
                    optimizer = subproblem_optimizer,
                    budget_sec = min(600, remaining),
                    deadline,
                )
                id=src["run_id"]
                r["subproblems"][id]=src
                step["cost_source_ids"][item["id"]]=id
                if src["validation"]["kkt_pass"]
                    add_cut!(src, step)
                elseif src["status"]=="solver_infeasible"
                    remaining=deadline-time()
                    remaining>0||break
                    diagnostic=solve_r5_benders_subproblem(
                        c,
                        s,
                        master["first_stage"];
                        branch = round(Int, master["z"][s]),
                        elastic = true,
                        optimizer = subproblem_optimizer,
                        budget_sec = min(600, remaining),
                        deadline,
                        numerical_scale = spec.diagnostic_scale,
                    )
                    did=diagnostic["run_id"]
                    r["subproblems"][did]=diagnostic
                    step["diagnostic_source_ids"][item["id"]]=did
                    if diagnostic["validation"]["kkt_pass"]
                        if spec.feasibility==:cuts
                            added=add_cut!(diagnostic, step)
                            !added&&!r5_benders_cut(
                                c,
                                diagnostic;
                                arithmetic = spec.cut_arithmetic,
                            )["productive"]&&(unresolved=true)
                        elseif s∈critical
                            unresolved=true
                        else
                            push!(ranking, (diagnostic["solver_objective"], s))
                        end
                    else
                        untrusted=true
                    end
                else
                    untrusted=true
                end
            end
            step["unresolved_sources"]=[
                Dict(
                    "source_id"=>id,
                    "status"=>r["subproblems"][id]["status"],
                    "kkt_status"=>r["subproblems"][id]["validation"]["status"],
                ) for id in vcat(
                    collect(values(step["cost_source_ids"])),
                    collect(values(step["diagnostic_source_ids"])),
                ) if
                !r["subproblems"][id]["validation"]["kkt_pass"]&&r["subproblems"][id]["status"]!="solver_infeasible"
            ]
            if length(step["cost_source_ids"])==length(sc)&&all(
                r["subproblems"][id]["validation"]["model_pass"] for
                id in values(step["cost_source_ids"])
            )
                candidate=r5_benders_evaluate(
                    c,
                    master,
                    step["cost_source_ids"],
                    r["subproblems"];
                    optimizer = oracle_optimizer,
                    deadline,
                )
                step["candidate"]=candidate
                if r5_benders_candidate_pass(candidate["validation"])
                    cost=candidate["validation"]["worst_net_cost"]
                    if cost<best
                        best=cost
                        selected=iteration
                    end
                end
            end
            sort!(ranking; by = x->(-x[1], x[2]))
            append!(critical, [p[2] for p in Iterators.take(ranking, spec.critical_count)])
            sort!(critical)
            step["critical_after"]=copy(critical)
            scope=b.scope
            local_lower=scope=="full_risk_domain" ? lower :
                        (
                master["validation"]["bound_valid"] ? master["solver_objective_bound"] : -Inf
            )
            step["gap"]=r5_benders_gap(best, local_lower, spec)
            step["elapsed_sec"]=time()-tick
            if time()>=deadline
                r["status"]="budget_exhausted"
                break
            elseif untrusted
                r["status"]="untrusted_or_unresolved_subproblem"
                r["failure_sources"]=deepcopy(step["unresolved_sources"])
                break
            elseif unresolved
                r["status"]="nonseparating_or_conflicting_diagnostic"
                break
            elseif step["gap"]["stopping_pass"]&&critical==b.critical
                r["status"]=scope=="full_risk_domain" ? "full_domain_gap" : "restricted_domain_gap"
                break
            elseif isempty(step["new_cut_ids"])&&critical==b.critical
                r["status"]="no_new_cuts"
                break
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    selected>0&&(r["selected_iteration"]=selected)
    r["validation"]=validate_r5_benders(c, r)
    r["cost_optimization_complete"]=r["status"]=="full_domain_gap"&&r["validation"]["optimality_pass"]
    r["elapsed_sec"]=time()-start
    r["budget_overrun_sec"]=max(0.0, time()-deadline)
    r["source_hashes_at_return"]=r5_benders_science_hashes()
    r["source_unchanged"]=r["source_hashes_at_solve"]==r["source_hashes_at_return"]
    r
end
