function r8_normal_differences(actual, expected)
    rows=Dict{String,Any}[]
    function compare(a, b, label)
        Set(keys(a))==Set(keys(b)) || error("固定计划字段缺失")
        for key in sort!(collect(keys(a)))
            x, y=r7_unpack(a, key), r7_unpack(b, key)
            size(x)==size(y) || error("固定计划形状变化")
            res=maximum(abs.(x .- y); init = 0.0)
            # 元素原值不裁剪；此等式只允许既有A1量级的求解浮点尾差。
            push!(
                rows,
                Dict(
                    "id"=>"R8-T4-fix",
                    "key"=>label*key,
                    "residual"=>res,
                    "tolerance"=>1e-6,
                    "pass"=>isfinite(res)&&res<=1e-6,
                ),
            )
        end
    end
    for key in ("values", "flow_values")
        compare(actual[key], expected[key], key*"/")
    end
    Set(keys(actual["chp_values"]))==Set(keys(expected["chp_values"])) || error("CHP计划缺失")
    for id in sort!(collect(keys(actual["chp_values"])))
        compare(actual["chp_values"][id], expected["chp_values"][id], id*"/")
    end
    rows
end

function r8_validate_stage(c, flow, s, r; normal_result = nothing)
    r7_check_currency_record(c.normal.data, r)
    evaluation=normal_result!==nothing
    r["evaluation"]===evaluation && r["objective_kind"]==r8_objective_kind(s; evaluation) ||
        error("R8阶段目标/单位错误")
    evaluation && r["fixed_normal_sha256"]!=r7_digest(normal_result) && error("固定计划来源改变")
    r["status"]=="infeasible_certified" &&
        get(r, "termination_status", "")!="INFEASIBLE" &&
        error("不可行缺终止证据")
    q=Dict{String,Any}(
        "model_pass"=>false,
        "objective_complete"=>false,
        "threshold_pass"=>false,
        "normal_pass"=>false,
        "rows"=>Dict{String,Any}[],
        "witness_checks"=>Any[],
    )
    r7_currency_record!(q, c.normal.data)
    haskey(r, "normal") || return q
    r["status"] in ("candidate", "time_limit_with_solution") || error("R8状态与原值矛盾")
    n=r["normal"]
    nq=validate_r7_normal_flow(c.normal, flow["normal_flow"], n)
    q["normal_check"]=nq
    q["normal_pass"]=nq["model_pass"]
    q["normal_pass"] || return q
    rows=q["rows"]
    rec(id, key, res, tol) = push!(
        rows,
        Dict(
            "id"=>id,
            "key"=>key,
            "residual"=>Float64(res),
            "tolerance"=>Float64(tol),
            "pass"=>isfinite(res)&&res<=tol,
        ),
    )
    evaluation && append!(rows, r8_normal_differences(n, normal_result))
    if s["heat_preparation"]=="no_net_charge"
        for side in ("S", "R")
            E=r7_unpack(n["values"], "E_pipe_$side")
            rec(
                "R8-T5-no-net-charge",
                side,
                maximum(max.(0.0, E .- E[:, 1:1, :]); init = 0.0),
                1e-6,
            )
        end
    end
    cost=nq[r7_money_key(c.normal.data, "cost_USD")]
    q[r7_money_key(c.normal.data, "normal_cost_USD")]=cost
    if !evaluation && s["mode"]=="economic"
        isempty(r["witnesses"]) && isempty(r["eta_MWh"]) || error("经济基线不得附加恢复约束")
        objective=cost
    else
        rc, f=r8_carrier(c, flow)
        ids=[r7_planning_pair_key((event = w["event"], fault = w["fault"])) for w in r["witnesses"]]
        ids==r7_planning_pair_key.(r7_planning_pairs(rc)) || error("R8故障见证覆盖不完整")
        checks=[r7_joint_witness_check(rc, f, n, w) for w in r["witnesses"]]
        q["witness_checks"]=checks
        all(w["model_pass"] for w in checks) || return q
        caps=r8_loss_caps(c)
        eta=r["eta_MWh"]
        length(eta)==length(caps) && all(isfinite, eta) || error("R8事件上图变量缺失")
        upper=zeros(length(caps))
        electric=zeros(length(caps))
        heat=zeros(length(caps))
        for (w, chk) in zip(r["witnesses"], checks)
            e=w["event"]
            loss=chk["loss_MWh"]
            if loss>=upper[e]
                upper[e]=loss
                electric[e]=chk["shared"]["loss_electric_MWh"]
                heat[e]=chk["shared"]["loss_heat_MWh"]
            end
            rec("R8-T2-epigraph", string(e), max(0.0, loss-eta[e]), 1e-6)
            if !evaluation && s["mode"]=="threshold"
                rec("R8-T1-threshold", string(e), max(0.0, loss-s["limits_MWh"][e]), 1e-6)
            end
            if s["recovery_topology"]=="retain_surviving"
                z=r7_unpack(w["values"], "z")
                expected=[
                    line["base_closed"]*(1-w["fault"][l]) for
                    (l, line) in enumerate(c.normal.data["electric"]["lines"])
                ]
                rec(
                    "R8-T5-topology",
                    r7_planning_pair_key((event = e, fault = w["fault"])),
                    maximum(abs.(z .- expected); init = 0.0),
                    1e-6,
                )
            end
        end
        for e in eachindex(caps)
            rec("R8-T2-bound", string(e), max(0.0, -eta[e], eta[e]-caps[e]), 1e-6)
        end
        q["event_upper_MWh"], q["event_electric_at_worst_MWh"], q["event_heat_at_worst_MWh"]=upper,
        electric,
        heat
        q["threshold_pass"]=all(upper .<= s["limits_MWh"] .+ 1e-6)
        objective=evaluation ? sum(eta) :
                  s["mode"]=="penalty" ?
                  cost+s[r7_money_key(c.normal.data, "penalty_USD_MWh")]*sum(eta) : cost
        if evaluation && haskey(r, "objective_lower_bound")
            # 各事件恢复块在固定正常计划后独立。总下界减其余事件可行上界给逐事件下界。
            lb=r["objective_lower_bound"]
            lower=[
                max(0.0, lb-sum(upper[j] for j in eachindex(upper) if j!=e; init = 0.0)) for
                e in eachindex(upper)
            ]
            q["event_lower_MWh"]=lower
            q["event_optimality_pass"]=[
                -1e-6<=(upper[e]-lower[e])/max(1, abs(upper[e]))<=1e-4 for e in eachindex(upper)
            ]
            q["threshold_rejected"]=any(lower .> s["limits_MWh"] .+ 1e-6)
        end
    end
    rec(
        "R8-T3-objective",
        r["objective_kind"],
        abs(objective-r["solver_objective"]),
        1e-6*max(1, abs(objective)),
    )
    q["objective_value"]=objective
    q["model_pass"]=all(x["pass"] for x in rows)
    if haskey(r, "objective_lower_bound")
        isfinite(r["objective_lower_bound"]) || error("R8非有限目标界")
        gap=(objective-r["objective_lower_bound"])/max(1, abs(objective))
        q["relative_gap"]=gap
        q["objective_complete"]=q["model_pass"]&&-1e-6<=gap<=1e-4
    end
    q
