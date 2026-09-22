"""
    validate_r7_thermal_reconstruction(case, recovery, spec, result)

独立重放各管水团、源荷功率和节点混合，检验子步边界全部空间温度及MWh总能量平衡。
不调用建模矩阵或求解器；A1为功率1e-6 MW、温度1e-4 K、流量1e-6 kg/s。
该认证仅为项目子步平均热模型，不自动认证连续节点、水力、交流电网或全故障弹性。
"""
function validate_r7_thermal_reconstruction(c, r, spec, result)
    x=r7_thermal_inputs(c, r, spec)
    result["schema"]=="r7-thermal-result-v1" &&
    result["spec_sha256"]==r7_digest(spec) &&
    result["parent_result_sha256"]==r7_digest(r) &&
    result["objective_kind"]=="conditional_heat_unserved_MWh" || error("热重构结果身份不符")
    result["status"]=="infeasible_certified" &&
        result["termination_status"]!="INFEASIBLE" &&
        error("不可行状态缺少求解器终止证据")
    r7_validate_thermal_values(x, spec, result)
end

function r7_validate_thermal_values(x, spec, result)
    h=x.h
    rows=Dict{String,Any}[]
    q=Dict{String,Any}(
        "thermal_model_pass"=>false,
        "same_dispatch_pass"=>false,
        "conditional_heat_optimality_pass"=>false,
        "continuous_node_dynamics_verified"=>false,
        "hydraulic_verified"=>false,
        "ac_grid_validated"=>false,
        "whole_recovery_certified"=>false,
        "port_witness"=>r7_thermal_port_witness(x),
        "rows"=>rows,
    )
    haskey(result, "values") || return q
    result["status"] in
    ("infeasible_certified", "budget_exhausted", "time_limit_no_solution", "license_unavailable") &&
        error("失败状态却有热重构解")
    shapes=Dict(k=>(x.J, x.K, x.W) for k in ("S", "R", "T_source", "T_load", "H_delivered"))
    merge!(shapes, Dict(k=>(x.A, x.K, x.W) for k in ("out_S", "out_R")))
    merge!(shapes, Dict(k=>(x.A, x.K+1, x.W) for k in ("E_S", "E_R")))
    Set(keys(result["values"]))==Set(keys(shapes)) || error("热重构变量集合错误")
    isfinite(result["solver_objective_MWh"]) || error("热重构目标不是有限值")
    v=Dict(k=>r7_unpack(result["values"], k) for k in keys(shapes))
    all(size(v[k])==s && all(isfinite, v[k]) for (k, s) in shapes) ||
        error("热重构数值形状或有限性错误")
    rec(id, obj, k, w, res, unit, tol) = push!(
        rows,
        Dict(
            "id"=>id,
            "object"=>string(obj),
            "step"=>k,
            "scenario"=>w,
            "residual"=>Float64(abs(res)),
            "unit"=>unit,
            "tolerance"=>tol,
            "pass"=>abs(res)<=tol,
        ),
    )
    bound(id, obj, k, w, y, lo, hi, unit, tol) = rec(id, obj, k, w, max(lo-y, y-hi, 0), unit, tol)
    replay=Dict{Tuple{Int,String,Int},Any}()
    loss=zeros(x.K, x.W)
    cw=h["c_J_kgK"]/1e6
    for a in 1:x.A, side in ("S", "R"), w in 1:x.W
        p=h["pipes"][a]
        inlet=[
            v[side][r7_thermal_ends(p, side, x.v["m_pipe"][a, cld(k, x.n)])[1], k, w] for k in 1:x.K
        ]
        sim=r7_thermal_pipe_replay(x, a, side, w, inlet)
        replay[(a, side, w)]=sim
        for k in 1:x.K
            step=sim.steps[k]
            loss[k, w]+=step.loss_MWh
            ref=step.outlet_mean_K===nothing ? 0.0 : step.outlet_mean_K
            rec("R7-T1-transport", "$side/$a", k, w, v["out_$side"][a, k, w]-ref, "K", 1e-4)
            step.outlet_mean_K===nothing || bound(
                "R7-T-bound",
                "$side/$a",
                k,
                w,
                ref,
                h["$(side)_min_K"],
                h["$(side)_max_K"],
                "K",
                1e-4,
            )
            rec("R7-T4-pipe-energy", "$side/$a", k, w, step.energy_residual_MWh, "MWh", 1e-6*x.dt)
            rec("R7-T4-pipe-mass", "$side/$a", k, w, step.mass_residual_kg/3600/x.dt, "kg/s", 1e-6)
        end
        for k in 1:(x.K+1)
            inv=r7_pipe_inventory(
                sim.states[k];
                cp_J_kgK = h["c_J_kgK"],
                reference_K = h["$(side)_min_K"],
            )
            rec(
                "R7-T4-inventory",
                "$side/$a",
                k,
                w,
                v["E_$side"][a, k, w]-inv.relative_heat_MWh,
                "MWh",
                1e-6*x.dt,
            )
            for (i, temp) in enumerate(r7_thermal_extrema(sim.states[k]))
                bound(
                    "R7-T4-spatial",
                    "$side/$a/$i",
                    k,
                    w,
                    temp,
                    h["$(side)_min_K"],
                    h["$(side)_max_K"],
                    "K",
                    1e-4,
                )
            end
        end
    end
    unchanged=true
    for j in 1:x.J, k in 1:x.K, w in 1:x.W
        t=cld(k, x.n)
        ms=x.v["m_source"][j, t]
        ml=x.v["m_load"][j, t]
        for (key, side) in (("S", "S"), ("R", "R"), ("T_source", "S"), ("T_load", "R"))
            bound(
                "R7-T-bound",
                "$key/$j",
                k,
                w,
                v[key][j, k, w],
                h["$(side)_min_K"],
                h["$(side)_max_K"],
                "K",
                1e-4,
            )
        end
        gen=cw*ms*(v["T_source"][j, k, w]-v["R"][j, k, w])
        load=cw*ml*(v["S"][j, k, w]-v["T_load"][j, k, w])
        rec("R7-T2-source", j, k, w, gen-x.generated[j, t, w], "MW", 1e-6)
        rec("R7-T2-load", j, k, w, load-v["H_delivered"][j, k, w], "MW", 1e-6)
        lo=spec["mode"]=="same_dispatch" ? x.served[j, t, w] :
           h["load_MW"][j][t]*(1-h["shed_fraction_max"][j])
        bound("R7-T-control", j, k, w, v["H_delivered"][j, k, w], lo, x.served[j, t, w], "MW", 1e-6)
        unchanged &= abs(v["H_delivered"][j, k, w]-x.served[j, t, w])<=1e-6
        if ms>0
            bound(
                "R7-T-port-source",
                j,
                k,
                w,
                v["T_source"][j, k, w]-v["R"][j, k, w],
                h["source_delta_min"][j],
                h["source_delta_max"][j],
                "K",
                1e-4,
            )
        else
            rec("R7-T-idle-source", j, k, w, v["T_source"][j, k, w]-v["S"][j, k, w], "K", 1e-4)
        end
        if ml>0
            bound(
                "R7-T-port-load",
                j,
                k,
                w,
                v["S"][j, k, w]-v["T_load"][j, k, w],
                h["load_delta_min"][j],
                h["load_delta_max"][j],
                "K",
                1e-4,
            )
        else
            rec("R7-T-idle-load", j, k, w, v["T_load"][j, k, w]-v["R"][j, k, w], "K", 1e-4)
        end
        mass=ms-ml
        for (a, p) in enumerate(h["pipes"])
            mass+=((p["to"]==j ? 1 : 0)-(p["from"]==j ? 1 : 0))*x.v["m_pipe"][a, t]
        end
        rec("R7-T-mass", j, k, w, mass, "kg/s", 1e-6)
        for (side, port, rate) in (("S", "T_source", ms), ("R", "T_load", ml))
            total=rate
            enthalpy=rate*v[port][j, k, w]
            for (a, p) in enumerate(h["pipes"])
                flow=x.v["m_pipe"][a, t]
                _, to=r7_thermal_ends(p, side, flow)
                if to==j && flow!=0
                    total+=abs(flow)
                    enthalpy+=abs(flow)*replay[(a, side, w)].steps[k].outlet_mean_K
                end
            end
            expected=total>0 ? enthalpy/total : h["$(side)_reference_K"]
            rec("R7-T3-mix", "$side/$j", k, w, v[side][j, k, w]-expected, "K", 1e-4)
        end
    end
    for k in 1:x.K, w in 1:x.W
        t=cld(k, x.n)
        delta=sum(v["E_$side"][a, k+1, w]-v["E_$side"][a, k, w] for side in ("S", "R"), a in 1:x.A)
        rec(
            "R7-T4-total",
            "network",
            k,
            w,
            delta-x.dt*(sum(x.generated[:, t, w])-sum(v["H_delivered"][:, k, w]))+loss[k, w],
            "MWh",
            1e-6*x.dt,
        )
    end
    unserved=x.dt*sum(
        x.d["probabilities"][w]*(h["load_MW"][j][cld(k, x.n)]-v["H_delivered"][j, k, w]) for
        j in 1:x.J, k in 1:x.K, w in 1:x.W
    )
    rec("objective", "network", 0, 0, result["solver_objective_MWh"]-unserved, "MWh", 1e-6*x.dt)
    q["thermal_model_pass"]=all(z["pass"] for z in rows)
    q["same_dispatch_pass"]=q["thermal_model_pass"]&&unchanged
    q["heat_unserved_MWh"]=unserved
    q["loss_to_environment_MWh"]=sum(loss[k, w]*x.d["probabilities"][w] for k in 1:x.K, w in 1:x.W)
    q["max_normalized_residual"]=maximum(z["residual"]/z["tolerance"] for z in rows)
    if haskey(result, "lower_bound_MWh")
        lb=result["lower_bound_MWh"]
        q["conditional_heat_optimality_pass"]=q["thermal_model_pass"]&&isfinite(lb)&&lb<=unserved+1e-6*x.dt&&(
            unserved-lb
        )/max(1.0, abs(unserved))<=1e-4
    end
    q
end
