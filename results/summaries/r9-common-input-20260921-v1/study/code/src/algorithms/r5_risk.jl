const R5_RISK_SOLVE_FILE=@__FILE__

function r5_risk_termination(term, point)
    term==MOI.OPTIMAL ? "solver_optimal" :
    term==MOI.INFEASIBLE ? "solver_infeasible" :
    term==MOI.TIME_LIMIT ? (point ? "time_limit_with_incumbent" : "time_limit_no_incumbent") :
    string(term)
end

function r5_risk_optimize!(m, deadline)
    set_silent(m)
    remaining=deadline-time()
    remaining>0||return Dict{String,Any}(
        "status"=>"budget_exhausted_before_solve",
        "has_candidate"=>false,
    )
    set_time_limit_sec(m, remaining)
    optimize!(m)
    term, prim=termination_status(m), primal_status(m)
    point=prim in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
    out=Dict{String,Any}(
        "termination"=>string(term),
        "primal_status"=>string(prim),
        "raw_status"=>raw_status(m),
        "has_candidate"=>point,
        "solver"=>solver_name(m),
        "status"=>r5_risk_termination(term, point),
    )
    try
        out["solver_version"]=MOI.get(backend(m), MOI.SolverVersion())
    catch err
        out["solver_version_unavailable"]=sprint(showerror, err)
    end
    point&&(out["solver_objective"]=objective_value(m))
    try
        bound=objective_bound(m)
        isfinite(bound)&&(
            out["solver_objective_bound"] = bound;
            out["bound_source"] = "MOI.ObjectiveBound"
        )
    catch err
        out["bound_unavailable"]=sprint(showerror, err)
    end
    if !haskey(out, "solver_objective_bound")&&dual_status(m)==MOI.FEASIBLE_POINT
        try
            bound=dual_objective_value(m)
            isfinite(bound)&&(
                out["solver_objective_bound"] = bound;
                out["bound_source"] = "MOI.DualObjectiveValue"
            )
        catch err
            out["dual_bound_unavailable"]=sprint(showerror, err)
        end
    end
    out
end

function r5_risk_exception!(r, err)
    message=sprint(showerror, err)
    r["status"]=occursin(r"(?i)license|licence|expired|not licensed", message) ?
                "license_unavailable" :
                err isa MOI.UnsupportedConstraint||err isa MOI.UnsupportedAttribute ?
                "unsupported_solver" : "execution_error"
    r["error"]=message
end

"""
    r5_worst_distribution(weights, distance, scores, radius; optimizer, budget_sec=60, quantity=:cost)

在同一预算内分别解有限支持质量运输原LP及独立对偶，保存两份见证、最坏权重和独立残差。
scores为情景费用或联合违约指示；二者须分别调用。费用允许负值，最坏权重允许零。
输入概率质量不自动归一化，距离/半径单位必须一致；不提供连续支持或样本外保证。
"""
function r5_worst_distribution(
    weights,
    distance,
    scores,
    radius;
    optimizer,
    budget_sec = 60.0,
    quantity = :cost,
)
    isfinite(budget_sec)&&budget_sec>0||error("运输预算必须为有限正数")
    tr=r5_risk_transport_input(weights, distance, scores, radius)
    start=time()
    deadline=start+budget_sec
    r=Dict{String,Any}(
        "schema"=>"r5-transport-witness-v1",
        "quantity"=>string(quantity),
        "budget_sec"=>Float64(budget_sec),
    )
    try
        for primal in (true, false)
            if time()>=deadline
                r["status"]="budget_exhausted_before_solve"
                break
            end
            b=r5_transport_build(tr.weights, tr.distance, tr.scores, tr.radius; optimizer, primal)
            status=r5_risk_optimize!(b.model, deadline)
            r[primal ? "primal_solver" : "dual_solver"]=status
            r["status"]=status["status"]
            if status["has_candidate"]
                if primal
                    r["transport"]=[value.(b.Π[i, :]) for i in 1:tr.n]
                else
                    r["lambda"], r["nu"]=value(b.λ), value.(b.ν)
                end
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r["validation"]=validate_r5_transport(weights, distance, scores, radius, r; quantity)
    r["elapsed_sec"]=time()-start
    r
end

