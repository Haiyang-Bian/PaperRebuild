function r8_energy_balance_rows(d, s, values, packed; recovery = false)
    Set(keys(packed))==Set(["H_pipe"]) || error("稳态能流保存字段错误")
    h=d["heat"]
    ps=h["pipes"]
    T=d["periods"]
    W=length(d["probabilities"])
    f=r7_unpack(packed, "H_pipe")
    size(f)==(length(ps), T, W)&&all(isfinite, f) || error("稳态能流形状/有限性错误")
    H=r7_unpack(values, "H")
    shed=recovery ? r7_unpack(values, "H_shed") : zeros(h["nodes"], T, W)
    scale=max(
        1.0,
        maximum(s["pipe_capacity_MW"]),
        maximum(reduce(vcat, h["load_MW"])),
        sum(g["P_max_MW"] for g in d["devices"]; init = 0.0),
    )
    tol=1e-6*(1+scale)
    rows=Dict{String,Any}[]
    rec(id, key, t, w, x) = push!(
        rows,
        Dict(
            "id"=>id,
            "key"=>string(key),
            "t"=>t,
            "scenario"=>w,
            "residual"=>abs(Float64(x)),
            "tolerance"=>tol,
            "unit"=>"MW",
            "pass"=>isfinite(x)&&abs(x)<=tol,
        ),
    )
    # 从原SI输入重算，独立于JuMP能流构建器及其缓存系数。
    losses=zeros(length(ps), T)
    for (a, p) in enumerate(ps), t in 1:T
        if s["loss_rule"]=="reference_UA"
            losses[a, t]=(
                p["UA_S_W_K"]*(h["S_reference_K"]-h["ambient_K"][t])+p["UA_R_W_K"]*(
                    h["R_reference_K"]-h["ambient_K"][t]
                )
            )/1_000_000
        end
        for w in 1:W
            rec(
                "R8-E2-capacity",
                a,
                t,
                w,
                max(0.0, losses[a, t]-f[a, t, w], f[a, t, w]-s["pipe_capacity_MW"][a]),
            )
        end
    end
    for j in 1:h["nodes"], t in 1:T, w in 1:W
        balance=sum(
            H[g, t, w] for
            (g, z) in enumerate(d["devices"]) if z["kind"] in ("CHP", "EB")&&z["heat_node"]==j;
            init = 0.0,
        )-h["load_MW"][j][t]+shed[j, t, w]
        for (a, p) in enumerate(ps)
            p["from"]==j && (balance-=f[a, t, w])
            p["to"]==j && (balance+=f[a, t, w]-losses[a, t])
        end
        rec("R8-E1-balance", j, t, w, balance)
    end
    rows
end

function r8_energy_normal_check(c, s, n)
    n["schema"]=="r8-energy-normal-v1" && n["case_sha256"]==c.normal.sha256 ||
        error("稳态正常计划身份错误")
    shared=Dict{String,Any}(
        "schema"=>"r7-normal-result-v1",
        "version"=>"r7_normal_prescribed_v1",
        "case_sha256"=>c.normal.sha256,
        "objective_kind"=>"expected_normal_cost_USD",
        "thermal_model"=>c.normal.data["thermal_model"],
        "full_preplan_optimality_verified"=>false,
        "status"=>"candidate",
        "values"=>n["values"],
        "chp_values"=>n["chp_values"],
        "solver_objective_USD"=>n["normal_cost_USD"],
    )
    common=validate_r7_normal(c.normal, shared; thermal = false)
    rows=r8_energy_balance_rows(c.normal.data, s, n["values"], n["energy_values"])
    Dict(
        "model_pass"=>common["shared_block_pass"]&&all(r["pass"] for r in rows),
        "shared"=>common,
        "rows"=>rows,
        "normal_cost_USD"=>common["cost_USD"],
        "dynamic_heat_verified"=>false,
    )
end

