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
    r5_benders_cut(case, subproblem_result)

只从通过独立KKT的固定分支LP生成可审计条件割。成本割给补救费用仿射下界，诊断割给最小违反下界。
原始乘子不变；按有限物理盒扣除驻点/微小符号误差界，并另记浮点保护量(R5-BD4)。
停用常数M由日前盒和有效负费用下界推导(R5-BD5)，不任取大常数、不把停用分支限制为费用非负。
诊断割必须在来源点有正下界才有排除作用；调用方须检查productive，不把无力的割当作进展。
"""
function r5_benders_cut(c::R5RiskCase, r)
    get(r, "source_unchanged", false) || error("求解期间源码未保持一致，不能生成正式割")
    check=validate_r5_benders_subproblem(c, r)
    check["kkt_pass"] || error("子问题未通过独立KKT，不能生成Benders割")
    sys=r5_benders_system(c, r["scenario"], r["first_stage"], r["branch"]; elastic = r["elastic"])
    cut=r5_benders_minorant(sys, r["raw_duals"])
    _, hi=r5_benders_range(cut["gradient"], sys.xb; constant = cut["constant"])
    floor=r["elastic"] ? 0.0 : sys.bounds.lower_cost
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
            "deactivation_M"=>max(0.0, hi-floor),
            "source_value"=>source,
            "productive"=>r["elastic"] ? source>1e-8 : true,
            "units"=>r["elastic"] ? "normalized_violation" : "synthetic_USD",
        ),
    )
    cut
end
