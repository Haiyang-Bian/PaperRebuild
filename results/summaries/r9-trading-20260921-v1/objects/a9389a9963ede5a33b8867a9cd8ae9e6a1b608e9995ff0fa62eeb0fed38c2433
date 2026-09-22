const R5_RISK_VERIFY_FILE=@__FILE__

function r5_risk_record!(out, id, group, residual, tol; unit = "1")
    push!(
        out["rows"],
        Dict{String,Any}(
            "id"=>id,
            "group"=>group,
            "residual"=>abs(Float64(residual)),
            "unit"=>unit,
            "tolerance"=>tol,
            "normalized"=>abs(residual)/tol,
            "pass"=>isfinite(residual)&&abs(residual)<=tol,
        ),
    )
end

"""
    validate_r5_transport(weights, distance, scores, radius, result; quantity=:cost)

独立回算有限支持最坏分布运输原LP及其对偶，不读取JuMP对象、不重新求解。
质量/预算按A1的1e-8；概率对偶与差按1e-8，费用按A1金额尺度及A2相对差。
费用可为负，对偶列和乘子自由；不存在“风险最坏分布同时最坏费用”的假设。
"""
function validate_r5_transport(weights, distance, scores, radius, r; quantity = :cost)
    tr=r5_risk_transport_input(weights, distance, scores, radius)
    p, D, q, rho, n=tr.weights, tr.distance, tr.scores, tr.radius, tr.n
    quantity in (:cost, :probability)||error("运输验收量错误")
    out=Dict{String,Any}("pass"=>false, "rows"=>Dict{String,Any}[], "status"=>"missing_witness")
    haskey(r, "transport")&&haskey(r, "lambda")&&haskey(r, "nu")||return out
    Π=r5_market_array(r["transport"])
    ν=r["nu"]
    λ=r["lambda"]
    size(Π)==(n, n)&&length(ν)==n&&all(isfinite, Π)&&all(isfinite, ν)&&isfinite(λ)||return out
    rec(id, v, tol) = r5_risk_record!(out, id, "transport", v, tol)
    rec("mass", maximum(abs.(vec(sum(Π; dims = 1))-p)), 1e-8)
    rec("nonnegative", max(0.0, -minimum(Π)), 1e-8)
    rec("budget", max(0.0, sum(D .* Π)-rho), 1e-8)
    scale=quantity==:probability ? 1.0 : max(1.0, maximum(abs.(q)))
    rec("dual-sign", max(0.0, -λ)/scale, quantity==:probability ? 1e-8 : 1e-6)
    rec(
        "dual-inequality",
        max(0.0, maximum(q[i]-λ*D[i, j]-ν[j] for i in 1:n, j in 1:n))/scale,
        quantity==:probability ? 1e-8 : 1e-6,
    )
    pv=sum(q[i]*Π[i, j] for i in 1:n, j in 1:n)
    dv=rho*λ+sum(p .* ν)
    rec(
        "primal-dual-gap",
        quantity==:probability ? pv-dv : (pv-dv)/max(1.0, abs(pv), abs(dv)),
        quantity==:probability ? 1e-8 : 1e-4,
    )
    merge!(
        out,
        Dict(
            "primal_value"=>pv,
            "dual_value"=>dv,
            "worst_weights"=>vec(sum(Π; dims = 2)),
            "distance_used"=>sum(D .* Π),
            "status"=>"evaluated",
        ),
    )
    out["pass"]=all(x["pass"] for x in out["rows"])
    out
end

function r5_risk_policy(c, r)
    physical=r5_risk_physical_case(c)
    x=r["first_stage"]
    scenario=Dict{String,Any}()
    costs, linear_costs, events, raw_events=Float64[], Float64[], Int[], Int[]
    excess=Float64[]
    for (i, s) in enumerate(physical.data["scenarios"])
        id=s["id"]
        view=r5_commitment_view(physical, s, x)
        rr=r["scenarios"][id]
        v=validate_r5_dispatch(view, rr)
        haskey(v, "operating_net_cost")||error("风险情景数值缺失")
        real=v["operating_net_cost"]-v["day_ahead_cost"]
        linear=v["device_cost"]+v["real_time_settlement"]+view.data["dt_h"]*view.data["realtime"]["penalty_USD_MWh"]*sum(
            only(rr["values"]["mismatch"]),
        )
        b0=c.data["commitment"]["scenarios"][i]["case"]["buildings"]
        violation=maximum(
            max(0.0, b["T_min_K"]-τ, τ-b["T_max_K"]) for (j, b) in enumerate(b0) for
            τ in rr["values"]["τ_IN"][j]
        )
        push!(costs, real)
        push!(linear_costs, linear)
        push!(excess, violation)
        push!(events, violation>1e-4 ? 1 : 0)
        push!(raw_events, violation>0 ? 1 : 0)
        scenario[id]=Dict{String,Any}(
            "validation"=>v,
            "recourse_cost"=>real,
            "epigraph_recourse_cost"=>linear,
            "comfort_excess_K"=>violation,
        )
    end
    (; physical, scenarios = scenario, costs, linear_costs, events, raw_events, excess)
