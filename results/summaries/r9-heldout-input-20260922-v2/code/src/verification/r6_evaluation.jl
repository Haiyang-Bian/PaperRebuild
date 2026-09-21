const R6_EVALUATION_VERIFY_FILE=@__FILE__

# 从已有独立物理矩阵追加温度越界行；不读取JuMP约束或建模表达式。
function r6_recourse_system(c, domain, stage, peak_cap)
    stage in (:hard, :physical, :peak, :cost) || error("未知补救阶段")
    stage==:cost ?
    (peak_cap isa Real && isfinite(peak_cap) && peak_cap>=0 || error("越界上限无效")) :
    (peak_cap===nothing || error("该阶段不能使用越界上限"))
    view=stage==:hard ? c : r6_physical_day(c, domain)
    old=r5_dispatch_dual_system(view)
    rows=Dict{String,Any}(
        k=>(;
            coefficients = v.coefficients,
            sense = v.sense,
            rhs = v.rhs,
            parameters = Dict{String,Float64}(),
        ) for (k, v) in old.rows
    )
    cost=stage==:peak ? Dict(k=>0.0 for k in keys(old.cost)) : copy(old.cost)
    scales=copy(old.scales)
    if stage in (:peak, :cost)
        cost["peak"]=stage==:peak ? 1.0 : 0.0
        scales["peak"]=max(
            1.0,
            maximum(
                max(
                    b["T_min_K"]-domain[b["id"]]["lower_K"],
                    domain[b["id"]]["upper_K"]-b["T_max_K"],
                ) for b in c.data["buildings"]
            ),
        )
        row(k, a, s, r) =
            (rows[k]=(; coefficients = a, sense = s, rhs = r, parameters = Dict{String,Float64}()))
        row("peak/lower", Dict("peak"=>1.0), :ge, 0.0)
        for (j, b) in enumerate(c.data["buildings"]), t in 1:c.data["T"]
            row("R6-E1/$j/$t/lower", Dict("τ_IN/$j/$t"=>1.0, "peak"=>1.0), :ge, b["T_min_K"])
            row("R6-E1/$j/$t/upper", Dict("τ_IN/$j/$t"=>1.0, "peak"=>-1.0), :le, b["T_max_K"])
        end
        stage==:cost && row("peak/cap", Dict("peak"=>1.0), :le, peak_cap)
    end
    (;
        rows,
        cost,
        variable_scales = scales,
        money_scale = stage==:peak ? 1.0 : old.money_scale,
        constant = stage==:peak ? 0.0 : old.constant,
        view,
        sizes = old.sizes,
    )
end

function r6_recourse_check(c, domain, r)
    r["case_sha256"]==c.sha256 || error("R6阶段输入不同")
    out=Dict{String,Any}(
        "model_pass"=>false,
        "kkt_pass"=>false,
        "cost_complete"=>false,
        "peak_complete"=>false,
        "has_candidate"=>false,
    )
    haskey(r, "flat_values") || return out
    stage=Symbol(r["stage"])
    cap=get(r, "peak_cap_K", nothing)
    sys=r6_recourse_system(c, domain, stage, cap)
    y=r["flat_values"]
    lp=r5_benders_lp_check(
        sys,
        Dict(),
        y,
        get(r, "raw_duals", Dict()),
        get(r, "solver_objective", NaN)-sys.constant,
    )
    out["lp"]=lp
    lp["primal_pass"] || return out
    values=Dict(k=>[[y["$k/$i/$t"] for t in 1:c.data["T"]] for i in 1:n] for (k, n) in sys.sizes)
    physics=validate_r5_dispatch(
        sys.view,
        Dict(
            "case_sha256"=>sys.view.sha256,
            "values"=>values,
            "solver_objective"=>stage==:peak ? NaN : get(r, "solver_objective", NaN),
        ),
    )
    peak=maximum(
        max(0.0, b["T_min_K"]-values["τ_IN"][j][t], values["τ_IN"][j][t]-b["T_max_K"]) for
        (j, b) in enumerate(c.data["buildings"]), t in 1:c.data["T"]
    )
    out["physics"]=physics
    out["has_candidate"]=true
    out["peak_excess_K"]=peak
    out["model_pass"]=physics["model_pass"]
    out["kkt_pass"]=physics["model_pass"]&&lp["kkt_pass"]
    out["cost_complete"]=stage!=:peak &&
                         out["kkt_pass"] &&
                         physics["cost_pass"] &&
                         physics["auxiliary_exact_pass"] &&
                         r["status"]=="solver_optimal"
    if stage==:peak && out["kkt_pass"]
        out["peak_gap_K"]=abs(lp["primal_objective"]-lp["dual_objective"])
        out["peak_complete"]=r["status"]=="solver_optimal" &&
                             out["peak_gap_K"]<=1e-8 &&
                             abs(y["peak"]-peak)<=1e-8
    end
    out