function r5_risk_direct(c; optimizer, oracle_optimizer, deadline, budget_sec, pattern)
    r=Dict{String,Any}(
        "schema"=>"r5-risk-result-v1",
        "version"=>"r5_finite_support_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r5-risk-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "objective_type"=>"worst_expected_IES_net_cost_fixed_prices",
        "budget_sec"=>Float64(budget_sec),
        "method"=>"direct",
        "source_hashes_at_solve"=>r5_risk_science_hashes(),
    )
    fixed=r5_risk_pattern(c, pattern)
    fixed===nothing||(r["pattern"]=fixed)
    try
        b=build_r5_risk(c; optimizer, pattern = fixed)
        merge!(r, r5_risk_optimize!(b.model, deadline))
        r["model_type"], r["model_types"]=b.model_type, b.model_types
        if r["has_candidate"]
            x=Dict(k=>value.(v) for (k, v) in b.base.first_stage)
            r["first_stage"]=x
            r["z"]=fixed===nothing ? value.(b.z) : Float64.(fixed)
            r["embedded_duals"]=Dict(
                k=>Dict("lambda"=>value(v.lambda), "nu"=>value.(v.nu)) for (k, v) in b.duals
            )
            r["scenarios"]=Dict{String,Any}()
            for (i, s) in enumerate(b.physical.data["scenarios"])
                id=s["id"]
                view=r5_commitment_view(b.physical, s, x)
                sys=b.base.systems[id]
                r["scenarios"][id]=Dict{String,Any}(
                    "schema"=>"r5-dispatch-result-v1",
                    "version"=>"r5_dispatch_checked_v1",
                    "case_sha256"=>view.sha256,
                    "run_id"=>r["run_id"]*"/"*id,
                    "status"=>"embedded_risk_policy",
                    "solver_objective"=>r5_commitment_day_cost(b.physical, x)+value(b.q[i]),
                    "values"=>Dict(
                        k=>[
                            [value(b.base.variables[id]["$k/$j/$t"]) for t in 1:view.data["T"]] for
                            j in 1:n
                        ] for (k, n) in sys.sizes
                    ),
                )
            end
            policy=r5_risk_policy(c, r)
            p=[s["probability"] for s in c.data["commitment"]["scenarios"]]
            D=c.data["ambiguity"]["distance"]
            rho=c.data["ambiguity"]["radius"]
            r["oracles"]=Dict{String,Any}()
            for (label, score) in (
                ("cost", policy.costs),
                ("risk", Float64.(round.(Int, r["z"]))),
                ("actual", Float64.(policy.events)),
            )
                remaining=deadline-time()
                remaining>0||break
                # 三个独立对手共享截止时间；不能将成本最坏权重套用到风险上。
                r["oracles"][label]=r5_worst_distribution(
                    p,
                    D,
                    score,
                    rho;
                    optimizer = oracle_optimizer,
                    budget_sec = remaining,
                    quantity = label=="cost" ? :cost : :probability,
                )
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r
end

function r5_risk_enumerated(c; optimizer, oracle_optimizer, deadline, budget_sec)
    n=length(c.data["commitment"]["scenarios"])
    n<=8||error("全枚举参照仅用于至多8情景；大系统使用直接MILP或后续分解")
    branches=Dict{String,Any}[]
    best=nothing
    for bits in 0:(2^n-1)
        remaining=deadline-time()
        remaining>0||break
        pattern=[Int((bits>>(i-1))&1) for i in 1:n]
        child=r5_risk_direct(
            c;
            optimizer,
            oracle_optimizer,
            deadline,
            budget_sec = remaining,
            pattern,
        )
        child["validation"]=validate_r5_risk(c, child)
        child["cost_optimization_complete"]=child["status"]=="solver_optimal"&&child["validation"]["optimality_pass"]
        push!(branches, child)
        v=child["validation"]
        if v["model_pass"]&&v["risk_pass"]&&v["cost_pass"]&&haskey(v, "worst_net_cost")
            (best===nothing||v["worst_net_cost"]<best["validation"]["worst_net_cost"])&&(best=child)
        end
    end
    if best===nothing
        r=Dict{String,Any}(
            "schema"=>"r5-risk-result-v1",
            "version"=>"r5_finite_support_checked_v1",
            "case_sha256"=>c.sha256,
            "source_hashes_at_solve"=>r5_risk_science_hashes(),
            "created_utc"=>string(now(UTC)),
            "julia_version"=>string(VERSION),
            "objective_type"=>"worst_expected_IES_net_cost_fixed_prices",
        )
    else
        r=deepcopy(best)
        delete!(r, "pattern")
        pop!(r, "solver_objective_bound", nothing)
        r["selected_branch_run_id"]=best["run_id"]
    end
    complete=length(branches)==2^n&&all(
        b["status"]=="solver_infeasible"||b["cost_optimization_complete"] for b in branches
    )
    r["method"], r["run_id"], r["budget_sec"], r["branches"]="enumeration",
    "r5-risk-enum-"*string(uuid4()),
    Float64(budget_sec),
    branches
    r["status"]=complete ? (best===nothing ? "solver_infeasible" : "enumeration_complete") :
                "enumeration_incomplete"
    if complete&&best!==nothing
        r["solver_objective_bound"]=minimum(
            b["solver_objective_bound"] for b in branches if b["status"]!="solver_infeasible"
        )
        r["bound_source"]="minimum_certified_branch_bounds"
    end
    r
end

"""
    solve_r5_risk(case; optimizer, oracle_optimizer=optimizer, method=:direct, pattern=nothing, budget_sec=60)

求解固定价格有限支持风险调度及三个独立运输证书；全部建模、求解和对手共用墙钟预算。
direct是MILP，给定pattern时为LP；enumeration穷举所有舒适开关，用于开放Clarabel小例参照。
费用上界来自已核查策略的最坏分布；零概率情景不提取除概率后的条件乘子，不制造梯度。
超时/不可行/缺许可分别保存，未完成对手核查的候选不标记风险认证通过。
"""
function solve_r5_risk(
    c::R5RiskCase;
    optimizer,
    oracle_optimizer = optimizer,
    method = :direct,
    pattern = nothing,
    budget_sec = 60.0,
)
    r5_risk_assert_case(c)
    isfinite(budget_sec)&&budget_sec>0||error("风险预算必须有限正数")
    method in (:direct, :enumeration)||error("风险方法错误")
    method==:enumeration&&pattern!==nothing&&error("全枚举不能同时固定分支")
    start=time()
    deadline=start+budget_sec
    r=method==:direct ?
      r5_risk_direct(c; optimizer, oracle_optimizer, deadline, budget_sec, pattern) :
      r5_risk_enumerated(c; optimizer, oracle_optimizer, deadline, budget_sec)
    r["validation"]=validate_r5_risk(c, r)
    r["cost_optimization_complete"]=r["status"] in ("solver_optimal", "enumeration_complete")&&r["validation"]["optimality_pass"]
    r["elapsed_sec"]=time()-start
    r["source_hashes_at_solve"]==r5_risk_science_hashes()||error("风险求解期间源码变化")
    r
end