end

function r5_risk_enumeration_evidence(c, r)
    out=Dict{String,Any}("complete"=>false, "records"=>0)
    get(r, "method", "")=="enumeration"||return out
    branches=get(r, "branches", [])
    n=length(c.data["commitment"]["scenarios"])
    patterns=String[]
    bounds=Float64[]
    certified=true
    for b in branches
        get(b, "method", "")=="direct"||error("枚举分支方法错误")
        pat=r5_risk_pattern(c, get(b, "pattern", nothing))
        pat===nothing&&error("枚举分支缺少模式")
        push!(patterns, join(pat))
        if b["status"]=="solver_infeasible"
            certified &= get(b, "termination", "")=="INFEASIBLE"&&!haskey(b, "first_stage")
        else
            v=validate_r5_risk(c, b)
            certified &= b["status"]=="solver_optimal"&&v["optimality_pass"]
            v["optimality_pass"]&&push!(bounds, b["solver_objective_bound"])
        end
    end
    length(unique(patterns))==length(patterns)||error("枚举重复分支")
    out["records"]=length(branches)
    out["complete"]=certified&&length(patterns)==2^n
    if out["complete"]&&!isempty(bounds)
        out["lower_bound"]=minimum(bounds)
    end
    if haskey(r, "selected_branch_run_id")
        matches=filter(b->b["run_id"]==r["selected_branch_run_id"], branches)
        length(matches)==1||error("枚举所选分支身份错误")
        chosen=only(matches)
        for key in
            ("first_stage", "scenarios", "z", "embedded_duals", "oracles", "solver_objective")
            isequal(r[key], chosen[key])||error("枚举候选并非所存分支：$key")
        end
    end
    out
end

