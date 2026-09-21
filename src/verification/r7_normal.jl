function r7_normal_decode(c, r; thermal = true)
    shape=r7_normal_shape(c)
    if !thermal
        filter!(
            p->!(
                startswith(first(p), "τ_") ||
                startswith(first(p), "Φ_") ||
                startswith(first(p), "E_pipe_")
            ),
            shape,
        )
    end
    Set(keys(r["values"]))==Set(keys(shape)) || error("正常调度值字段不完整")
    v=Dict(k=>r7_unpack(r["values"], k) for k in keys(shape))
    all(size(v[k])==s&&all(isfinite, v[k]) for (k, s) in shape) ||
        error("正常调度值形状或有限性错误")
    ids=Set(g["id"] for g in c.data["devices"] if g["kind"]=="CHP")
    Set(keys(r["chp_values"]))==ids || error("正常启停字段不完整")
    v
end

# 独立以时间区间交集计算恒流节点法K；不读取建模系数或fixed_flow_kernel。
function r7_normal_node_outlet(d, p, side, w, input)
    h=d["heat"]
    dt_s=3600d["dt_h"]
    f=first(p["normal_flow_kg_s"])
    M=h["rho_kg_m3"]*p["volume_$(side)_m3"]
    delay=M/(f*dt_s)
    J=exp(-p["UA_$(side)_W_K"]*dt_s/(h["c_J_kgK"]*M)*(ceil(Int, delay)-0.5))
    hist=p["history_$(side)_K"]
    T=d["periods"]
    out=zeros(T)
    for t in 1:T
        lo, hi=t-1-delay, t-delay
        average=0.0
        covered=0.0
        for k in (1-length(hist)):T
            weight=max(0.0, min(hi, k)-max(lo, k-1))
            weight==0 && continue
            average+=weight*(k>0 ? input[k] : hist[end+k][w])
            covered+=weight
        end
        abs(covered-1)<=1e-10 || error("节点法独立质量覆盖不足")
        out[t]=h["ambient_K"][t]+J*(average-h["ambient_K"][t])
    end
    out
end

