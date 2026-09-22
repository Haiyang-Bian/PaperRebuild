const R5_BENDERS_VERIFY_FILE=@__FILE__

function r5_benders_record!(rows, id, kind, value, tol)
    v=abs(Float64(value))
    push!(
        rows,
        Dict(
            "id"=>id,
            "kind"=>kind,
            "residual"=>v,
            "tolerance"=>tol,
            "normalized"=>v/tol,
            "pass"=>isfinite(v)&&v<=tol,
        ),
    )
end

function r5_benders_lp_check(sys, x, y, duals, solver_objective)
    rows=Dict{String,Any}[]
    out=Dict{String,Any}(
        "kkt_pass"=>false,
        "primal_pass"=>false,
        "dual_feasible"=>false,
        "rows"=>rows,
        "status"=>"missing_values",
    )
    Set(keys(y))==Set(keys(sys.cost)) || return out
    all(v->v isa Real&&isfinite(v), values(y)) || (out["status"] = "invalid_values"; return out)
    record(id, kind, v, tol) = r5_benders_record!(rows, id, kind, v, tol)
    for id in sort!(collect(keys(sys.rows)))
        row=sys.rows[id]
        rhs=r5_benders_rhs_value(row, x)
        slack=sum(a*y[k] for (k, a) in row.coefficients; init = 0.0)-rhs
        scale=max(
            1.0,
            abs(rhs),
            sum(abs(a)*sys.variable_scales[k] for (k, a) in row.coefficients; init = 0.0),
        )
        violation=row.sense==:eq ? abs(slack) : row.sense==:ge ? max(0.0, -slack) : max(0.0, slack)
        record(id, "primal", violation/scale, 1e-8)
    end
    primal=sum(sys.cost[k]*y[k] for k in keys(sys.cost))
    record("objective", "objective", (primal-solver_objective)/max(1.0, abs(primal)), 1e-6)
    out["primal_pass"]=all(r["pass"] for r in rows)
    out["primal_objective"]=primal
    if Set(keys(duals))!=Set(keys(sys.rows))
        out["status"]="missing_duals"
        return out
    end
    all(v->v isa Real&&isfinite(v), values(duals)) || (out["status"] = "invalid_duals"; return out)
    stationarity=copy(sys.cost)
    dual=0.0
    for id in sort!(collect(keys(sys.rows)))
        row=sys.rows[id]
        λ=duals[id]
        rhs=r5_benders_rhs_value(row, x)
        slack=sum(a*y[k] for (k, a) in row.coefficients; init = 0.0)-rhs
        scale=max(
            1.0,
            abs(rhs),
            sum(abs(a)*sys.variable_scales[k] for (k, a) in row.coefficients; init = 0.0),
        )
        wrong=row.sense==:ge ? max(0.0, -λ) : row.sense==:le ? max(0.0, λ) : 0.0
        record(id, "sign", wrong*scale/sys.money_scale, 1e-6)
        record(id, "complementarity", λ*slack/sys.money_scale, 1e-6)
        for (k, a) in row.coefficients
            stationarity[k]-=λ*a
        end
        dual+=λ*rhs
    end
    for k in sort!(collect(keys(stationarity)))
        record(k, "stationarity", stationarity[k]*sys.variable_scales[k]/sys.money_scale, 1e-6)
    end
    record("primal-dual", "gap", (primal-dual)/max(1.0, abs(primal), abs(dual)), 1e-4)
    out["status"]="evaluated"
    out["dual_objective"]=dual
    out["stationarity_raw"]=stationarity
    out["dual_feasible"]=all(r["pass"] for r in rows if r["kind"] in ("sign", "stationarity"))
    out["kkt_pass"]=all(r["pass"] for r in rows)
    out
end

function r5_benders_dispatch_view(sys, r)
    y=r["flat_values"]
    Dict{String,Any}(
        "case_sha256"=>sys.view.sha256,
        "run_id"=>r["run_id"],
        "solver_objective"=>r["solver_objective"]+r5_dispatch_dual_system(sys.view).constant,
        "values"=>Dict(
            k=>[[y["$k/$i/$t"] for t in 1:sys.view.data["T"]] for i in 1:n] for (k, n) in sys.sizes
        ),
    )
