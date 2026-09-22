# 数值验证适配器：保留原求解浮点数，不做裁剪或重优化。输入已由父正常验证器核验。
function r7_joint_event_values(c, n, event)
    d=c.normal.data
    e=c.specification["events"][event]
    at, T=e["event_start"], e["periods"]
    win=at:(at+T-1)
    out=deepcopy(r7_event_template(c, event).data)
    nv=Dict(k=>r7_unpack(n["values"], k) for k in keys(n["values"]))
    nf=Dict(k=>r7_unpack(n["flow_values"], k) for k in ("pipe", "source", "load"))
    out["preplan_id"]=n["run_id"]
    out["heat"]["reference_flow_kg_s"]=[sum(nf["source"][:, t]) for t in win]
    profiles=Dict{String,Any}[]
    for (g, dev) in enumerate(out["devices"])
        if dev["kind"]=="CHP"
            u=r7_unpack(n["chp_values"][dev["id"]], "u_CHP")
            dev["commitment"]=collect(u[win])
            dev["previous_commitment"]=at==1 ? d["devices"][g]["previous_commitment"] : u[at-1]
            dev["previous_P_MW"]=at==1 ? deepcopy(d["devices"][g]["previous_P_MW"]) :
                                 collect(nv["P"][g, at-1, :])
        elseif dev["kind"]=="BES"
            dev["initial_MWh"]=collect(nv["E_BES"][g, at, :])
        end
    end
    h=d["heat"]
    for (a, p) in enumerate(h["pipes"])
        out["heat"]["pipes"][a]["normal_flow_kg_s"]=collect(nf["pipe"][a, win])
        for side in ("S", "R"), w in eachindex(d["probabilities"])
            state=r7_normal_initial(d, p, side, w)
            node=p[side=="S" ? "from" : "to"]
            for t in 1:(at-1)
                state=r7_pipe_step(
                    state;
                    mass_flow_kg_s = nf["pipe"][a, t],
                    inlet_K = nv["τ_$side"][node, t, w],
                    ambient_K = h["ambient_K"][t],
                    dt_h = d["dt_h"],
                    cp_J_kgK = h["c_J_kgK"],
                    UA_W_K = p["UA_$(side)_W_K"],
                    reference_K = h["$(side)_min_K"],
                ).state
            end
            inv=r7_pipe_inventory(state; cp_J_kgK = h["c_J_kgK"], reference_K = h["$(side)_min_K"])
            out["heat"]["pipes"][a]["initial_$(side)_K"][w]=inv.mean_K
            push!(
                profiles,
                Dict(
                    "pipe"=>a,
                    "side"=>side,
                    "scenario"=>w,
                    "segments"=>[
                        Dict(
                            "mass_kg"=>z.mass_kg,
                            "base_K"=>z.base_K,
                            "amplitude_K"=>z.amplitude_K,
                            "rate_per_kg"=>z.rate_per_kg,
                            "from_left"=>z.from_left,
                        ) for z in state.segments
                    ],
                ),
            )
        end
    end
    (; case = R7RecoveryCase(out, r7_digest(out)), profiles, nv, nf)
end