"""
    validate_r7_normal(case, result; thermal=true)

从保存值独立回代正常电热网络、启停、电池状态与期望费用，采用既有A1/A2。
输运按水团回放或独立区间交集重算，不读JuMP表达式；作者节点法与连续参考差异单独报告。
返回给定流量条件模型的检查和成本界，交流潮流、自由流量灾前最优及故障保证仍未认证。
thermal=false仅核验共用设备、电池、启停、电网及成本，输入值必须没有热网状态字段。
此时仅返回shared_block_pass，model_pass及optimality_pass保持false，不能冒充完整正常模型通过。
"""
function validate_r7_normal(c::R7NormalCase, r; thermal = true)
    r7_normal_assert(c)
    r7_check_currency_record(c.data, r)
    r["schema"]==r7_money_schema(c.data, "r7-normal-result-v1") &&
    r["version"]=="r7_normal_prescribed_v1" &&
    r["case_sha256"]==c.sha256 &&
    r["objective_kind"]==r7_normal_objective_kind(c.data) &&
    r["thermal_model"]==c.data["thermal_model"] &&
    r["full_preplan_optimality_verified"]===false || error("正常结果身份、范围或目标错误")
    out=Dict{String,Any}(
        "model_pass"=>false,
        "cost_pass"=>false,
        "optimality_pass"=>false,
        "pipe_reference_pass"=>false,
        "full_preplan_optimality_verified"=>false,
        "ac_grid_validated"=>false,
        "rows"=>Dict{String,Any}[],
    )
    r7_currency_record!(out, c.data)
    thermal || (out["shared_block_pass"]=false)
    haskey(r, "values") || return out
    r["status"] in
    ("infeasible_certified", "budget_exhausted", "time_limit_no_solution", "license_unavailable") &&
        error("正常状态与候选矛盾")
    isfinite(r[r7_money_key(c.data, "solver_objective_USD")]) || error("正常目标非有限")
    v=r7_normal_decode(c, r; thermal)
    d=c.data
    e, h=d["electric"], d["heat"]
    ds, ls, ps=d["devices"], e["lines"], h["pipes"]
    T, W, N, J=d["periods"], length(d["probabilities"]), e["nodes"], h["nodes"]
    dt=d["dt_h"]
    cp=h["c_J_kgK"]/1e6
    pscale=max(
        1.0,
        maximum(reduce(vcat, e["load_MW"])),
        maximum(reduce(vcat, h["load_MW"])),
        sum(g["P_max_MW"] for g in ds; init = 0.0),
    )
    escale=max(
        1.0,
        maximum((g["E_max_MWh"] for g in ds if g["kind"]=="BES"); init = 0.0),
        h["c_J_kgK"]*h["rho_kg_m3"]/3.6e9*sum(
            p["volume_$(side)_m3"]*(h["$(side)_max_K"]-h["$(side)_min_K"]) for
            p in ps, side in ("S", "R")
        ),
    )
    pt, et=1e-6*(1+pscale), 1e-6*(1+escale)
    function rec(id, entity, t, w, x, unit, tol; scope = "adopted")
        push!(
            out["rows"],
            Dict(
                "id"=>id,
                "entity"=>string(entity),
                "t"=>t,
                "scenario"=>w,
                "residual"=>abs(Float64(x)),
                "unit"=>unit,
                "tolerance"=>tol,
                "normalized"=>abs(Float64(x))/tol,
                "pass"=>isfinite(x)&&abs(x)<=tol,
                "scope"=>scope,
            ),
        )
    end
    bound(id, entity, t, w, x, lo, hi, unit, tol) =
        rec(id, entity, t, w, max(0.0, lo-x, x-hi), unit, tol)
    r7_verify_battery_domain!(rec, d, r, v, pt)
    startup=0.0
    simultaneous=0.0
    for (g, z) in enumerate(ds)
        kind=z["kind"]
        if kind=="CHP"
            cv=Dict(
                k=>r7_unpack(r["chp_values"][z["id"]], k) for k in keys(r["chp_values"][z["id"]])
            )
            check=validate_r7_chp(r7_normal_chp(d, z), cv)
            startup+=check[r7_money_key(c.data, "startup_cost_USD")]
            for row in check["rows"]
                rec(
                    row["formula"],
                    z["id"],
                    row["t"],
                    row["scenario"],
                    row["residual"],
                    row["unit"],
                    row["tolerance"],
                )
            end
            if haskey(r, "fixed_commitments")
                Set(keys(r["fixed_commitments"]))==Set(keys(r["chp_values"])) ||
                    error("固定启停记录不完整")
                schedule=r7_numbers(
                    r["fixed_commitments"][z["id"]],
                    (T,),
                    "存档固定启停";
                    lo = 0,
                    hi = 1,
                )
                all(isinteger, schedule) || error("存档固定启停非二值")
                for t in 1:T
                    rec("fixed-commitment", z["id"], t, 0, cv["u_CHP"][t]-schedule[t], "1", 1e-6)
                end
            end
            for t in 1:T, w in 1:W, (key, ck) in (("P", "P_CHP"), ("Q", "Q_CHP"), ("H", "H_CHP"))
                rec(
                    "R7-D-device-link",
                    z["id"],
                    t,
                    w,
                    v[key][g, t, w]-cv[ck][t, w],
                    key=="Q" ? "Mvar" : "MW",
                    pt,
                )
            end
        end
        for t in 1:T, w in 1:W
            if kind!="CHP"
                hi=kind=="PV" ? z["available_MW"][t][w] : kind=="BES" ? 0.0 : z["P_max_MW"]
                bound("6-8:10", z["id"], t, w, v["P"][g, t, w], 0, hi, "MW", pt)
                bound(
                    "6-9",
                    z["id"],
                    t,
                    w,
                    v["Q"][g, t, w],
                    0,
                    kind=="GT" ? z["Q_max_Mvar"] : 0,
                    "Mvar",
                    pt,
                )
                rec(
                    "6-11",
                    z["id"],
                    t,
                    w,
                    v["H"][g, t, w]-(kind=="EB" ? z["heat_ratio"]*v["P"][g, t, w] : 0),
                    "MW",
                    pt,
                )
            end
            ch, dis=v["P_ch"][g, t, w], v["P_dis"][g, t, w]
            for (key, x) in (("ch", ch), ("dis", dis))
                bound("6-12-$key", z["id"], t, w, x, 0, kind=="BES" ? z["P_max_MW"] : 0, "MW", pt)
            end
            if kind=="BES"
                bound("6-12", z["id"], t, w, ch+dis, 0, z["P_max_MW"], "MW", pt)
                rec(
                    "6-14",
                    z["id"],
                    t,
                    w,
                    v["E_BES"][g, t+1, w]-v["E_BES"][g, t, w]-dt*(z["eta_ch"]*ch-dis/z["eta_dis"]),
                    "MWh",
                    et,
                )
                simultaneous=max(simultaneous, min(ch, dis))
            end
        end
        for k in 1:(T+1), w in 1:W
            if kind=="BES"
                bound(
                    "6-13",
                    z["id"],
                    k,
                    w,
                    v["E_BES"][g, k, w],
                    z["E_min_MWh"],
                    z["E_max_MWh"],
                    "MWh",
                    et,
                )
                k==1 && rec(
                    "R7-D-battery-initial",
                    z["id"],
                    k,
                    w,
                    v["E_BES"][g, k, w]-z["initial_MWh"][w],
                    "MWh",
                    et,
                )
                k==T+1 &&
                    rec("6-15", z["id"], k, w, v["E_BES"][g, k, w]-v["E_BES"][g, 1, w], "MWh", et)
            else
                rec("6-13-zero", z["id"], k, w, v["E_BES"][g, k, w], "MWh", et)
            end
        end
    end
    for t in 1:T, w in 1:W
        bound("PCC-P", 1, t, w, v["P_PCC"][t, w], e["pcc_min_MW"], e["pcc_max_MW"], "MW", pt)
        bound("PCC-Q", 1, t, w, v["Q_PCC"][t, w], e["qcc_min_Mvar"], e["qcc_max_Mvar"], "Mvar", pt)
        for n in 1:N
            bound("6-22", n, t, w, v["v"][n, t, w], e["v_min_pu"], e["v_max_pu"], "pu", 1e-6)
            n==e["pcc_node"] &&
                rec("root-voltage", n, t, w, v["v"][n, t, w]-e["v_ref_pu"], "pu", 1e-6)
            for (key, unit, demand) in
                (("P", "MW", e["load_MW"][n][t]), ("Q", "Mvar", e["tan_phi"][n]*e["load_MW"][n][t]))
                injection=n==e["pcc_node"] ? v["$(key)_PCC"][t, w] : 0.0
                for (g, z) in enumerate(ds)
                    z["electric_node"]==n || continue
                    injection+=key=="P" ?
                               (z["kind"]=="EB" ? -1 : 1)*v[key][g, t, w]+v["P_dis"][g, t, w]-v["P_ch"][
                        g,
                        t,
                        w,
                    ] : v[key][g, t, w]
                end
                for (l, z) in enumerate(ls)
                    z["to"]==n && (injection+=v["$(key)_line"][l, t, w])
                    z["from"]==n && (injection-=v["$(key)_line"][l, t, w])
                end
                rec(key=="P" ? "6-18:19" : "6-20", n, t, w, injection-demand, unit, pt)
            end
        end
        for (l, z) in enumerate(ls)
            sgn=e["flow_domain"]=="signed" ? -1 : 0
            for (key, cap, unit) in (("P_line", "P_max_MW", "MW"), ("Q_line", "Q_max_Mvar", "Mvar"))
                bound(
                    "6-24:25",
                    l,
                    t,
                    w,
                    v[key][l, t, w],
                    sgn*z[cap]*z["base_closed"],
                    z[cap]*z["base_closed"],
                    unit,
                    pt,
                )
            end
            if z["base_closed"]==1
                drop=(z["r_pu"]*v["P_line"][l, t, w]+z["x_pu"]*v["Q_line"][l, t, w])/(
                    e["S_base_MVA"]*e["v_ref_pu"]
                )
                rec(
                    "R7-D-voltage",
                    l,
                    t,
                    w,
                    v["v"][z["from"], t, w]-v["v"][z["to"], t, w]-drop,
                    "pu",
                    1e-6,
                )
            end
        end
        for j in (thermal ? (1:J) : (1:0))
            for (key, side) in (("τ_S", "S"), ("τ_R", "R"), ("τ_source", "S"), ("τ_load", "R"))
                bound(
                    "6-27:29",
                    j,
                    t,
                    w,
                    v[key][j, t, w],
                    h["$(side)_min_K"],
                    h["$(side)_max_K"],
                    "K",
                    1e-4,
                )
            end
            ms, md=h["source_flow_kg_s"][j][t], h["load_flow_kg_s"][j][t]
            generated=sum(
                v["H"][g, t, w] for
                (g, z) in enumerate(ds) if z["kind"] in ("CHP", "EB")&&z["heat_node"]==j;
                init = 0.0,
            )
            rec(
                "6-26",
                j,
                t,
                w,
                generated-cp*ms*(v["τ_source"][j, t, w]-v["τ_R"][j, t, w]),
                "MW",
                pt,
            )
            rec(
                "6-28",
                j,
                t,
                w,
                h["load_MW"][j][t]-cp*md*(v["τ_S"][j, t, w]-v["τ_load"][j, t, w]),
                "MW",
                pt,
            )
            if ms>0
                bound(
                    "source-delta",
                    j,
                    t,
                    w,
                    v["τ_source"][j, t, w]-v["τ_R"][j, t, w],
                    h["source_delta_min"][j],
                    h["source_delta_max"][j],
                    "K",
                    1e-4,
                )
            else
                rec("idle-source", j, t, w, v["τ_source"][j, t, w]-v["τ_S"][j, t, w], "K", 1e-4)
            end
            if md>0
                bound(
                    "load-delta",
                    j,
                    t,
                    w,
                    v["τ_S"][j, t, w]-v["τ_load"][j, t, w],
                    h["load_delta_min"][j],
                    h["load_delta_max"][j],
                    "K",
                    1e-4,
                )
            else
                rec("idle-load", j, t, w, v["τ_load"][j, t, w]-v["τ_R"][j, t, w], "K", 1e-4)
            end
            fs, fr=ms, md
            bs=ms*v["τ_source"][j, t, w]
            br=md*v["τ_load"][j, t, w]
            for (a, p) in enumerate(ps)
                f=p["normal_flow_kg_s"][t]
                if p["to"]==j
                    fs+=f
                    bs+=f*v["τ_pipe_S"][a, t, w]
                end
                if p["from"]==j
                    fr+=f
                    br+=f*v["τ_pipe_R"][a, t, w]
                end
            end
            rec("R7-D-mix-S", j, t, w, v["τ_S"][j, t, w]-bs/fs, "K", 1e-4)
            rec("R7-D-mix-R", j, t, w, v["τ_R"][j, t, w]-br/fr, "K", 1e-4)
        end
    end
    total_loss=zeros(T, W)
    total_delta=zeros(T, W)
    for (a, p) in enumerate(thermal ? ps : []), side in ("S", "R"), w in 1:W
        input=collect(v["τ_$side"][p[side=="S" ? "from" : "to"], :, w])
        replay=r7_normal_pipe_replay(d, p, side, w, input)
        adopted=d["thermal_model"]=="node_method_fixed_v1" ?
                r7_normal_node_outlet(d, p, side, w, input) : replay.outlet
        cap=h["c_J_kgK"]*h["rho_kg_m3"]*p["volume_$(side)_m3"]/3.6e9*(
            h["$(side)_max_K"]-h["$(side)_min_K"]
        )
        for t in 1:T
            rec(
                "R7-D-transport",
                "$a-$side",
                t,
                w,
                v["τ_pipe_$side"][a, t, w]-adopted[t],
                "K",
                1e-4,
            )
            bound(
                "pipe-temperature",
                "$a-$side",
                t,
                w,
                v["τ_pipe_$side"][a, t, w],
                h["$(side)_min_K"],
                h["$(side)_max_K"],
                "K",
                1e-4,
            )
            rec(
                "reference-outlet",
                "$a-$side",
                t,
                w,
                v["τ_pipe_$side"][a, t, w]-replay.outlet[t],
                "K",
                1e-4;
                scope = "pipe_reference",
            )
            rec(
                "reference-energy",
                "$a-$side",
                t,
                w,
                replay.steps[t].energy_residual_MWh,
                "MWh",
                et;
                scope = "pipe_reference",
            )
            total_loss[t, w]+=replay.steps[t].loss_MWh
            total_delta[t, w]+=replay.energy[t+1]-replay.energy[t]
        end
        for k in 1:(T+1)
            rec(
                "R7-D-inventory",
                "$a-$side",
                k,
                w,
                v["E_pipe_$side"][a, k, w]-replay.energy[k],
                "MWh",
                et,
            )
            bound("inventory-domain", "$a-$side", k, w, replay.energy[k], 0, cap, "MWh", et)
        end
        d["heat_terminal_rule"]=="pipe_inventory_initial" && rec(
            "R7-D-thermal-terminal",
            "$a-$side",
            T+1,
            w,
            replay.energy[end]-replay.energy[1],
            "MWh",
            et,
        )
    end
    for t in (thermal ? (1:T) : (1:0)), w in 1:W
        balance=dt*(sum(v["H"][:, t, w])-sum(h["load_MW"][j][t] for j in 1:J))-total_loss[t, w]-total_delta[
            t,
            w,
        ]
        rec(
            "reference-network-energy",
            "network",
            t,
            w,
            balance,
            "MWh",
            et;
            scope = d["thermal_model"]=="plug_flow_reference_v1" ? "adopted" : "pipe_reference",
        )
    end
    for t in (thermal ? (1:T) : (1:0))
        for j in 1:J
            for side in ("S", "R")
                bound(
                    "6-35",
                    j,
                    t,
                    0,
                    v["Φ_$side"][j, t],
                    0,
                    h["pressure_max_Pa"],
                    "Pa",
                    1e-6*h["pressure_max_Pa"],
                )
            end
            bound(
                "6-36",
                j,
                t,
                0,
                v["Φ_S"][j, t]-v["Φ_R"][j, t],
                h["delta_pressure_min_Pa"],
                h["delta_pressure_max_Pa"],
                "Pa",
                1e-6*h["pressure_max_Pa"],
            )
        end
        for (a, p) in enumerate(ps), side in ("S", "R")
            i, j=side=="S" ? (p["from"], p["to"]) : (p["to"], p["from"])
            valve=v["Φ_val_$side"][a, t]
            bound(
                "valve-head",
                "$a-$side",
                t,
                0,
                valve,
                0,
                p["valve_max_Pa"],
                "Pa",
                1e-6*h["pressure_max_Pa"],
            )
            residual=v["Φ_$side"][i, t]-v["Φ_$side"][j, t]-valve-p["mu_$(side)_Pa_s2_kg2"]*p["normal_flow_kg_s"][t]^2
            rec("R7-D-pressure-$side", a, t, 0, residual/h["pressure_max_Pa"], "1", 1e-6)
        end
    end
    resource=dt*sum(
        d["probabilities"][w]*z[r7_money_key(c.data, "cost_P_USD_MWh")]*(
            z["kind"]=="BES" ? v["P_ch"][g, t, w]+v["P_dis"][g, t, w] : v["P"][g, t, w]
        ) for (g, z) in enumerate(ds), t in 1:T, w in 1:W
    )
    grid=dt*sum(
        d["probabilities"][w]*e[r7_money_key(c.data, "price_USD_MWh")][t]*v["P_PCC"][t, w] for
        t in 1:T, w in 1:W
    )
    cost=startup+resource+grid
    rec(
        "6-1",
        "cost",
        0,
        0,
        r[r7_money_key(c.data, "solver_objective_USD")]-cost,
        r7_currency(c.data),
        1e-6*max(1, abs(cost)),
    )
    out["model_pass"]=all(x["pass"] for x in out["rows"] if x["scope"]=="adopted")
    out["pipe_reference_pass"]=all(x["pass"] for x in out["rows"] if x["scope"]=="pipe_reference")
    out["cost_pass"]=last(out["rows"])["pass"]
    out[r7_money_key(c.data, "cost_USD")]=cost
    out[r7_money_key(c.data, "startup_cost_USD")]=startup
    out[r7_money_key(c.data, "resource_cost_USD")]=resource
    out[r7_money_key(c.data, "grid_payment_USD")]=grid
    out["max_simultaneous_charge_discharge_MW"]=simultaneous
    out["mutual_exclusivity_pass"]=simultaneous<=pt
    if haskey(r, r7_money_key(c.data, "lower_bound_USD"))
        isfinite(r[r7_money_key(c.data, "lower_bound_USD")]) || error("正常成本界非有限")
        gap=(cost-r[r7_money_key(c.data, "lower_bound_USD")])/max(1, abs(cost))
        out["relative_gap"]=gap
        out["optimality_pass"]=out["model_pass"] && -1e-6<=gap<=1e-4
    end
    if !thermal
        out["shared_block_pass"]=out["model_pass"]
        out["model_pass"]=false
        out["pipe_reference_pass"]=false
        out["optimality_pass"]=false
    end
    out