end

"""
    validate_r5_benders_subproblem(case, result)

从输入和保存原值独立重建固定分支LP，检查原始乘子的方向、互补、驻点及原对偶差。
成本子问题另外调用原物理回放器；诊断只认证弹性关系，不冒充实际供能。
KKT门槛1e-6、间隙A2为1e-4；新增归一化矩阵原始残差1e-8不替代物理A1。
不读取JuMP对象、不重新求解；缺失/篡改数值或乘子不产生可信割。
"""
function validate_r5_benders_subproblem(c::R5RiskCase, r)
    r5_risk_assert_case(c)
    get(r, "case_sha256", nothing)==c.sha256 || error("Benders子问题输入哈希不一致")
    out=Dict{String,Any}("kkt_pass"=>false, "model_pass"=>false, "status"=>"missing_candidate")
    haskey(r, "flat_values") || return out
    scale=r5_benders_check_scale(get(r, "numerical_scale", 1.0))
    if haskey(r, "solver_raw_values")
        if Dict(k=>v/scale for (k, v) in r["solver_raw_values"])!=r["flat_values"]
            out["status"]="invalid_value_transform"
            return out
        end
    elseif scale!=1.0
        out["status"]="missing_scaled_values"
        return out
    end
    if haskey(r, "solver_raw_duals")&&!isempty(get(r, "raw_duals", Dict()))
        if Dict(k=>v*scale for (k, v) in r["solver_raw_duals"])!=r["raw_duals"]
            out["status"]="invalid_dual_transform"
            return out
        end
    elseif scale!=1.0&&haskey(r, "raw_duals")
        out["status"]="missing_scaled_duals"
        return out
    end
    sys=r5_benders_system(c, r["scenario"], r["first_stage"], r["branch"]; elastic = r["elastic"])
    xf=r5_benders_flat(r["first_stage"])
    first_rows=r5_commitment_first_rows(R5CommitmentCase(c.data["commitment"]))
    first_pass=all(
        begin
            slack=sum(a*xf[k] for (k, a) in row.coefficients)-row.rhs
            (row.sense==:ge ? -slack : slack)<=1e-6
        end for row in values(first_rows)
    )
    check=r5_benders_lp_check(
        sys,
        xf,
        r["flat_values"],
        get(r, "raw_duals", Dict()),
        get(r, "solver_objective", NaN),
    )
    merge!(out, check)
    out["first_stage_pass"]=first_pass
    if r["elastic"]
        out["model_pass"]=check["primal_pass"]&&first_pass
        out["physical_dispatch_pass"]=false
    elseif check["primal_pass"]
        physical=validate_r5_dispatch(sys.view, r5_benders_dispatch_view(sys, r))
        out["physical"]=physical
        out["model_pass"]=first_pass&&physical["model_pass"]&&physical["cost_pass"]&&physical["auxiliary_exact_pass"]
        out["physical_dispatch_pass"]=out["model_pass"]
    end
    out["kkt_pass"]=check["kkt_pass"]&&out["model_pass"]
    out["raw_multipliers_unchanged"]=true
    out["certificate_scope"]="Numerical fixed-branch LP KKT; elastic solutions are not physical dispatches"
    out
end

