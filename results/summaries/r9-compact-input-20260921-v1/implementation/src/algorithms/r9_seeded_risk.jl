# 只增加求解编排：原build_r5_risk和原独立验证器均不改动。
function r9_seeded_extract!(r, c, b)
    x=Dict(k=>value.(v) for (k, v) in b.base.first_stage)
    r["first_stage"]=x
    r["z"]=b.pattern===nothing ? value.(b.z) : Float64.(b.pattern)
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
                    [value(b.base.variables[id]["$k/$j/$t"]) for t in 1:view.data["T"]] for j in 1:n
                ] for (k, n) in sys.sizes
            ),
        )
    end
    r
end

"""
    solve_r9_seeded_risk(case, witness; optimizer, seed!, oracle_optimizer,
                        pattern=nothing, budget_sec=600, process_start=time(),
                        representation=:original, solver_log=false)

把已核查共同调度作为原有限支持模型的初值，继续优化；约束、目标及A1/A2均不变。
seed!只负责向求解器传值。原型检查、建模及优化用前70%预算，独立运输检查到80%，
原验证与调用方保存共用剩余预算。process_start允许纳入导入和输入读取耗时。
返回实际求解器候选、界、初值逐行审计及独立验证；没有新候选时不回填共同见证。
同一输入下LP方法变化和预算分配另行记录，不把本入口称为独立的加速证明。
representation显式选择原表示或r9_compact_v1；后者只改变量界和费用表达式的装配，原数值验证器不变。
solver_log仅控制求解器日志；旧调用默认仍为原表示及静默输出。
"""
function solve_r9_seeded_risk(
    c::R5RiskCase,
    w;
    optimizer,
    seed!,
    oracle_optimizer,
    pattern = nothing,
    budget_sec = 600.0,
    process_start = time(),
    representation = :original,
    solver_log = false,
)
    isfinite(budget_sec) && budget_sec>0 || error("完整预算必须为有限正数")
    isfinite(process_start) && process_start<=time() || error("进程起始时间错误")
    representation in (:original, :r9_compact_v1) || error("未支持的风险模型表示")
    solver_log isa Bool || error("solver_log必须为布尔值")
    r5_risk_assert_case(c)
    fixed=r5_risk_pattern(c, pattern)
    r=Dict{String,Any}(
        "schema"=>"r5-risk-result-v1",
        "version"=>"r5_finite_support_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r9-seeded-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "objective_type"=>"worst_expected_IES_net_cost_fixed_prices",
        "method"=>"direct",
        "initialization"=>"r9_verified_common_witness",
        "representation"=>string(representation),
        "solver_logging_requested"=>solver_log,
        "has_candidate"=>false,
        "budget_sec"=>Float64(budget_sec),
        "optimization_cutoff_fraction"=>0.7,
        "oracle_cutoff_fraction"=>0.8,
        "source_hashes_at_solve"=>r5_risk_science_hashes(),
        "timings"=>Dict{String,Float64}(),
    )
    fixed===nothing || (r["pattern"]=fixed)
    if representation==:r9_compact_v1
        r["representation_source_hashes"]=Dict(
            "src/formulations/r9_compact_risk.jl"=>bytes2hex(sha256(read(R9_COMPACT_MODEL_FILE))),
            "src/algorithms/r9_compact_risk.jl"=>bytes2hex(sha256(read(R9_COMPACT_SOLVE_FILE))),
        )
    end
    solve_deadline=process_start+0.7budget_sec
    oracle_deadline=process_start+0.8budget_sec
    deadline=process_start+budget_sec
    try
        if time()>=solve_deadline
            r["status"]="budget_exhausted_before_build"
        else
            tick=time()
            b=representation==:original ? build_r5_risk(c; optimizer, pattern = fixed) :
              build_r9_compact_risk(c; optimizer, pattern = fixed)
            r["timings"]["build_sec"]=time()-tick
            r["model_type"], r["model_types"]=b.model_type, b.model_types
            r["representation_statistics"]=Dict(
                "variables"=>num_variables(b.model),
                "constraints_by_type"=>Dict(
                    string(F, " in ", S)=>num_constraints(b.model, F, S) for
                    (F, S) in list_of_constraint_types(b.model)
                ),
                "cost_alias_equalities"=>hasproperty(b, :cost_alias) ? length(b.cost_alias.rows) :
                                         0,
            )
            tick=time()
            start=r9_risk_start_values(c, b, w)
            r["initial_point_audit"]=audit_r9_risk_start(b, start)
            r["timings"]["mapping_and_audit_sec"]=time()-tick
            r["initial_point_audit"]["pass"] || error("共同初值未通过原模型逐行检查")
            tick=time()
            if time()<solve_deadline
                r["native_start"]=seed!(b.model, start; lp = fixed!==nothing)
                r["timings"]["native_start_sec"]=time()-tick
                tick=time()
                optimize_once! = solver_log ? r9_logged_risk_optimize! : r5_risk_optimize!
                merge!(r, optimize_once!(b.model, solve_deadline))
                r["timings"]["optimization_sec"]=time()-tick
            else
                r["status"]="budget_exhausted_before_seed"
            end
            if r["has_candidate"]
                tick=time()
                r9_seeded_extract!(r, c, b)
                r["timings"]["extraction_sec"]=time()-tick
                tick=time()
                policy=r5_risk_policy(c, r)
                r["timings"]["independent_scores_sec"]=time()-tick
                p=[s["probability"] for s in c.data["commitment"]["scenarios"]]
                D=c.data["ambiguity"]["distance"]
                rho=c.data["ambiguity"]["radius"]
                r["oracles"]=Dict{String,Any}()
                for (label, scores) in (
                    ("cost", policy.costs),
                    ("risk", Float64.(round.(Int, r["z"]))),
                    ("actual", Float64.(policy.events)),
                )
                    remaining=oracle_deadline-time()
                    remaining>0 || break
                    r["oracles"][label]=r5_worst_distribution(
                        p,
                        D,
                        scores,
                        rho;
                        optimizer = oracle_optimizer,
                        budget_sec = remaining,
                        quantity = label=="cost" ? :cost : :probability,
                    )
                end
            end
        end
    catch err
        r5_risk_exception!(r, err)
    end
    tick=time()
    if time()<deadline
        try
            r["validation"]=validate_r5_risk(c, r)
        catch err
            r["validation_error"]=sprint(showerror, err)
            r["validation"]=Dict{String,Any}(
                "status"=>"validation_error",
                "model_pass"=>false,
                "risk_pass"=>false,
                "cost_pass"=>false,
                "optimality_pass"=>false,
            )
        end
    else
        r["validation"]=Dict{String,Any}(
            "status"=>"budget_exhausted_before_validation",
            "model_pass"=>false,
            "risk_pass"=>false,
            "cost_pass"=>false,
            "optimality_pass"=>false,
        )
    end
    r["timings"]["validation_sec"]=time()-tick
    r["elapsed_sec"]=time()-process_start
    r["cost_optimization_complete"]=get(r, "status", "")=="solver_optimal" &&
                                    r["validation"]["optimality_pass"] &&
                                    r["elapsed_sec"]<=budget_sec
    r
end