end

"""
    validate_r8_solution(case, flow, spec, result)

从保存的正常/恢复原值重算成本、输运、继承、逐事件电热失供、epigraph与目标。
经济基线正常可行不代表可恢复；恢复评估的MWh界只适用于固定原计划，
有限故障见证给上界，只有有效下界同时闭合才称最小最坏失供已认证。
"""
function validate_r8_solution(c::R7PlanningCase, flow, s, r)
    r8_check(c, flow, s)
    r7_check_currency_record(c.normal.data, r)
    r["schema"]==r7_money_schema(c.normal.data, "r8-tradeoff-result-v1") &&
    r["version"]==s["version"] &&
    r["case_sha256"]==c.sha256 &&
    r["flow_sha256"]==r7_digest(flow) &&
    r["spec_sha256"]==r7_digest(s) &&
    r["full_thesis_domain_verified"]===false || error("R8结果身份错误")
    p=r8_validate_stage(c, flow, s, r["primary"])
    isequal(p, r["primary"]["validation"]) || error("R8主阶段摘要与原值不符")
    q=Dict{String,Any}(
        "primary"=>p,
        "normal_plan_pass"=>p["normal_pass"],
        "primary_model_pass"=>p["model_pass"],
        "planning_objective_complete"=>p["objective_complete"],
        "recovery_verified"=>false,
        "threshold_pass"=>false,
        "full_thesis_domain_verified"=>false,
    )
    r7_currency_record!(q, c.normal.data)
    if haskey(r, "evaluation")
        p["model_pass"] || error("未通过的主阶段不能有恢复评估")
        e=r8_validate_stage(c, flow, s, r["evaluation"]; normal_result = r["primary"]["normal"])
        isequal(e, r["evaluation"]["validation"]) || error("R8恢复摘要与原值不符")
        q["evaluation"]=e
        q["recovery_verified"]=e["model_pass"]
        q["threshold_pass"]=e["model_pass"]&&e["threshold_pass"]
        q["recovery_objective_complete"]=e["objective_complete"]
    end
    q
end