# c'y=λ'b(x)+λ'(Ay-b(x))+(c-A'λ)'y；用全盒界扣除数值误差，不裁剪原始乘子。
function r5_benders_minorant(sys, duals)
    Set(keys(duals))==Set(keys(sys.rows)) || error("割乘子清单不完整")
    all(v->v isa Real&&isfinite(v), values(duals)) || error("割乘子非有限")
    residual=copy(sys.cost)
    gradient=Dict(k=>0.0 for k in keys(sys.xb))
    intercept=0.0
    sign_guard=0.0
    arithmetic_scale=sum(abs(sys.cost[k])*max(abs.(sys.box[k])...) for k in keys(sys.cost))
    for id in sort!(collect(keys(sys.rows)))
        row=sys.rows[id]
        λ=duals[id]
        intercept+=λ*row.rhs
        for (k, a) in row.parameters
            gradient[k]+=λ*a
        end
        for (k, a) in row.coefficients
            residual[k]-=λ*a
        end
        lhs=r5_benders_range(row.coefficients, sys.box)
        rhs=r5_benders_range(row.parameters, sys.xb; constant = row.rhs)
        V=max(abs(lhs[1]-rhs[2]), abs(lhs[2]-rhs[1]))
        wrong=row.sense==:ge ? max(0.0, -λ) : row.sense==:le ? max(0.0, λ) : 0.0
        sign_guard+=wrong*V
        arithmetic_scale+=abs(λ)*(max(abs.(lhs)...)+max(abs.(rhs)...))
    end
    stationarity_guard=sum(abs(residual[k])*max(abs.(sys.box[k])...) for k in keys(residual))
    rounding_guard=1e-10*max(1.0, arithmetic_scale)
    guard=stationarity_guard+sign_guard+rounding_guard
    Dict{String,Any}(
        "constant"=>intercept-guard,
        "gradient"=>gradient,
        "raw_constant"=>intercept,
        "guard"=>guard,
        "stationarity_guard"=>stationarity_guard,
        "sign_guard"=>sign_guard,
        "rounding_guard"=>rounding_guard,
        "stationarity_raw"=>residual,
    )
end

"""
    r5_benders_cut(case, subproblem_result; arithmetic=:float_box)

只从通过独立KKT的固定分支LP生成可审计条件割。成本割给补救费用仿射下界，诊断割给最小违反下界。
原始乘子不变；按有限物理盒扣除驻点/微小符号误差界，并另记浮点保护量(R5-BD4)。
停用常数M由日前盒和有效负费用下界推导(R5-BD5)，不任取大常数、不把停用分支限制为费用非负。
诊断割必须在来源点有正下界才有排除作用；调用方须检查productive，不把无力的割当作进展。
rational_box使用精确二进制有理系数计算保护量，转换回Float64时对截距向下、M向上舍入(R5-BD9)。
该证书只覆盖已编码LP，不证明物理常数精确、MILP精确求解或作者原始模型等价。
"""
function r5_benders_cut(c::R5RiskCase, r; arithmetic = :float_box)
    arithmetic in (:float_box, :rational_box)||error("未知割算术模式")
    get(r, "source_unchanged", false) || error("求解期间源码未保持一致，不能生成正式割")
    check=validate_r5_benders_subproblem(c, r)
    check["kkt_pass"] || error("子问题未通过独立KKT，不能生成Benders割")
    sys=r5_benders_system(c, r["scenario"], r["first_stage"], r["branch"]; elastic = r["elastic"])
    cut=arithmetic==:float_box ? r5_benders_minorant(sys, r["raw_duals"]) :
        r5_benders_rational_minorant(sys, r["raw_duals"])
    _, hi=r5_benders_range(cut["gradient"], sys.xb; constant = cut["constant"])
    floor=r["elastic"] ? 0.0 : sys.bounds.lower_cost
    M=max(0.0, hi-floor)
    if arithmetic==:rational_box
        _, hr=r5_benders_exact_range(cut["gradient"], sys.xb; constant = cut["constant"])
        M=r5_benders_outward(max(0, hr-r5_benders_rational(floor)), :up)
    end
    source=cut["constant"]+sum(a*r5_benders_flat(r["first_stage"])[k] for (k, a) in cut["gradient"])
    merge!(
        cut,
        Dict(
            "case_sha256"=>c.sha256,
            "source_run_id"=>r["run_id"],
            "scenario"=>r["scenario"],
            "branch"=>r["branch"],
            "kind"=>r["elastic"] ? "feasibility" : "cost",
            "lower_cost"=>floor,
            "deactivation_M"=>M,
            "arithmetic"=>string(arithmetic),
            "source_value"=>source,
            "productive"=>r["elastic"] ? source>1e-8 : true,
            "units"=>r["elastic"] ? "normalized_violation" :
                     "synthetic_"*r5_dispatch_currency(
                first(c.data["commitment"]["scenarios"])["case"],
            ),
        ),
    )
    cut
