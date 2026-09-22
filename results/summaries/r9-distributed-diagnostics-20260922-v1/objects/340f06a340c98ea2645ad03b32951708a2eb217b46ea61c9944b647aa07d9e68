"""
    r4_coordination_surplus(case, independent, central)

对同一冻结输入、同一电网版本的AG0与SWM数值独立验收，再计算资源成本差及主体效用差。
要求采用模型、电网原关系、静态热能流及账本均通过A1；无可实施AG0时返回eligible=false，
不计算虚假收益率。式R4-B3中效用差之和应等于系统节约，内部支付抵消。
费用为合成美元；正效用差表示相对指定分歧点改善，不自动表示公平或已完成议价。
函数不求解、不写文件；成本差是两个候选的差，不能当作求解器最优性间隙。
"""
function r4_coordination_surplus(c::R4Case, independent, central)
    independent["spec"]["operation"]=="independent" || error("首项必须为独立运营")
    central["spec"]["operation"]=="central" || error("第二项必须为集中协调")
    independent["spec"]["electric"]==central["spec"]["electric"] ||
        error("对照必须使用同一电网版本")
    for r in (independent, central)
        r["input_sha256"]==c.sha256 || error("不同输入不能直接解释为协调收益")
    end
    vals=[validate_r4_solution(c, r) for r in (independent, central)]
    checks=("model_pass", "electric_original_pass", "heat_pass", "ledger_pass")
    stages=get(independent, "local_stages", Any[])
    independent_stages_pass=length(stages)==2 &&
                            sort([s["actor"] for s in stages])==[2, 3] &&
                            all(validate_r4_solution(c, s)["model_pass"] for s in stages) &&
                            get(independent, "stage", "")=="network"
    eligible=independent_stages_pass && all(v[k] for v in vals for k in checks)
    out=Dict{String,Any}(
        "eligible"=>eligible,
        "input_sha256"=>c.sha256,
        "scope"=>"static_heat_energy_model_with_original_electric_check",
        "bargaining"=>"not_performed",
        "independent_status"=>independent["status"],
        "central_status"=>central["status"],
        "independent_stages_pass"=>independent_stages_pass,
        "independent_checks"=>Dict(k=>vals[1][k] for k in checks),
        "central_checks"=>Dict(k=>vals[2][k] for k in checks),
    )
    eligible || return out
    li=r4_ledger(c, independent["values"]; p2p_enabled = false)
    lc=r4_ledger(c, central["values"])
    ci=li["operating_cost"]
    cc=lc["operating_cost"]
    gains=[lc["actors"][i]["utility"]-li["actors"][i]["utility"] for i in 1:3]
    out["independent_cost"]=ci
    out["central_cost"]=cc
    out["resource_saving"]=ci-cc
    ci>0 && (out["saving_fraction"]=(ci-cc)/ci)
    out["actors"]=[
        Dict(
            "actor"=>c.data["actors"][i]["id"],
            "disagreement_utility"=>li["actors"][i]["utility"],
            "central_utility"=>lc["actors"][i]["utility"],
            "utility_gain"=>gains[i],
        ) for i in 1:3
    ]
    out["utility_gain_identity"]=sum(gains)-(ci-cc)
    tolerance=1e-6*max(1.0, abs(ci), abs(cc))
    out["accounting_identity_pass"]=abs(out["utility_gain_identity"])<=tolerance
    out["all_actors_not_worse"]=all(g>=-tolerance for g in gains)
    out["both_cost_optimizations_complete"]=all(
        get(r, "cost_optimization_complete", false) for r in (independent, central)
    )
    return out
end