end

"""
    validate_r6_evaluation(day, temperature_domain, result; spec=R6EvaluationSpec())

独立重建舒适能力诊断每阶段的物理关系、KKT、越界优先级、交付和费用，不求解。
室温联合事件按A1的1e-4 K分类，同时保留原始越界；未完成操作规则标为unknown，不删除样本。
cost_complete仅指共同操作规则下的费用最优，不代表日前策略在真实分布下全局最优。
"""
function validate_r6_evaluation(c::R5DispatchCase, domain, r; spec = R6EvaluationSpec())
    r6_assert_evaluation(spec)
    r["schema"]=="r6-day-result-v1" && r["version"]==spec.data["version"] || error("诊断版本错误")
    r["case_sha256"]==c.sha256 &&
    r["spec_sha256"]==spec.sha256 &&
    r["temperature_domain_sha256"]==bytes2hex(sha256(r5_market_text(domain))) ||
        error("评价身份不符")
    all(k in ("hard", "peak", "cost") && s["stage"]==k for (k, s) in r["stages"]) ||
        error("诊断阶段名称或语义被修改")
    checked=Dict(k=>r6_recourse_check(c, domain, s) for (k, s) in r["stages"])
    out=Dict{String,Any}(
        "stages"=>checked,
        "model_pass"=>false,
        "cost_complete"=>false,
        "policy_complete"=>false,
        "comfort_outcome"=>"unknown",
        "status"=>r["status"],
    )
    chosen=get(r, "selected_stage", "")
    haskey(checked, chosen) || return out
    v=checked[chosen]
    v["model_pass"] || return out
    chain=chosen=="hard" ? true :
          haskey(r["stages"], "hard")&&r["stages"]["hard"]["status"]=="solver_infeasible"
    if chosen=="cost"
        chain &=
            haskey(checked, "peak") &&
            checked["peak"]["peak_complete"] &&
            checked["peak"]["peak_excess_K"]>spec.data["lexicographic_allowance_K"] &&
            r["stages"]["cost"]["peak_cap_K"]==r["stages"]["peak"]["flat_values"]["peak"]+spec.data["lexicographic_allowance_K"]
    end
    out["model_pass"]=chain
    out["policy_complete"]=chain &&
                           (
                               chosen=="hard" ||
                               (chosen=="cost" && checked["peak"]["peak_complete"])
                           ) &&
                           v["cost_complete"]
    out["cost_complete"]=out["policy_complete"]
    out["peak_excess_K"]=v["peak_excess_K"]
    out["comfort_outcome"]=out["policy_complete"] ?
                           (v["peak_excess_K"]<=1e-4 ? "pass" : "violation") : "unknown"
    for key in (
        "operating_net_cost",
        "day_ahead_cost",
        "device_cost",
        "real_time_settlement",
        "delivery_penalty",
        "request_MW",
        "delivered_MW",
        "mismatch_MWh",
        "mismatch_limit_MWh",
    )
        out[key]=v["physics"][key]
    end
    dt=c.data["dt_h"]
    out["called_energy_MWh"]=dt*sum(abs, out["request_MW"])
    out["call_relative_mismatch"]=out["called_energy_MWh"]>0 ?
                                  out["mismatch_MWh"]/out["called_energy_MWh"] : NaN
    out["delivery_budget_pass"]=v["physics"]["delivery_pass"]
    out
end