end

# Float64的二进制系数可以精确嵌入BigInt有理数。证书只针对已编码的有限盒LP，不认证物理常数本身。
function r5_benders_rational_minorant(sys, duals)
    Set(keys(duals))==Set(keys(sys.rows))||error("割乘子清单不完整")
    all(v->v isa Real&&isfinite(v), values(duals))||error("割乘子非有限")
    R=r5_benders_rational
    residual=Dict(k=>R(v) for (k, v) in sys.cost)
    gradient=Dict(k=>R(0) for k in keys(sys.xb))
    constant=R(0)
    sign_guard=R(0)
    for (id, row) in sys.rows
        λ=R(duals[id])
        constant+=λ*R(row.rhs)
        for (k, a) in row.parameters
            gradient[k]+=λ*R(a)
        end
        for (k, a) in row.coefficients
            residual[k]-=λ*R(a)
        end
        lhs=r5_benders_exact_range(row.coefficients, sys.box)
        rhs=r5_benders_exact_range(row.parameters, sys.xb; constant = row.rhs)
        V=max(abs(lhs[1]-rhs[2]), abs(lhs[2]-rhs[1]))
        wrong=row.sense==:ge ? max(0, -λ) : row.sense==:le ? max(0, λ) : R(0)
        sign_guard+=wrong*V
    end
    stationarity_guard=sum(abs(v)*maximum(abs.(R.(sys.box[k]))) for (k, v) in residual)
    raw_constant=constant
    constant-=stationarity_guard+sign_guard
    float_gradient=Dict(k=>Float64(v) for (k, v) in gradient)
    all(isfinite, values(float_gradient))||error("割梯度溢出")
    coefficient_guard=sum(
        abs(gradient[k]-R(float_gradient[k]))*maximum(abs.(R.(sys.xb[k]))) for k in keys(gradient)
    )
    constant-=coefficient_guard
    fconstant=r5_benders_outward(constant, :down)
    rounding=coefficient_guard+constant-R(fconstant)
    Dict{String,Any}(
        "constant"=>fconstant,
        "gradient"=>float_gradient,
        "raw_constant"=>Float64(raw_constant),
        "guard"=>Float64(stationarity_guard+sign_guard+rounding),
        "stationarity_guard"=>Float64(stationarity_guard),
        "sign_guard"=>Float64(sign_guard),
        "rounding_guard"=>Float64(rounding),
        "stationarity_raw"=>Dict(k=>Float64(v) for (k, v) in residual),
        "exact_raw_constant"=>string(raw_constant),
        "exact_stationarity_guard"=>string(stationarity_guard),
        "exact_sign_guard"=>string(sign_guard),
        "exact_coefficient_guard"=>string(coefficient_guard),
        "exact_gradient"=>Dict(k=>string(v) for (k, v) in gradient),
        "certificate_scope"=>"exact_rational_minorant_of_encoded_bounded_LP_outward_float_coefficients",
    )
end