"""
    validate_r5_risk(case, result)

独立重放每情景硬物理关系、共同承诺、舒适开关以及两套运输对偶。
实际净费用按真实交付误差重算；模型误差上图与真实费用分开，零最坏权重不生成条件梯度。
联合事件报告原始越界与超过A1温度带1e-4 K的事件；开关的最坏风险证书另行检查。
最优性仅使用同一直接模型/固定分支的有效界；不认证市场策略、交流、水压或样本外风险。
"""
function validate_r5_risk(c::R5RiskCase, r)
    r5_risk_assert_case(c)
    get(r, "case_sha256", nothing)==c.sha256||error("风险结果输入不符")
    out=Dict{String,Any}(
        "model_pass"=>false,
        "risk_pass"=>false,
        "cost_pass"=>false,
        "optimality_pass"=>false,
        "rows"=>Dict{String,Any}[],
        "scenarios"=>Dict{String,Any}(),
        "status"=>"missing_candidate",
    )
    enum=r5_risk_enumeration_evidence(c, r)
    out["enumeration"]=enum
    all(haskey(r, k) for k in ("first_stage", "scenarios", "z", "embedded_duals"))||return out
    base=c.data["commitment"]
    sc=base["scenarios"]
    n=length(sc)
    T=first(sc)["case"]["T"]
    x=r["first_stage"]
    z=r["z"]
    Set(keys(x))==Set(R5_COMMITMENT_KEYS)&&all(
        length(x[k])==T&&all(isfinite, x[k]) for k in R5_COMMITMENT_KEYS
    )&&length(z)==n&&all(isfinite, z)&&Set(keys(r["scenarios"]))==Set(s["id"] for s in sc) ||
        (out["status"] = "invalid_candidate"; return out)
    rec(id, group, v, tol; unit = "1") = r5_risk_record!(out, id, group, v, tol; unit)
    e=first(sc)["case"]["electric"]
    ep=max(
        1.0,
        e["pcc_max_MW"],
        sum(a["p_max_MW"] for a in first(sc)["case"]["devices"]; init = 0.0),
    )
    for k in R5_COMMITMENT_KEYS, t in 1:T
        lo, hi=base["bounds"][k]["lower"][t], base["bounds"][k]["upper"][t]
        rec("$k/$t", "first_stage", max(0.0, lo-x[k][t], x[k][t]-hi), 1e-6*(1+ep); unit = "MW")
    end
    for t in 1:T
        rec(
            "PCC/$t",
            "first_stage",
            max(
                0.0,
                e["pcc_min_MW"]-x["P_DA_MW"][t]+x["R_up_MW"][t],
                x["P_DA_MW"][t]+x["R_down_MW"][t]-e["pcc_max_MW"],
            ),
            1e-6*(1+ep);
            unit = "MW",
        )
    end
    rec("z-binary", "branch", maximum(max(abs(a-round(a)), max(0.0, -a, a-1)) for a in z), 1e-6)
    pattern=get(r, "pattern", nothing)
    pattern===nothing||rec("fixed-pattern", "branch", maximum(abs.(z-pattern)), 1e-6)
    policy=r5_risk_policy(c, r)
    out["scenarios"]=policy.scenarios
    for (i, s) in enumerate(sc), (j, b) in enumerate(s["case"]["buildings"]), t in 1:T
        τ=r["scenarios"][s["id"]]["values"]["τ_IN"][j][t]
        dom=c.data["temperature_domain"][b["id"]]
        rec(
            "$(s["id"])/$j/$t",
            "comfort_link",
            max(
                0.0,
                b["T_min_K"]-(b["T_min_K"]-dom["lower_K"])*z[i]-τ,
                τ-b["T_max_K"]-(dom["upper_K"]-b["T_max_K"])*z[i],
            ),
            1e-4;
            unit = "K",
        )
    end
    p=[s["probability"] for s in sc]
    D=r5_market_array(c.data["ambiguity"]["distance"])
    rho=c.data["ambiguity"]["radius"]
    embedded=Dict{String,Float64}()
    for (label, score) in (("cost", policy.linear_costs), ("risk", z))
        d=get(r["embedded_duals"], label, Dict())
        haskey(d, "lambda")&&haskey(d, "nu")&&length(d["nu"])==n&&all(isfinite, d["nu"])&&isfinite(
            d["lambda"],
        )||(out["status"] = "invalid_embedded_dual"; return out)
        λ, ν=d["lambda"], d["nu"]
        scale=label=="risk" ? 1.0 : max(1.0, maximum(abs.(score)))
        tol=label=="risk" ? 1e-8 : 1e-6
        rec("$label/dual-sign", "embedded", max(0.0, -λ)/scale, tol)
        rec(
            "$label/dual-rows",
            "embedded",
            max(0.0, maximum(score[i]-λ*D[i, j]-ν[j] for i in 1:n, j in 1:n))/scale,
            tol,
        )
        embedded[label]=rho*λ+sum(p .* ν)
    end
    rec("risk-upper", "risk", max(0.0, embedded["risk"]-c.data["epsilon"]), 1e-8)
    da=r5_commitment_day_cost(policy.physical, x)
    modelobj=da+embedded["cost"]
    rec(
        "model-objective",
        "cost",
        get(r, "solver_objective", NaN)-modelobj,
        1e-6*max(1, abs(modelobj));
        unit = "USD",
    )
    out["model_pass"]=all(v["validation"]["model_pass"] for v in values(policy.scenarios))&&all(
        a["pass"] for a in out["rows"]
    )
    out["day_ahead_cost"], out["model_objective_recomputed"]=da, modelobj
    out["actual_event"], out["raw_event"], out["comfort_excess_K"]=policy.events,
    policy.raw_events,
    policy.excess
    out["nominal_violation_probability"]=sum(p .* policy.events)
    out["nominal_net_cost"]=da+sum(p .* policy.costs)
    out["transport_checks"]=Dict{String,Any}()
    haskey(r, "oracles")||(out["status"] = "missing_oracles"; return out)
    # 在验证原始整数距离后才形成事件掩码；该掩码的概率仍按1e-8复核。
    zm=round.(Int, z)
    for (label, score) in
        (("cost", policy.costs), ("risk", Float64.(zm)), ("actual", Float64.(policy.events)))
        check=validate_r5_transport(
            p,
            D,
            score,
            rho,
            get(r["oracles"], label, Dict());
            quantity = label=="cost" ? :cost : :probability,
        )
        out["transport_checks"][label]=check
    end
    checks=out["transport_checks"]
    all(v["pass"] for v in values(checks))||(out["status"] = "uncertified_transport"; return out)
    rec("selected-risk", "risk", max(0.0, checks["risk"]["dual_value"]-c.data["epsilon"]), 1e-8)
    rec("actual-risk", "risk", max(0.0, checks["actual"]["dual_value"]-c.data["epsilon"]), 1e-8)
    upper=da+checks["cost"]["dual_value"]
    rec(
        "policy-upper",
        "cost",
        max(0.0, upper-modelobj),
        1e-6*max(1, abs(upper), abs(modelobj));
        unit = "USD",
    )
    out["risk_pass"]=out["model_pass"]&&all(x["pass"] for x in out["rows"] if x["group"]=="risk")
    out["cost_pass"]=all(x["pass"] for x in out["rows"] if x["group"]=="cost")
    out["worst_net_cost"]=upper
    out["worst_violation_probability"]=checks["actual"]["dual_value"]
    out["selected_violation_bound"]=checks["risk"]["dual_value"]
    bound=get(r, "solver_objective_bound", NaN)
    if get(r, "method", "")=="enumeration"
        enum["complete"]&&haskey(enum, "lower_bound")&&isequal(bound, enum["lower_bound"])||(
            bound=NaN
        )
    end
    out["valid_bound"]=isfinite(bound)&&bound<=upper+1e-6*max(1, abs(upper))
    out["relative_gap"]=out["valid_bound"] ? max(0.0, upper-bound)/max(1, abs(upper), abs(bound)) :
                        Inf
    out["optimality_pass"]=out["model_pass"]&&out["risk_pass"]&&out["cost_pass"]&&out["valid_bound"]&&out["relative_gap"]<=1e-4
    out["status"]="evaluated"
    out
end
