const R5_DISPATCH_VERIFY_FILE = @__FILE__

# 独立质量区间重叠，不调用建模侧fixed_flow_kernel或管道JuMP表达式。
function r5_dispatch_pipe_replay(p, h, dt, t, input, ambient, side)
    delay=p["rho_kg_m3"]*p["area_m2"]*p["length_m"]/(p["m_kg_s"]*3600*dt)
    left, right=t-1-delay, t-delay
    hist=p["history_$(side)_K"]
    adv=0.0
    total=0.0
    for k in floor(Int, left):ceil(Int, right)
        w=max(0.0, min(right, k)-max(left, k-1))
        w==0 && continue
        val=k>0 ? input[k] : hist[end+k]
        adv+=w*val
        total+=w
    end
    χ=ceil(Int, delay)-1
    J=exp(-p["loss_W_mK"]*3600*dt/(h["c_J_kgK"]*p["rho_kg_m3"]*p["area_m2"])*(χ+0.5))
    (; temperature = ambient+J*(adv-ambient), weight_sum = total, advection = adv, attenuation = J)
end

"""
    validate_r5_dispatch(case, result)

从保存数值独立核算线性电网、供回水质量/温度混合、累计质量输运、建筑总受热和备用交付。
成本分开记录日前净支出、设备费用、实时收入和误差罚款；沿用A1/A2，不重新求解。
线性电网通过不认证交流潮流，固定流量热网通过不认证水压或备用不确定性的概率保证。
"""
function validate_r5_dispatch(c::R5DispatchCase, r)
    r5_dispatch_assert_case(c)
    get(r, "case_sha256", nothing)==c.sha256 || error("IES结果输入不一致")
    d=c.data
    T, B, L, N, A, S, J, G=r5_dispatch_sizes(c)
    e, h, a, rt=d["electric"], d["heat"], d["award"], d["realtime"]
    ds, bs, ss, ps, ls=d["devices"], d["buildings"], h["sources"], h["pipes"], e["lines"]
    rows=Dict{String,Any}[]
    out=Dict{String,Any}(
        "model_pass"=>false,
        "optimality_pass"=>false,
        "cost_pass"=>false,
        "auxiliary_exact_pass"=>false,
        "linear_electric_pass"=>false,
        "fixed_flow_heat_pass"=>false,
        "comfort_pass"=>false,
        "delivery_pass"=>false,
        "rows"=>rows,
    )
    haskey(r, "values") || return out
    record(id, group, entity, t, residual, unit, tol) = push!(
        rows,
        Dict{String,Any}(
            "id"=>id,
            "group"=>group,
            "entity"=>string(entity),
            "t"=>t,
            "residual"=>abs(Float64(residual)),
            "unit"=>unit,
            "tolerance"=>tol,
            "normalized"=>abs(Float64(residual))/tol,
            "pass"=>isfinite(residual)&&abs(residual)<=tol,
        ),
    )
    sizes=Dict(
        "P_DER"=>G,
        "Q_DER"=>G,
        "P_PCC"=>1,
        "Q_PCC"=>1,
        "P_line"=>L,
        "Q_line"=>L,
        "v"=>B,
        "τ_S"=>N,
        "τ_R"=>N,
        "τ_src"=>S,
        "τ_load_R"=>J,
        "τ_pipe_S"=>A,
        "τ_pipe_R"=>A,
        "H_D"=>J,
        "P_DH"=>J,
        "τ_IN"=>J,
        "delivery"=>1,
        "mismatch"=>1,
    )
    v=Dict{String,Matrix{Float64}}()
    for (name, n) in sizes
        raw=get(r["values"], name, nothing)
        if !(raw isa AbstractVector) || length(raw)!=n || any(x->length(x)!=T, raw)
            out["invalid_values"]="形状错误：$name"
            return out
        end
        v[name]=n==0 ? zeros(0, T) : r5_market_array(raw)
        all(isfinite, v[name]) || (out["invalid_values"] = "非有限值：$name"; return out)
    end
    dt=d["dt_h"]
    cp=h["c_J_kgK"]/1e6
    ep=max(
        1.0,
        e["pcc_max_MW"],
        sum(z["p_max_MW"] for z in ds; init = 0.0),
        sum(maximum(z) for z in e["P_load_MW"]),
    )
    hp=max(
        1.0,
        sum(z["p_max_MW"]*z["heat_ratio"] for z in ds if z["kind"] in ("CHP", "EB"); init = 0.0),
    )
    etol, htol=1e-6*(1+ep), 1e-6*(1+hp)
    bt(id, group, entity, t, x, lo, hi, unit, tol) =
        record(id, group, entity, t, max(0.0, lo-x, x-hi), unit, tol)
    for t in 1:T
        bt(
            "PCC-bound",
            "electric",
            "PCC",
            t,
            v["P_PCC"][1, t],
            e["pcc_min_MW"],
            e["pcc_max_MW"],
            "MW",
            etol,
        )
        bt(
            "QCC-bound",
            "electric",
            "PCC",
            t,
            v["Q_PCC"][1, t],
            e["qcc_min_Mvar"],
            e["qcc_max_Mvar"],
            "Mvar",
            etol,
        )
        for (g, z) in enumerate(ds)
            upper=z["kind"]=="PV" ? z["available_MW"][t] : z["p_max_MW"]
            bt("5-9-P", "electric", z["id"], t, v["P_DER"][g, t], z["p_min_MW"], upper, "MW", etol)
            bt(
                "5-9-Q",
                "electric",
                z["id"],
                t,
                v["Q_DER"][g, t],
                z["q_min_Mvar"],
                z["q_max_Mvar"],
                "Mvar",
                etol,
            )
            if z["kind"] in ("CHP", "GT")
                previous=t==1 ? z["P_initial_MW"] : v["P_DER"][g, t-1]
                bt(
                    "5-10",
                    "electric",
                    z["id"],
                    t,
                    v["P_DER"][g, t]-previous,
                    -dt*z["ramp_down_MW_h"],
                    dt*z["ramp_up_MW_h"],
                    "MW",
                    etol,
                )
            end
        end
        for n in 1:B
            p=(n==e["root"] ? v["P_PCC"][1, t] : 0.0)-e["P_load_MW"][n][t]
            q=(n==e["root"] ? v["Q_PCC"][1, t] : 0.0)-e["Q_load_Mvar"][n][t]
            for (g, z) in enumerate(ds)
                z["node"]==n || continue
                p+=(z["kind"]=="EB" ? -1 : 1)*v["P_DER"][g, t]
                q+=v["Q_DER"][g, t]
            end
            for (l, z) in enumerate(ls)
                sign=(z["to"]==n ? 1 : 0)-(z["from"]==n ? 1 : 0)
                p+=sign*v["P_line"][l, t]
                q+=sign*v["Q_line"][l, t]
            end
            p-=sum(v["P_DH"][j, t] for (j, z) in enumerate(bs) if z["electric_node"]==n; init = 0.0)
            record("5-14", "electric", n, t, p, "MW", etol)
            record("5-15", "electric", n, t, q, "Mvar", etol)
            bt("5-17", "electric", n, t, v["v"][n, t], e["v_min_pu"], e["v_max_pu"], "pu", 1e-6)
        end
        record(
            "root-voltage",
            "electric",
            e["root"],
            t,
            v["v"][e["root"], t]-e["v_ref_pu"],
            "pu",
            1e-6,
        )
        for (l, z) in enumerate(ls)
            drop=(z["r_pu"]*v["P_line"][l, t]+z["x_pu"]*v["Q_line"][l, t])/(
                e["S_base_MVA"]*e["v_ref_pu"]
            )
            record(
                "5-16",
                "electric",
                z["id"],
                t,
                v["v"][z["to"], t]-v["v"][z["from"], t]+drop,
                "pu",
                1e-6,
            )
            bt(
                "P-line-bound",
                "electric",
                z["id"],
                t,
                v["P_line"][l, t],
                -z["P_limit_MW"],
                z["P_limit_MW"],
                "MW",
                etol,
            )
            bt(
                "Q-line-bound",
                "electric",
                z["id"],
                t,
                v["Q_line"][l, t],
                -z["Q_limit_Mvar"],
                z["Q_limit_Mvar"],
                "Mvar",
                etol,
            )
        end
        for n in 1:N
            mi=mo=hs=hr=ms=ml=0.0
            for (p, z) in enumerate(ps)
                if z["to"]==n
                    mi+=z["m_kg_s"]
                    hs+=z["m_kg_s"]*v["τ_pipe_S"][p, t]
                end
                if z["from"]==n
                    mo+=z["m_kg_s"]
                    hr+=z["m_kg_s"]*v["τ_pipe_R"][p, t]
                end
            end
            for (s, z) in enumerate(ss)
                z["node"]==n || continue
                ms+=z["m_kg_s"]
                hs+=z["m_kg_s"]*v["τ_src"][s, t]
            end
            for (j, z) in enumerate(bs)
                z["heat_node"]==n || continue
                ml+=z["m_kg_s"]
                hr+=z["m_kg_s"]*v["τ_load_R"][j, t]
            end
            record("mass", "heat", n, t, mi+ms-mo-ml, "kg/s", 1e-6*(1+max(mi+ms, mo+ml)))
            record("5-20", "heat", n, t, v["τ_S"][n, t]-hs/(mo+ml), "K", 1e-4)
            record("5-21", "heat", n, t, v["τ_R"][n, t]-hr/(mi+ms), "K", 1e-4)
            bt("5-24-S", "heat", n, t, v["τ_S"][n, t], h["S_min_K"], h["S_max_K"], "K", 1e-4)
            bt("5-24-R", "heat", n, t, v["τ_R"][n, t], h["R_min_K"], h["R_max_K"], "K", 1e-4)
        end
        for (s, z) in enumerate(ss)
            gen=sum(
                dev["heat_ratio"]*v["P_DER"][g, t] for (g, dev) in enumerate(ds) if
                dev["kind"] in ("CHP", "EB") && dev["source_id"]==z["id"];
                init = 0.0,
            )
            record(
                "5-18",
                "heat",
                z["id"],
                t,
                gen-cp*z["m_kg_s"]*(v["τ_src"][s, t]-v["τ_R"][z["node"], t]),
                "MW",
                htol,
            )
            bt(
                "source-temperature",
                "heat",
                z["id"],
                t,
                v["τ_src"][s, t],
                z["T_min_K"],
                z["T_max_K"],
                "K",
                1e-4,
            )
        end
        for (j, z) in enumerate(bs)
            HD, PL, temp=v["H_D"][j, t], v["P_DH"][j, t], v["τ_IN"][j, t]
            record(
                "5-19",
                "heat",
                z["id"],
                t,
                HD-cp*z["m_kg_s"]*(v["τ_S"][z["heat_node"], t]-v["τ_load_R"][j, t]),
                "MW",
                htol,
            )
            bt("heat-nonnegative", "heat", z["id"], t, HD, 0, Inf, "MW", htol)
            bt("5-31", "electric", z["id"], t, PL, 0, z["P_DH_max_MW"], "MW", etol)
            bt(
                "load-return",
                "heat",
                z["id"],
                t,
                v["τ_load_R"][j, t],
                z["R_min_K"],
                z["R_max_K"],
                "K",
                1e-4,
            )
            previous=t==1 ? z["T_initial_K"] : v["τ_IN"][j, t-1]
            # 直接从MWh能量平衡回算；不复用建模侧η/U或温度更新函数。
            storage=z["C_MWh_K"]*(temp-previous)
            gain=dt*(HD+z["COP_DH"]*PL-z["G_MW_K"]*(temp-d["ambient_K"][t]))
            equivalent=(z["C_MWh_K"]*previous+dt*(HD+z["COP_DH"]*PL+z["G_MW_K"]*d["ambient_K"][t]))/(
                z["C_MWh_K"]+dt*z["G_MW_K"]
            )
            record("R5-D-building", "comfort", z["id"], t, temp-equivalent, "K", 1e-4)
            record("building-energy", "comfort", z["id"], t, storage-gain, "MWh", 1e-6*(1+hp*dt))
            bt("5-28", "comfort", z["id"], t, temp, z["T_min_K"], z["T_max_K"], "K", 1e-4)
            if t==T && z["terminal_rule"]=="initial"
                record("terminal", "comfort", z["id"], t, temp-z["T_initial_K"], "K", 1e-4)
            end
        end
        for (p, z) in enumerate(ps), side in ("S", "R")
            node=side=="S" ? z["from"] : z["to"]
            replay=r5_dispatch_pipe_replay(
                z,
                h,
                dt,
                t,
                v["τ_$side"][node, :],
                d["ambient_K"][t],
                side,
            )
            record(
                "5-25-26-$side",
                "heat",
                z["id"],
                t,
                v["τ_pipe_$side"][p, t]-replay.temperature,
                "K",
                1e-4,
            )
            record("transport-weight-$side", "heat", z["id"], t, replay.weight_sum-1, "1", 1e-6)
        end
        actual=a["P_DA_MW"][t]-v["P_PCC"][1, t]
        request=rt["alpha_up"][t]*a["R_up_MW"][t]-rt["alpha_down"][t]*a["R_down_MW"][t]
        record("R5-D-delivery", "delivery", "PCC", t, v["delivery"][1, t]-actual, "MW", etol)
        record(
            "5-3-epigraph",
            "delivery",
            "PCC",
            t,
            max(0.0, abs(request-actual)-v["mismatch"][1, t]),
            "MW",
            etol,
        )
        record(
            "5-3-exact",
            "auxiliary",
            "PCC",
            t,
            v["mismatch"][1, t]-abs(request-actual),
            "MW",
            etol,
        )
    end
    request=rt["alpha_up"] .* a["R_up_MW"]-rt["alpha_down"] .* a["R_down_MW"]
    actual=a["P_DA_MW"]-vec(v["P_PCC"])
    mis=abs.(request-actual)
    limit=rt["delta"]*dt*sum(a["R_up_MW"]+a["R_down_MW"])
    record(
        "5-4",
        "delivery",
        "window",
        0,
        max(0.0, dt*sum(v["mismatch"])-limit),
        "MWh",
        1e-6*(1+ep*dt*T),
    )
    cost_DA=dt*sum(
        a["energy_price"] .* a["P_DA_MW"]-a["up_price"] .* a["R_up_MW"]-a["down_price"] .*
                                                                        a["R_down_MW"],
    )
    cost_DER=dt*sum(
        r5_dispatch_device_cost(d, z)*v["P_DER"][g, t] for (g, z) in enumerate(ds), t in 1:T;
        init = 0.0,
    )
    cost_RT=-dt*sum(rt["price"] .* actual)
    penalty=dt*r5_dispatch_penalty(d)*sum(mis)
    total=cost_DA+cost_DER+cost_RT+penalty
    record(
        "5-5-cost",
        "cost",
        "total",
        0,
        get(r, "solver_objective", NaN)-total,
        r5_dispatch_currency(d),
        1e-6*max(1, abs(total)),
    )
    for (key, group) in (
        ("linear_electric_pass", "electric"),
        ("fixed_flow_heat_pass", "heat"),
        ("comfort_pass", "comfort"),
        ("delivery_pass", "delivery"),
        ("auxiliary_exact_pass", "auxiliary"),
        ("cost_pass", "cost"),
    )
        out[key]=all(x["pass"] for x in rows if x["group"]==group)
    end
    out["model_pass"]=all(
        out[k] for
        k in ("linear_electric_pass", "fixed_flow_heat_pass", "comfort_pass", "delivery_pass")
    )
    merge!(
        out,
        Dict(
            "operating_net_cost"=>total,
            "day_ahead_cost"=>cost_DA,
            "device_cost"=>cost_DER,
            "real_time_settlement"=>cost_RT,
            "delivery_penalty"=>penalty,
            "request_MW"=>request,
            "delivered_MW"=>actual,
            "mismatch_MW"=>mis,
            "mismatch_MWh"=>dt*sum(mis),
            "mismatch_limit_MWh"=>limit,
            "electric_scale_MW"=>ep,
            "heat_scale_MW"=>hp,
            "bound_certificate_scope"=>"Solver LP objective bound; no independent KKT certification in this batch",
        ),
    )
    bound=get(r, "solver_objective_bound", NaN)
    gap=isfinite(bound) ? max(0.0, total-bound)/max(1.0, abs(total), abs(bound)) : Inf
    out["relative_gap"]=gap
    out["valid_bound"]=isfinite(bound)&&bound<=total+1e-6*max(1, abs(total))
    out["optimality_pass"]=out["model_pass"]&&out["cost_pass"]&&out["auxiliary_exact_pass"]&&out["valid_bound"]&&gap<=1e-4
    out
end