function r5_benders_master_check(c, spec, r, cuts)
    active=r5_benders_critical(c, spec, r["critical"])
    r["scope"]==r5_benders_scope(c, spec, active)||error("主问题界作用域改变")
    [q["source_run_id"] for q in cuts]==r["cut_source_ids"]||error("主问题割来源改变")
    out=Dict{String,Any}(
        "pass"=>false,
        "bound_valid"=>false,
        "rows"=>Dict{String,Any}[],
        "construction_pass"=>true,
    )
    get(r, "has_candidate", false)||return out
    base=R5CommitmentCase(c.data["commitment"])
    sc=base.data["scenarios"]
    n=length(sc)
    xf=r5_benders_flat(r5_benders_xcheck(c, r["first_stage"]))
    z, θ=r["z"], r["theta"]
    length(z)==length(θ)==n&&all(isfinite, z)&&all(isfinite, θ)||error("主问题值形状错误")
    rec(id, kind, v, tol = 1e-6) = r5_benders_record!(out["rows"], id, kind, v, tol)
    for (id, row) in r5_commitment_first_rows(base)
        slack=r5_benders_dot(row.coefficients, xf)-row.rhs
        rec(id, "first_stage", row.sense==:ge ? max(0.0, -slack) : max(0.0, slack))
    end
    for s in 1:n
        L=r5_benders_bounds(c, s).lower_cost
        rec("floor/$s", "cost_floor", max(0.0, L-θ[s])/max(1, abs(L)))
        rec("z/$s", "binary", max(abs(z[s]-round(z[s])), max(0.0, -z[s], z[s]-1)))
        if spec.feasibility==:paper_critical&&s∉active
            rec("outside/$s", "restricted_comfort", z[s])
        end
    end
    for (i, cut) in enumerate(cuts)
        s=cut["scenario"]
        match=cut["branch"]==0 ? 1-z[s] : z[s]
        lhs=r5_benders_affine(cut, xf)-cut["deactivation_M"]*(1-match)
        lhs-=cut["kind"]=="cost" ? θ[s] : 0.0
        scale=cut["kind"]=="cost" ? max(1, abs(θ[s]), abs(cut["source_value"])) : 1.0
        rec("cut/$i", "conditional_cut", max(0.0, lhs)/scale)
    end
    ids=[sc[s]["id"] for s in active]
    Set(keys(r["critical_values"]))==Set(ids)||error("关键情景值清单错误")
    for s in active
        sys=r5_benders_system(c, s, r["first_stage"], 1)
        y=r["critical_values"][sc[s]["id"]]
        Set(keys(y))==Set(keys(sys.cost))&&all(isfinite, values(y))||error("关键情景变量缺失")
        q=sum(a*y[k] for (k, a) in sys.cost)
        adapter=Dict("flat_values"=>y, "solver_objective"=>q, "run_id"=>"master-critical")
        physical=validate_r5_dispatch(sys.view, r5_benders_dispatch_view(sys, adapter))
        rec("critical/$s", "physical", physical["model_pass"] ? 0.0 : 1.0)
        for (j, b) in enumerate(sc[s]["case"]["buildings"]), t in 1:sys.view.data["T"]
            dom=c.data["temperature_domain"][b["id"]]
            τ=y["τ_IN/$j/$t"]
            rec(
                "comfort/$s/$j/$t",
                "critical_comfort",
                max(
                    0.0,
                    b["T_min_K"]-(b["T_min_K"]-dom["lower_K"])*z[s]-τ,
                    τ-b["T_max_K"]-(dom["upper_K"]-b["T_max_K"])*z[s],
                ),
                1e-4,
            )
        end
    end
    D=r5_market_array(c.data["ambiguity"]["distance"])
    rho=c.data["ambiguity"]["radius"]
    p=[s["probability"] for s in sc]
    objectives=Dict{String,Float64}()
    for (label, score) in (("cost", θ), ("risk", z))
        d=r["embedded_duals"][label]
        λ=d["lambda"]
        ν=d["nu"]
        length(ν)==n&&isfinite(λ)&&all(isfinite, ν)||error("主问题运输乘子错误")
        scale=label=="cost" ? max(1.0, maximum(abs.(score))) : 1.0
        tol=label=="cost" ? 1e-6 : 1e-8
        rec("$label/sign", "transport", max(0.0, -λ)/scale, tol)
        rec(
            "$label/rows",
            "transport",
            max(0.0, maximum(score[i]-λ*D[i, j]-ν[j] for i in 1:n, j in 1:n))/scale,
            tol,
        )
        objectives[label]=rho*λ+sum(p .* ν)
    end
    rec("risk/budget", "risk", max(0.0, objectives["risk"]-c.data["epsilon"]), 1e-8)
    objective=r5_commitment_day_cost(base, r["first_stage"])+objectives["cost"]
    rec("master/objective", "objective", (r["solver_objective"]-objective)/max(1, abs(objective)))
    out["pass"]=all(row["pass"] for row in out["rows"])
    out["objective_recomputed"]=objective
    bound=get(r, "solver_objective_bound", NaN)
    out["bound_valid"]=out["pass"]&&isfinite(bound)&&get(r, "bound_source", "") in (
        "MOI.ObjectiveBound",
        "MOI.DualObjectiveValue",
    )&&bound<=objective+1e-6*max(1, abs(objective))
    out