function r8_energy_event(c, n, eindex)
    data=deepcopy(r7_event_template(c, eindex).data)
    data["preplan_id"]=n["run_id"]
    event=c.specification["events"][eindex]
    at, T=event["event_start"], event["periods"]
    G, W=length(data["devices"]), length(data["probabilities"])
    P, E=r7_unpack(n["values"], "P"), r7_unpack(n["values"], "E_BES")
    expected=Dict(
        "u"=>zeros(G, T),
        "u_before"=>zeros(G),
        "P_before"=>zeros(G, W),
        "E_before"=>zeros(G, W),
    )
    for (g, z) in enumerate(data["devices"])
        if z["kind"]=="CHP"
            u=r7_unpack(n["chp_values"][z["id"]], "u_CHP")
            z["commitment"]=u[at:(at+T-1)]
            z["previous_commitment"]=at==1 ? c.normal.data["devices"][g]["previous_commitment"] :
                                     u[at-1]
            z["previous_P_MW"]=at==1 ? c.normal.data["devices"][g]["previous_P_MW"] :
                               collect(P[g, at-1, :])
            expected["u"][g, :]=z["commitment"]
            expected["u_before"][g]=z["previous_commitment"]
            expected["P_before"][g, :]=z["previous_P_MW"]
        elseif z["kind"]=="BES"
            z["initial_MWh"]=collect(E[g, at, :])
            expected["E_before"][g, :]=z["initial_MWh"]
        end
    end
    (; case = R7RecoveryCase(data, r7_digest(data)), expected)
end

function r8_energy_stage_check(c, s, r; normal_result = nothing)
    evaluation=normal_result!==nothing
    r["evaluation"]===evaluation && r["objective_kind"]==r8_objective_kind(s; evaluation) ||
        error("能流目标身份错误")
    evaluation && r["fixed_normal_sha256"]!=r7_digest(normal_result) && error("固定计划被替换")
    r["status"]=="infeasible_certified" &&
        get(r, "termination_status", "")!="INFEASIBLE" &&
        error("不可行缺少终止证据")
    q=Dict{String,Any}(
        "model_pass"=>false,
        "objective_complete"=>false,
        "normal_pass"=>false,
        "dynamic_heat_verified"=>false,
        "rows"=>Dict{String,Any}[],
        "witness_checks"=>Any[],
    )
    haskey(r, "normal") || return q
    r["status"] in ("candidate", "time_limit_with_solution") || error("能流状态与候选矛盾")
    n=r["normal"]
    nq=r8_energy_normal_check(c, s, n)
    q["normal_check"]=nq
    q["normal_pass"]=nq["model_pass"]
    nq["model_pass"] || return q
    cost=nq["normal_cost_USD"]
    q["normal_cost_USD"]=cost
    rows=q["rows"]
    rec(id, key, x, tol) = push!(
        rows,
        Dict(
            "id"=>id,
            "key"=>key,
            "residual"=>abs(Float64(x)),
            "tolerance"=>Float64(tol),
            "pass"=>isfinite(x)&&abs(x)<=tol,
        ),
    )
    if evaluation
        function same(actual, original, path)
            Set(keys(actual))==Set(keys(original)) || error("固定计划字段变化")
            for key in sort!(collect(keys(actual)))
                a, b=r7_unpack(actual, key), r7_unpack(original, key)
                size(a)==size(b) || error("固定计划形状变化")
                rec("R8-E3-fixed", path*key, maximum(abs.(a .- b); init = 0.0), 1e-6)
            end
        end
        for key in ("values", "energy_values")
            same(n[key], normal_result[key], key*"/")
        end
        Set(keys(n["chp_values"]))==Set(keys(normal_result["chp_values"])) ||
            error("固定CHP集合变化")
        for key in sort!(collect(keys(n["chp_values"])))
            same(n["chp_values"][key], normal_result["chp_values"][key], key*"/")
        end
    end
    if !evaluation && s["mode"]=="economic"
        isempty(r["witnesses"]) && isempty(r["eta_MWh"]) || error("经济目标附加了灾后约束")
        objective=cost
    else
        caps=r8_loss_caps(c)
        eta=r["eta_MWh"]
        length(eta)==length(caps)&&all(isfinite, eta) || error("事件上图值错误")
        ids=[r7_planning_pair_key((event = w["event"], fault = w["fault"])) for w in r["witnesses"]]
        ids==r7_planning_pair_key.(r7_planning_pairs(c)) || error("能流故障覆盖缺失")
        upper=zeros(length(caps))
        for w in r["witnesses"]
            ev=r8_energy_event(c, n, w["event"])
            shared=Dict{String,Any}(
                "schema"=>"r7-recovery-result-v1",
                "version"=>r7_recovery_version(ev.case),
                "case_sha256"=>ev.case.sha256,
                "preplan_id"=>n["run_id"],
                "preplan_optimality_verified"=>false,
                "objective_kind"=>"expected_unserved_energy_MWh",
                "fault"=>w["fault"],
                "status"=>"candidate",
                "values"=>w["values"],
                "solver_objective_MWh"=>w["witness_loss_MWh"],
            )
            common=validate_r7_recovery(
                ev.case,
                shared;
                aggregate_heat = false,
                thermal_network = false,
            )
            erows=r8_energy_balance_rows(
                ev.case.data,
                s,
                w["values"],
                w["energy_values"];
                recovery = true,
            )
            Set(keys(w["boundary_values"]))==Set(keys(ev.expected)) || error("能流恢复边界字段错误")
            for (key, x) in ev.expected
                actual=r7_unpack(w["boundary_values"], key)
                size(actual)==size(x) || error("继承量形状错误")
                rec(
                    "R8-E3-inherit",
                    string(w["event"])*key,
                    maximum(abs.(actual .- x); init = 0.0),
                    1e-6,
                )
            end
            push!(q["witness_checks"], Dict("shared"=>common, "rows"=>erows))
            common["shared_block_pass"]&&all(x["pass"] for x in erows) || return q
            e=w["event"]
            loss=common["loss_MWh"]
            upper[e]=max(upper[e], loss)
            rec("R8-T2-epigraph", string(e), max(0.0, loss-eta[e]), 1e-6)
            !evaluation &&
                s["mode"]=="threshold" &&
                rec("R8-T1-threshold", string(e), max(0.0, loss-s["limits_MWh"][e]), 1e-6)
            if s["recovery_topology"]=="retain_surviving"
                actual=r7_unpack(w["values"], "z")
                expected=[
                    l["base_closed"]*(1-w["fault"][i]) for
                    (i, l) in enumerate(c.normal.data["electric"]["lines"])
                ]
                rec(
                    "R8-T5-topology",
                    string(e),
                    maximum(abs.(actual .- expected); init = 0.0),
                    1e-6,
                )
            end
        end
        for e in eachindex(caps)
            rec("R8-T2-bound", string(e), max(0.0, -eta[e], eta[e]-caps[e]), 1e-6)
        end
        q["event_upper_MWh"]=upper
        q["threshold_pass"]=all(upper .<= s["limits_MWh"] .+ 1e-6)
        objective=evaluation ? sum(eta) :
                  s["mode"]=="penalty" ? cost+s["penalty_USD_MWh"]*sum(eta) : cost
        if evaluation && haskey(r, "objective_lower_bound")
            lower=[
                max(
                    0.0,
                    r["objective_lower_bound"]-sum(
                        upper[j] for j in eachindex(upper) if j!=e;
                        init = 0.0,
                    ),
                ) for e in eachindex(upper)
            ]
            q["event_lower_MWh"]=lower
            q["event_optimality_pass"]=[
                -1e-6<=(upper[e]-lower[e])/max(1, abs(upper[e]))<=1e-4 for e in eachindex(upper)
            ]
        end
    end
    rec(
        "R8-E3-objective",
        r["objective_kind"],
        objective-r["solver_objective"],
        1e-6*max(1, abs(objective)),
    )
    q["objective_value"]=objective
    q["model_pass"]=all(x["pass"] for x in rows)
    if haskey(r, "objective_lower_bound")
        isfinite(r["objective_lower_bound"]) || error("能流目标界非有限")
        gap=(objective-r["objective_lower_bound"])/max(1, abs(objective))
        q["relative_gap"]=gap
        q["objective_complete"]=q["model_pass"]&&-1e-6<=gap<=1e-4
    end
    q