function r7_joint_witness_check(c, s, n, w)
    pair=(event = w["event"], fault = w["fault"])
    w["objective_kind"]=="recovery_feasibility_witness" && !haskey(w, "lower_bound_MWh") ||
        error("联合恢复见证不能冒称失供优化界")
    ev=r7_joint_event_values(c, n, pair.event)
    shared=Dict{String,Any}(
        "schema"=>"r7-recovery-result-v1",
        "version"=>r7_recovery_version(ev.case),
        "case_sha256"=>ev.case.sha256,
        "fault"=>pair.fault,
        "preplan_id"=>n["run_id"],
        "preplan_optimality_verified"=>false,
        "objective_kind"=>"expected_unserved_energy_MWh",
        "status"=>"candidate",
        "values"=>w["values"],
        "solver_objective_MWh"=>w["witness_loss_MWh"],
    )
    a=validate_r7_recovery(ev.case, shared; aggregate_heat = false)
    v=Dict(k=>r7_unpack(w["values"], k) for k in ("m_pipe", "m_source", "m_load", "H", "H_shed"))
    bounds=r7_joint_bounds(s, pair)
    rows=Dict{String,Any}[]
    function rec(id, key, I, res, tol, unit)
        push!(
            rows,
            Dict(
                "id"=>id,
                "key"=>key,
                "index"=>collect(Tuple(I)),
                "residual"=>Float64(abs(res)),
                "tolerance"=>Float64(tol),
                "unit"=>unit,
                "pass"=>isfinite(res)&&abs(res)<=tol,
            ),
        )
    end
    for kind in ("pipe", "source", "load"), I in CartesianIndices(v["m_"*kind])
        lo, hi=bounds[kind*"_min"][I], bounds[kind*"_max"][I]
        rec(
            "R7-J1-bound",
            kind,
            I,
            max(0, lo-v["m_"*kind][I], v["m_"*kind][I]-hi),
            1e-6*max(1, hi),
            "kg/s",
        )
    end
    d=ev.case.data
    at=c.specification["events"][pair.event]["event_start"]
    G, T, W=length(d["devices"]), d["periods"], length(d["probabilities"])
    expected=Dict(
        "u"=>zeros(G, T),
        "u_before"=>zeros(G),
        "P_before"=>zeros(G, W),
        "E_before"=>zeros(G, W),
        "m_normal"=>ev.nf["pipe"][:, at:(at+T-1)],
        "E_S_before"=>[sum(ev.nv["E_pipe_S"][:, at, j]) for j in 1:W],
        "E_R_before"=>[sum(ev.nv["E_pipe_R"][:, at, j]) for j in 1:W],
    )
    for (g, dev) in enumerate(d["devices"])
        if dev["kind"]=="CHP"
            expected["u"][g, :]=dev["commitment"]
            expected["u_before"][g]=dev["previous_commitment"]
            expected["P_before"][g, :]=dev["previous_P_MW"]
        elseif dev["kind"]=="BES"
            expected["E_before"][g, :]=dev["initial_MWh"]
        end
    end
    Set(keys(expected))==Set(keys(w["boundary_values"])) || error("恢复边界数值缺失")
    for (k, x) in expected
        actual=r7_unpack(w["boundary_values"], k)
        size(actual)==size(x) && all(isfinite, actual) || error("恢复边界形状或有限性错误")
        unit=k in ("u", "u_before") ? "1" : k=="m_normal" ? "kg/s" : k=="P_before" ? "MW" : "MWh"
        for I in CartesianIndices(x)
            rec("R7-J2-inherit", k, I, actual[I]-x[I], 1e-6, unit)
        end
    end
    q=Dict{String,Any}(
        "key"=>r7_planning_pair_key(pair),
        "model_pass"=>false,
        "threshold_pass"=>false,
        "shared"=>a,
        "rows"=>rows,
        "initial_profiles_sha256"=>r7_digest(Dict("profiles"=>ev.profiles)),
    )
    # 负流没有被本版本定义；连微小负原值也不偷偷截到0再声称通过。
    if !all(all(>=(0), v[k]) for k in ("m_pipe", "m_source", "m_load"))
        q["replay_blocked"]="negative_raw_flow"
        return q
    end
    spec=Dict(
        "substeps"=>s["substeps"],
        "mode"=>"same_dispatch",
        "profiles"=>ev.profiles,
        "profile_origin"=>"same_normal_mass_history_"*n["run_id"],
        "uniform_assumption"=>false,
    )
    x=r7_thermal_dispatch_context(r7_thermal_context(ev.case, spec, v), v)
    b=r7_validate_thermal_values(
        x,
        spec,
        Dict(
            "status"=>"candidate",
            "values"=>w["thermal_values"],
            "solver_objective_MWh"=>a["loss_heat_MWh"],
        );
        idle_temperature_rule = :free_zero_flow,
    )
    q["thermal"]=b
    q["loss_MWh"]=a["loss_MWh"]
    q["model_pass"]=a["shared_block_pass"]&&b["same_dispatch_pass"]&&all(z["pass"] for z in rows)
    limit=d["loss_limit_MWh"]
    q["threshold_pass"]=q["model_pass"]&&a["loss_MWh"]<=limit+1e-6*(1+max(1, limit))
    q
end

"""
    validate_r7_flow_planning(case, spec, result)

R7-J4从正常原值重新累计水团，再独立核查全部事件/故障的设备、电网、流量、热交付和失供门槛。
不会使用优化交集权重或另选灾前状态；正常费用界与恢复存在性见证分开。仅认证所声明无损正向/
非负、时段平均节点及线性电网模型，不认证水力恢复、交流电网或论文完整控制域。
"""
function validate_r7_flow_planning(c::R7PlanningCase, s, r)
    r7_flow_planning_check(c, s)
    r["schema"]=="r7-flow-planning-result-v1"&&r["version"]==s["version"] &&
    r["case_sha256"]==c.sha256&&r["spec_sha256"]==r7_digest(s) &&
    r["objective_kind"]=="expected_normal_cost_USD"&&r["method"]=="extensive" &&
    r["full_thesis_domain_verified"]===false || error("联合流量结果身份/范围错误")
    r["status"]=="infeasible_certified"&&get(r, "termination_status", "")!="INFEASIBLE" &&
        error("联合规划不可行缺终止证据")
    q=Dict{String,Any}(
        "robust_model_pass"=>false,
        "domain_optimality_pass"=>false,
        "normal_pass"=>false,
        "full_thesis_domain_verified"=>false,
        "continuous_node_dynamics_verified"=>false,
        "hydraulic_recovery_verified"=>false,
        "ac_grid_verified"=>false,
        "witness_checks"=>Any[],
    )
    haskey(r, "normal") || return q
    r["status"] in ("candidate", "time_limit_with_solution") || error("联合状态与候选矛盾")
    n=r["normal"]
    !haskey(n, "lower_bound_USD") || error("正常子记录不能继承安全规划费用界")
    nq=validate_r7_normal_flow(c.normal, s["normal_flow"], n)
    q["normal_check"]=nq
    q["normal_pass"]=nq["model_pass"]
    keys=[r7_planning_pair_key((event = w["event"], fault = w["fault"])) for w in r["witnesses"]]
    keys==r7_planning_pair_key.(r7_planning_pairs(c)) || error("联合故障见证缺失/重复/顺序错误")
    q["normal_pass"] || return q
    checks=[r7_joint_witness_check(c, s, n, w) for w in r["witnesses"]]
    q["witness_checks"]=checks
    q["robust_model_pass"]=all(w["threshold_pass"] for w in checks)
    q["cost_USD"]=nq["cost_USD"]
    if haskey(r, "lower_bound_USD")
        isfinite(r["lower_bound_USD"]) || error("联合规划非有限界")
        gap=(q["cost_USD"]-r["lower_bound_USD"])/max(1, abs(q["cost_USD"]))
        q["relative_gap"]=gap
        q["domain_optimality_pass"]=q["robust_model_pass"]&&-1e-6<=gap<=1e-4
    end
    q
end