end

# 仅为复用独立风险验算器构造同一策略的视图；计算的总费用不是一个新的求解器目标记录。
function r5_benders_policy_view(c, candidate, sources)
    x=candidate["first_stage"]
    n=length(c.data["commitment"]["scenarios"])
    out=Dict{String,Any}(
        "case_sha256"=>c.sha256,
        "first_stage"=>x,
        "z"=>candidate["z"],
        "scenarios"=>Dict{String,Any}(),
        "oracles"=>get(candidate, "oracles", Dict()),
    )
    for s in 1:n
        id=c.data["commitment"]["scenarios"][s]["id"]
        src=sources[candidate["source_ids"][id]]
        !src["elastic"]&&src["scenario"]==s&&isequal(src["first_stage"], x)&&src["branch"]==round(
            Int,
            candidate["z"][s],
        )||error("候选并非记录的情景子问题")
        sys=r5_benders_system(c, s, x, 1)
        out["scenarios"][id]=r5_benders_dispatch_view(sys, src)
    end
    if all(
        haskey(out["oracles"], label)&&haskey(out["oracles"][label], "lambda")&&haskey(
            out["oracles"][label],
            "nu",
        ) for label in ("cost", "risk")
    )
        out["embedded_duals"]=Dict(
            label=>Dict(k=>out["oracles"][label][k] for k in ("lambda", "nu")) for
            label in ("cost", "risk")
        )
        dc=out["embedded_duals"]["cost"]
        p=[s["probability"] for s in c.data["commitment"]["scenarios"]]
        out["solver_objective"]=r5_commitment_day_cost(R5CommitmentCase(c.data["commitment"]), x)+c.data["ambiguity"]["radius"]*dc["lambda"]+sum(
            p .* dc["nu"],
        )
    end
    out
end

function r5_benders_candidate_check(c, candidate, sources)
    v=validate_r5_risk(c, r5_benders_policy_view(c, candidate, sources))
    v["objective_source"]="evaluated_policy_and_transport_dual_not_monolithic_solver"
    v
end
r5_benders_candidate_pass(v) =
    v["model_pass"]&&v["risk_pass"]&&v["cost_pass"]&&haskey(v, "worst_net_cost")