end

"""
    validate_r8_energy_solution(case, spec, result)

从保存原值独立核验稳态热能流、共同设备/电网、事件状态继承、失供积分和费用。
原始浮点值不裁剪；正常成本界与固定正常计划的最坏失供界分别解释。
稳态通过只认证本能流对照，不报告温度、水压或动态输运通过。
"""
function validate_r8_energy_solution(c::R7PlanningCase, s, r)
    r8_energy_check(c, s)
    r["schema"]=="r8-energy-result-v1" &&
    r["version"]==s["version"] &&
    r["case_sha256"]==c.sha256 &&
    r["spec_sha256"]==r7_digest(s) &&
    r["full_thesis_domain_verified"]===false || error("能流结果身份错误")
    primary=r8_energy_stage_check(c, s, r["primary"])
    primary==r["primary"]["validation"] || error("能流主结果摘要改变")
    q=Dict{String,Any}(
        "primary"=>primary,
        "primary_model_pass"=>primary["model_pass"],
        "recovery_verified"=>false,
        "dynamic_heat_verified"=>false,
        "full_thesis_domain_verified"=>false,
    )
    if haskey(r, "evaluation")
        primary["model_pass"] || error("未通过正常计划出现恢复评估")
        ev=r8_energy_stage_check(c, s, r["evaluation"]; normal_result = r["primary"]["normal"])
        ev==r["evaluation"]["validation"] || error("能流风险摘要改变")
        q["evaluation"]=ev
        q["recovery_verified"]=ev["model_pass"]
    end
    q
end