end

# 只允许至多8个Float64 ULP的边界表示修正；不修改原值，不以A1容差裁剪真实越界。
function r7_boundary_roundoff(x, lo, hi, path, unit, changes)
    lo<=x<=hi && return Float64(x)
    y=clamp(Float64(x), lo, hi)
    tol=8eps(max(1.0, abs(Float64(x)), abs(Float64(lo)), abs(Float64(hi))))
    abs(y-x)<=tol || error("事件初值超出声明界且不是Float64尾差：$path")
    push!(
        changes,
        Dict(
            "field"=>path,
            "unit"=>unit,
            "original"=>Float64(x),
            "inherited"=>Float64(y),
            "delta"=>Float64(y-x),
            "maximum_roundoff"=>tol,
            "rule"=>"at_most_eight_float64_ulps_at_declared_bound",
        ),
    )
    Float64(y)
end

"""
    r7_normal_event(case, result; event_start, periods, renewable_factor, loss_limit_MWh)

将通过正常模型及连续管道回放的同一轨迹转换为R7RecoveryCase。CHP取t_s-1功率与窗口启停，
电池取区间起点E[t_s]，管温取完成t_s-1步后的整管质量平均；场景不平均。
返回恢复输入和父运行/状态证据。至多8 ULP的边界尾差显式记录原值与继承值，更大越界拒绝；
不优化、不承诺灾后全部显热可回收，也不证明自由流量灾前最优。
"""
function r7_normal_event(c::R7NormalCase, r; event_start, periods, renewable_factor, loss_limit_MWh)
    check=validate_r7_normal(c, r)
    check["model_pass"] && check["pipe_reference_pass"] ||
        error("正常调度或管道物理回放未通过，不生成恢复初值")
    d=c.data
    T=d["periods"]
    W=length(d["probabilities"])
    event_start isa Integer &&
    periods isa Integer &&
    periods>0 &&
    1<=event_start<=event_start+periods-1<=T || error("事件窗口超出正常轨迹")
    at=event_start
    win=at:(at+periods-1)
    v=r7_normal_decode(c, r)
    ed=Dict{String,Any}(
        "schema"=>"r7-recovery-case-v1",
        "name"=>d["name"]*"_event_$(at)_$(periods)",
        "origin"=>d["origin"],
        "preplan_id"=>r["run_id"],
        "periods"=>periods,
        "dt_h"=>d["dt_h"],
        "event_start"=>at,
        "probabilities"=>deepcopy(d["probabilities"]),
        "renewable_factor"=>renewable_factor,
        "loss_limit_MWh"=>loss_limit_MWh,
        "battery_rule"=>d["battery_rule"],
        "units"=>deepcopy(d["units"]),
    )
    r7_currency_record!(ed, d)
    ed["electric"]=deepcopy(d["electric"])
    ed["electric"]["load_MW"]=[a[win] for a in d["electric"]["load_MW"]]
    h=deepcopy(d["heat"])
    h["load_MW"]=[a[win] for a in d["heat"]["load_MW"]]
    h["ambient_K"]=h["ambient_K"][win]
    h["reference_flow_kg_s"]=[
        sum(d["heat"]["source_flow_kg_s"][j][t] for j in 1:h["nodes"]) for t in win
    ]
    profiles=Dict{String,Any}[]
    adjustments=Dict{String,Any}[]
    for (a, p) in enumerate(h["pipes"])
        for side in ("S", "R")
            means=Float64[]
            for w in 1:W
                replay=r7_normal_pipe_replay(
                    d,
                    d["heat"]["pipes"][a],
                    side,
                    w,
                    collect(v["τ_$side"][p[side=="S" ? "from" : "to"], :, w]),
                )
                state=replay.states[at]
                inventory=r7_pipe_inventory(
                    state;
                    cp_J_kgK = h["c_J_kgK"],
                    reference_K = h["$(side)_min_K"],
                )
                inherited=r7_boundary_roundoff(
                    inventory.mean_K,
                    h["$(side)_min_K"],
                    h["$(side)_max_K"],
                    "pipe[$a].$(side)[$w]",
                    "K",
                    adjustments,
                )
                push!(means, inherited)
                push!(
                    profiles,
                    Dict(
                        "pipe"=>a,
                        "side"=>side,
                        "scenario"=>w,
                        "mass_kg"=>inventory.mass_kg,
                        "mean_K"=>inventory.mean_K,
                        "reference_K"=>h["$(side)_min_K"],
                        "relative_heat_MWh"=>inventory.relative_heat_MWh,
                        "segments"=>[
                            Dict(
                                "mass_kg"=>s.mass_kg,
                                "base_K"=>s.base_K,
                                "amplitude_K"=>s.amplitude_K,
                                "rate_per_kg"=>s.rate_per_kg,
                                "from_left"=>s.from_left,
                            ) for s in state.segments
                        ],
                    ),
                )
            end
            p["initial_$(side)_K"]=means
            delete!(p, "initial_$(side)_profiles")
            pop!(p, "history_$(side)_K", nothing)
        end
        p["normal_flow_kg_s"]=p["normal_flow_kg_s"][win]
    end
    pop!(h, "source_flow_kg_s")
    pop!(h, "load_flow_kg_s")
    ed["heat"]=h
    ed["devices"]=deepcopy(d["devices"])
    for (g, z) in enumerate(ed["devices"])
        if z["kind"]=="CHP"
            cv=Dict(
                k=>r7_unpack(r["chp_values"][z["id"]], k) for k in keys(r["chp_values"][z["id"]])
            )
            b=r7_chp_event_boundary(r7_normal_chp(d, d["devices"][g]), cv; event_start, periods)
            merge!(z, b["fields"])
            u=z["previous_commitment"]
            z["previous_P_MW"]=[
                r7_boundary_roundoff(
                    x,
                    u*z["P_min_MW"],
                    u*z["P_max_MW"],
                    "device[$g].previous_P[$w]",
                    "MW",
                    adjustments,
                ) for (w, x) in enumerate(z["previous_P_MW"])
            ]
        elseif z["kind"]=="BES"
            z["initial_MWh"]=[
                r7_boundary_roundoff(
                    x,
                    z["E_min_MWh"],
                    z["E_max_MWh"],
                    "device[$g].initial_E[$w]",
                    "MWh",
                    adjustments,
                ) for (w, x) in enumerate(v["E_BES"][g, at, :])
            ]
        elseif z["kind"]=="PV"
            z["available_MW"]=z["available_MW"][win]
        end
    end
    # 电价不是灾后失供目标；删去未切片的正常期序列，避免形成模糊的事件输入。
    pop!(ed["electric"], r7_money_key(c.data, "price_USD_MWh"))
    event=R7RecoveryCase(ed)
    evidence=Dict(
        "schema"=>"r7-normal-event-v1",
        "parent_run_id"=>r["run_id"],
        "parent_case_sha256"=>c.sha256,
        "parent_result_sha256"=>r7_digest(r),
        "event_case_sha256"=>event.sha256,
        "event_start"=>at,
        "periods"=>periods,
        "normal_thermal_model"=>d["thermal_model"],
        "normal_model_pass"=>check["model_pass"],
        "normal_pipe_reference_pass"=>check["pipe_reference_pass"],
        "conditional_cost_complete"=>check["optimality_pass"],
        "full_preplan_optimality_verified"=>false,
        "detailed_disaster_heat_verified"=>false,
        "initial_pipe_profiles"=>profiles,
        "boundary_adjustments"=>adjustments,
    )
    r7_currency_record!(evidence, d)
    (; case = event, evidence)
end