"""
    validate_r5_benders(case, result)

只读重验全部情景来源、原始对偶条件割、主问题数值、风险运输及逐轮上下界；不调用求解器。
完整域下界只来自已核查主问题的求解器界；paper_critical扩张关键集时不累计旧受限域界。
候选必须全情景物理与风险通过。最优性A2、分解停止及受限域完成分别报告，不认证策略报价或样本外风险。
"""
function validate_r5_benders(c::R5RiskCase, r)
    r5_risk_assert_case(c)
    get(r, "case_sha256", nothing)==c.sha256||error("Benders输入不一致")
    r["schema"]=="r5-benders-result-v1"&&r["version"]=="r5_benders_checked_v1"||error(
        "Benders结果版本错误",
    )
    spec=r5_benders_spec(r["spec"])
    sources=r["subproblems"]
    sc=c.data["commitment"]["scenarios"]
    out=Dict{String,Any}(
        "model_pass"=>false,
        "risk_pass"=>false,
        "cost_pass"=>false,
        "optimality_pass"=>false,
        "stopping_pass"=>false,
        "restricted_stopping_pass"=>false,
        "evidence_pass"=>true,
        "subproblem_checks"=>Dict{String,Any}(),
        "iteration_checks"=>Dict{String,Any}[],
    )
    for (id, src) in sources
        id==src["run_id"]||error("子问题身份改变")
        src["case_sha256"]==c.sha256&&get(src, "source_unchanged", false) &&
        src["source_hashes_at_solve"]==src["source_hashes_at_return"]==r["source_hashes_at_solve"]||error(
            "子问题科学来源改变",
        )
        v=validate_r5_benders_subproblem(c, src)
        r5_risk_validation_text(v)==r5_risk_validation_text(src["validation"])||error(
            "子问题历史核查改变",
        )
        out["subproblem_checks"][id]=Dict(k=>v[k] for k in ("model_pass", "kkt_pass", "status"))
    end
    length(unique(r["cut_order"]))==length(r["cut_order"])&&Set(r["cut_order"])==Set(
        keys(r["cuts"]),
    )||error("割清单改变")
    cuts=Dict{String,Any}()
    for id in r["cut_order"]
        haskey(sources, id)||error("割缺来源")
        cuts[id]=r5_benders_cut(c, sources[id]; arithmetic = spec.cut_arithmetic)
        r5_market_text(cuts[id])==r5_market_text(r["cuts"][id])||error("条件割系数或界改变")
    end
    accumulated=String[]
    critical=Int[]
    used=Set{String}()
    lower=-Inf
    best=Inf
    selected=0
    restricted=-Inf
    for (i, step) in enumerate(r["iterations"])
        step["iteration"]==i||error("Benders迭代顺序改变")
        if !haskey(step, "master")
            out["evidence_pass"]=false
            continue
        end
        m=step["master"]
        m["critical"]==critical&&m["cut_source_ids"]==accumulated||error("主问题没有使用声明的历史")
        mv=r5_benders_master_check(c, spec, m, [cuts[id] for id in accumulated])
        r5_risk_validation_text(mv)==r5_risk_validation_text(m["validation"])||error(
            "主问题历史核查改变",
        )
        if mv["bound_valid"]
            if m["scope"]=="full_risk_domain"
                lower=max(lower, m["solver_objective_bound"])
            else
                restricted=m["solver_objective_bound"]
            end
        else
            restricted=-Inf
        end
        if get(m, "has_candidate", false)
            out["evidence_pass"] &= mv["pass"]
        end
        for (kind, elastic) in (("cost_source_ids", false), ("diagnostic_source_ids", true)),
            (sid, id) in step[kind]

            s=findfirst(item->item["id"]==sid, sc)
            s===nothing&&error("迭代情景不存在")
            src=sources[id]
            src["scenario"]==s&&src["elastic"]==elastic&&isequal(
                src["first_stage"],
                m["first_stage"],
            )&&src["branch"]==round(Int, m["z"][s])||error("子问题不属于该主问题")
            get(src, "numerical_scale", 1.0)==(elastic ? spec.diagnostic_scale : 1.0)||error(
                "子问题数值表示与规则不同",
            )
            if elastic
                prior=sources[step["cost_source_ids"][sid]]
                prior["status"]=="solver_infeasible"||error("未证明成本子问题不可行即诊断")
            end
            push!(used, id)
        end
        current_ids=Set(
            vcat(
                collect(values(step["cost_source_ids"])),
                collect(values(step["diagnostic_source_ids"])),
            ),
        )
        for id in step["new_cut_ids"]
            id∈current_ids&&id∉accumulated&&haskey(cuts, id)||error("新增割来源无效")
            cuts[id]["productive"]||error("没有排除作用的诊断割不能记作进展")
            spec.feasibility!=:cuts&&cuts[id]["kind"]=="feasibility"&&error(
                "关键路线暗中使用可行性割",
            )
            push!(accumulated, id)
        end
        next=r5_benders_critical(c, spec, step["critical_after"])
        issubset(Set(critical), Set(next))||error("关键情景被移除")
        for s in setdiff(next, critical)
            sid=sc[s]["id"]
            haskey(step["diagnostic_source_ids"], sid)||error("关键情景没有诊断来源")
            out["subproblem_checks"][step["diagnostic_source_ids"][sid]]["kkt_pass"]||error(
                "关键情景诊断不可信",
            )
        end
        cv=Dict{String,Any}()
        if haskey(step, "candidate")
            candidate=step["candidate"]
            isequal(candidate["first_stage"], m["first_stage"])&&isequal(candidate["z"], m["z"])&&candidate["source_ids"]==step["cost_source_ids"]||error(
                "候选并非该轮全情景补救",
            )
            cv=r5_benders_candidate_check(c, candidate, sources)
            r5_risk_validation_text(cv)==r5_risk_validation_text(candidate["validation"])||error(
                "策略运输或历史验收改变",
            )
            if r5_benders_candidate_pass(cv)&&cv["worst_net_cost"]<best
                best=cv["worst_net_cost"]
                selected=i
            end
        end
        scope_lower=m["scope"]=="full_risk_domain" ? lower : restricted
        gap=r5_benders_gap(best, scope_lower, spec)
        haskey(step, "gap")&&r5_market_text(gap)!=r5_market_text(step["gap"])&&error("逐轮间隙改变")
        push!(
            out["iteration_checks"],
            Dict(
                "iteration"=>i,
                "master_pass"=>mv["pass"],
                "bound_valid"=>mv["bound_valid"],
                "scope"=>m["scope"],
                "lower_bound"=>scope_lower,
                "upper_bound"=>best,
                "gap"=>gap,
                "candidate_pass"=>!isempty(cv)&&r5_benders_candidate_pass(cv),
            ),
        )
        critical=next
    end
    accumulated==r["cut_order"]&&used==Set(keys(sources))||error("割或子问题不属于完整迭代轨迹")
    get(r, "selected_iteration", 0)==selected||error("未按最小已认证策略费用选择候选")
    gap=r5_benders_gap(best, lower, spec)
    out["lower_bound"], out["upper_bound"], out["gap"]=lower, best, gap
    if selected>0
        v=r5_benders_candidate_check(c, r["iterations"][selected]["candidate"], sources)
        out["selected_iteration"]=selected
        out["selected_validation"]=v
        for k in ("model_pass", "risk_pass", "cost_pass")
            out[k]=v[k]
        end
        out["optimality_pass"]=out["evidence_pass"]&&r5_benders_candidate_pass(v)&&gap["a2_pass"]
        out["stopping_pass"]=out["optimality_pass"]&&gap["stopping_pass"]
        if !isempty(out["iteration_checks"])
            lastcheck=last(out["iteration_checks"])
            out["restricted_stopping_pass"]=out["evidence_pass"]&&lastcheck["scope"]=="restricted_comfort_domain"&&lastcheck["gap"]["stopping_pass"]
        end
    end
    out["infeasibility_scope"]=r["status"]=="full_domain_infeasible" ?
                               "solver_reported_full_domain" :
                               r["status"]=="restricted_domain_infeasible" ?
                               "solver_reported_restricted_domain" : "not_proved"
    if r["status"] in ("full_domain_gap", "restricted_domain_gap")
        isempty(r["iterations"])&&error("没有迭代却记录间隙停止")
        step=last(r["iterations"])
        m=step["master"]
        expected=r["status"]=="full_domain_gap" ? "full_risk_domain" : "restricted_comfort_domain"
        m["scope"]==expected&&m["critical"]==step["critical_after"]&&out["evidence_pass"] &&
        selected>0&&last(out["iteration_checks"])["gap"]["stopping_pass"]||error(
            "停止标签缺乏同域间隙证据",
        )
    elseif r["status"] in ("full_domain_infeasible", "restricted_domain_infeasible")
        isempty(r["iterations"])&&error("没有主问题却宣称不可行")
        m=last(r["iterations"])["master"]
        expected=r["status"]=="full_domain_infeasible" ? "full_risk_domain" :
                 "restricted_comfort_domain"
        !get(m, "has_candidate", false)&&m["status"]=="solver_infeasible"&&m["scope"]==expected&&selected==0||error(
            "不可行标签与原始求解证据冲突",
        )
    elseif r["status"]=="iteration_limit"
        length(r["iterations"])==spec.max_iterations||error("迭代上限标签没有达到预定次数")
    end
    out
end
