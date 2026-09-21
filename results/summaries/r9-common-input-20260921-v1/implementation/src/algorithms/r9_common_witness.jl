"""
    solve_r9_common_witness(case; optimizer, budget_sec=600)

在共享预算中求一个零备用/零PV出力的共同硬舒适调度；返回受限求解证据和原值。
求解失败不等于原风险问题不可行。只记录受限界，不生成原百情景问题的最优性认证。
不写文件；输入、冻结、存档和完整进程预算由脚本入口负责。
"""
function solve_r9_common_witness(c::R5RiskCase; optimizer, budget_sec = 600.0)
    isfinite(budget_sec) && budget_sec>0 || error("预算必须有限正数")
    started=time()
    r=Dict{String,Any}(
        "schema"=>"r9-common-witness-v1",
        "version"=>"r9_common_zero_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>"r9-common-"*string(uuid4()),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "budget_sec"=>Float64(budget_sec),
        "has_candidate"=>false,
        "objective_scope"=>"restricted_zero_reserve_zero_PV_single_day",
        "original_risk_optimality_claim"=>false,
    )
    try
        b=build_r9_common_witness(c; optimizer)
        r["common_identity"]=b.common_identity
        r["construction_sec"]=time()-started
        status=r5_risk_optimize!(b.model, started+budget_sec)
        r["restricted_solver"]=status
        r["status"]=status["status"]
        r["has_candidate"]=status["has_candidate"]
        if status["has_candidate"]
            sc=only(b.one.data["scenarios"])
            id=sc["id"]
            sys=b.base.systems[id]
            r["first_stage"]=Dict(k=>value.(v) for (k, v) in b.base.first_stage)
            r["values"]=Dict(
                k=>[
                    [value(b.base.variables[id]["$k/$j/$t"]) for t in 1:sc["case"]["T"]] for
                    j in 1:n
                ] for (k, n) in sys.sizes
            )
            r["restricted_case_sha256"]=b.one.sha256
            r["model_types"]=b.base.model_types
            # 保留添加的零控制等式实际残差；不裁剪求解器输出。
            r["restriction_residual_MW"]=maximum(
                abs(value(constraint_object(ref).func)) for ref in values(b.extra)
            )
        end
    catch err
        r5_risk_exception!(r, err)
    end
    r["elapsed_sec"]=time()-started
    r
end

"""
    r9_constant_transport(weights, distance, scores, radius; quantity=:cost)

为全部情景分数严格相同的运输问题构造解析原对偶见证：Π为经验概率对角阵，λ=0、ν=q。
只有恒定费用/事件时适用；输入与原对偶残差仍经独立validate_r5_transport验证。
项目式R9-CW2，不拟合或更改运输半径，不用一个费用对手替代非恒定风险对手。
"""
function r9_constant_transport(weights, distance, scores, radius; quantity = :cost)
    tr=r5_risk_transport_input(weights, distance, scores, radius)
    all(==(first(tr.scores)), tr.scores) || error("解析见证只适用恒定情景分数")
    r=Dict{String,Any}(
        "schema"=>"r5-transport-witness-v1",
        "status"=>"analytic_constant_score",
        "quantity"=>string(quantity),
        "transport"=>[[i==j ? tr.weights[j] : 0.0 for j in 1:tr.n] for i in 1:tr.n],
        "lambda"=>0.0,
        "nu"=>copy(tr.scores),
    )
    r["validation"]=validate_r5_transport(weights, distance, scores, radius, r; quantity)
    r["validation"]["pass"] || error("恒定分数运输证书未通过")
    r
end

"""
    r9_common_risk_candidate(case, witness)

将同一零备用/零PV调度复制至给定原风险案例的所有情景；不重新求解、不改输入、不裁剪控制。
原验证器仍逐情景检查设备、网络、热历史、建筑末温、交付、成本和风险。
只生成可行候选及解析运输见证；受限求解界不传入原风险模型。
"""
function r9_common_risk_candidate(c::R5RiskCase, w)
    r5_risk_assert_case(c)
    get(w, "schema", "")=="r9-common-witness-v1" && get(w, "has_candidate", false) ||
        error("缺少共同候选")
    r9_common_identity(c)==w["common_identity"] || error("共同候选的物理、历史、费用或承诺边界不符")
    zero_controls=vcat(w["first_stage"]["R_up_MW"], w["first_stage"]["R_down_MW"])
    for (j, a) in enumerate(first(c.data["commitment"]["scenarios"])["case"]["devices"])
        a["kind"]=="PV" && append!(zero_controls, w["values"]["P_DER"][j])
    end
    all(isfinite, zero_controls) && maximum(abs, zero_controls)<=1e-8 ||
        error("共同候选未满足零备用/零PV限制")
    physical=r5_risk_physical_case(c)
    sc=physical.data["scenarios"]
    x=deepcopy(w["first_stage"])
    n=length(sc)
    r=Dict{String,Any}(
        "schema"=>"r5-risk-result-v1",
        "version"=>"r5_finite_support_checked_v1",
        "case_sha256"=>c.sha256,
        "run_id"=>w["run_id"]*"/"*c.sha256[1:12],
        "method"=>"common_feasible_witness",
        "status"=>"common_candidate_not_risk_optimum",
        "first_stage"=>x,
        "z"=>zeros(n),
        "scenarios"=>Dict{String,Any}(),
        "objective_type"=>"worst_expected_IES_net_cost_fixed_prices",
        "original_risk_optimality_claim"=>false,
        "objective_source"=>"restricted_solver_same_objective_with_identical_recourse",
    )
    for s in sc
        view=r5_commitment_view(physical, s, x)
        r["scenarios"][s["id"]]=Dict{String,Any}(
            "schema"=>"r5-dispatch-result-v1",
            "version"=>"r5_dispatch_checked_v1",
            "case_sha256"=>view.sha256,
            "run_id"=>r["run_id"]*"/"*s["id"],
            "status"=>"common_control_replay",
            "values"=>deepcopy(w["values"]),
            "solver_objective"=>w["restricted_solver"]["solver_objective"],
        )
    end
    policy=r5_risk_policy(c, r)
    # 不将温度修正或费用取整为恒定值；所有情景必须实际给出相同原数值。
    all(==(first(policy.linear_costs)), policy.linear_costs) || error("共同控制费用不恒定")
    p=[s["probability"] for s in sc]
    D=c.data["ambiguity"]["distance"]
    rho=c.data["ambiguity"]["radius"]
    r["embedded_duals"]=Dict(
        "cost"=>Dict("lambda"=>0.0, "nu"=>copy(policy.linear_costs)),
        "risk"=>Dict("lambda"=>0.0, "nu"=>zeros(n)),
    )
    r["solver_objective"]=w["restricted_solver"]["solver_objective"]
    r["oracles"]=Dict(
        label=>r9_constant_transport(
            p,
            D,
            score,
            rho;
            quantity = label=="cost" ? :cost : :probability,
        ) for (label, score) in
        (("cost", policy.costs), ("risk", zeros(n)), ("actual", Float64.(policy.events)))
    )
    r["cost_optimization_complete"]=false
    r
end
