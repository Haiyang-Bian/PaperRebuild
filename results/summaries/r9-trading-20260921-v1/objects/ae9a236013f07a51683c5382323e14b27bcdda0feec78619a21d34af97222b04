"""
    validate_r4_heat_reconstruction(case, parent, reconstruction)

仅由保存数值独立回算逐管显热、损耗、质量/双网络焓平衡及温度边界。
检查父输入和父结果哈希；不复用JuMP表达式。通过仅支持声明的冻结损耗稳态模型，
不认证水压、动态或真实温度相关散热。温度混合另用加权平均回代，A1温度门槛1e-4K。
"""
function validate_r4_heat_reconstruction(c, parent, r)
    r["input_sha256"]==c.sha256 || error("重构输入哈希不符")
    r["parent_sha256"]==r4_heat_parent_hash(parent) || error("父结果已改变")
    spec=r4_heat_spec(r["spec"])
    z=r4_heat_data(c, parent)
    h=c.data["heat"]
    rows=Dict{String,Any}[]
    row(id, i, t, res, unit, tol) = push!(
        rows,
        Dict(
            "id"=>id,
            "index"=>i,
            "time"=>t,
            "residual"=>abs(res),
            "unit"=>unit,
            "tolerance"=>tol,
            "pass"=>abs(res)<=tol,
        ),
    )
    bound(id, i, t, x, lo, hi, unit, tol) = row(id, i, t, max(lo-x, x-hi, 0), unit, tol)
    haskey(r, "values") || return Dict("checked"=>false, "pass"=>false, "rows"=>rows)
    v=r["values"]
    T=z.T
    n=length(z.pipes)
    V=Dict(
        k=>r4_heat_matrix(v, k, k=="m_pipe" ? n : 3, T) for k in ("m_pipe", "m_source", "m_load")
    )
    if spec.level==:mixing
        for k in ("τ_S", "τ_R", "τ_source", "τ_load", "τ_S_out", "τ_R_out")
            V[k]=r4_heat_matrix(v, k, endswith(k, "_out") ? n : 3, T)
            bounds=k in ("τ_S", "τ_source", "τ_S_out") ? spec.supply_K : spec.return_K
            for i in axes(V[k], 1), t in 1:T
                bound("temperature_"*k, i, t, V[k][i, t], bounds..., "K", 1e-4)
            end
        end
    end
    Δmin=max(0, spec.supply_K[1]-spec.return_K[2])
    Δmax=spec.supply_K[2]-spec.return_K[1]
    for t in 1:T
        for (p, pipe) in enumerate(z.pipes)
            m=V["m_pipe"][p, t]
            i, j=pipe["from"], pipe["to"]
            bound("pipe_mass", p, t, m, 0, pipe["flow_max"]*z.on[p, t], "kg/s", z.f_tol)
            row(
                "frozen_loss",
                p,
                t,
                z.q["H_in"][p, t]-z.q["H_out"][p, t]-z.Ls[p, t]-z.Lr[p, t],
                "MW",
                z.p_tol,
            )
            spec.fixed_mass && row("fixed_mass_pipe", p, t, m-z.q["m_pipe"][p, t], "kg/s", z.f_tol)
            for key in ("H_in", "H_out")
                bound("R4-HC1_"*key, p, t, z.q[key][p, t], z.cp*Δmin*m, z.cp*Δmax*m, "MW", z.p_tol)
            end
            for (loss, span) in (
                (z.Ls[p, t], spec.supply_K[2]-spec.supply_K[1]),
                (z.Lr[p, t], spec.return_K[2]-spec.return_K[1]),
            )
                row("loss_mass_envelope", p, t, max(loss-z.cp*span*m, 0), "MW", z.p_tol)
            end
            if spec.level==:mixing
                S=V["τ_S"][i, t]
                R=V["τ_R"][j, t]
                So=V["τ_S_out"][p, t]
                Ro=V["τ_R_out"][p, t]
                row("R4-HC1_in", p, t, z.cp*m*(S-Ro)-z.q["H_in"][p, t], "MW", z.p_tol)
                row("R4-HC1_out", p, t, z.cp*m*(So-R)-z.q["H_out"][p, t], "MW", z.p_tol)
                row("R4-HC2_supply", p, t, z.cp*m*(S-So)-z.Ls[p, t], "MW", z.p_tol)
                row("R4-HC2_return", p, t, z.cp*m*(R-Ro)-z.Lr[p, t], "MW", z.p_tol)
            end
        end
        for i in 1:3
            inc=findall(p->p["to"]==i, z.pipes)
            out=findall(p->p["from"]==i, z.pipes)
            ms, ml=V["m_source"][i, t], V["m_load"][i, t]
            mi=sum(V["m_pipe"][p, t] for p in inc; init = 0)
            mo=sum(V["m_pipe"][p, t] for p in out; init = 0)
            row("R4-HC5_mass", i, t, ms+mi-ml-mo, "kg/s", z.f_tol)
            row(
                "frozen_node_heat",
                i,
                t,
                z.q["H_src"][i, t]-z.q["H_D"][i, t] +
                sum(z.q["H_out"][p, t] for p in inc; init = 0) -
                sum(z.q["H_in"][p, t] for p in out; init = 0),
                "MW",
                z.p_tol,
            )
            for (k, Hkey, port) in (("m_source", "H_src", "source"), ("m_load", "H_D", "load"))
                m=V[k][i, t]
                H=z.q[Hkey][i, t]
                bound(
                    "port_mass",
                    i,
                    t,
                    m,
                    0,
                    c.data["actors"][i]["port_flow_max"],
                    "kg/s",
                    z.f_tol,
                )
                spec.fixed_mass && row("fixed_"*k, i, t, m-z.q[k][i, t], "kg/s", z.f_tol)
                bound(
                    "R4-HC3_envelope",
                    i,
                    t,
                    H,
                    z.cp*max(Δmin, h[port*"_delta_min"])*m,
                    z.cp*min(Δmax, h[port*"_delta_max"])*m,
                    "MW",
                    z.p_tol,
                )
            end
            if spec.level==:mixing
                S, R=V["τ_S"][i, t], V["τ_R"][i, t]
                Ss, Rl=V["τ_source"][i, t], V["τ_load"][i, t]
                row("R4-HC3_source", i, t, z.cp*ms*(Ss-R)-z.q["H_src"][i, t], "MW", z.p_tol)
                row("R4-HC3_load", i, t, z.cp*ml*(S-Rl)-z.q["H_D"][i, t], "MW", z.p_tol)
                for (delta, Hkey, port) in ((Ss-R, "H_src", "source"), (S-Rl, "H_D", "load"))
                    z.q[Hkey][i, t]>z.p_tol && bound(
                        "port_delta_"*port,
                        i,
                        t,
                        delta,
                        h[port*"_delta_min"],
                        h[port*"_delta_max"],
                        "K",
                        1e-4,
                    )
                end
                Esi=ms*(Ss-273.15)+sum(
                    V["m_pipe"][p, t]*(V["τ_S_out"][p, t]-273.15) for p in inc;
                    init = 0,
                )
                Eri=ml*(Rl-273.15)+sum(
                    V["m_pipe"][p, t]*(V["τ_R_out"][p, t]-273.15) for p in out;
                    init = 0,
                )
                row("R4-HC4_supply", i, t, z.cp*(Esi-(ml+mo)*(S-273.15)), "MW", z.p_tol)
                row("R4-HC4_return", i, t, z.cp*(Eri-(ms+mi)*(R-273.15)), "MW", z.p_tol)
                # 正质量输入时重算混合温度；不能用小流量下功率残差掩盖温度误差。
                ms+mi>z.f_tol &&
                    row("mix_temperature_supply", i, t, Esi/(ms+mi)+273.15-S, "K", 1e-4)
                ml+mo>z.f_tol &&
                    row("mix_temperature_return", i, t, Eri/(ml+mo)+273.15-R, "K", 1e-4)
            end
        end
    end
    Dict(
        "checked"=>true,
        "pass"=>all(x["pass"] for x in rows),
        "temperature_checked"=>spec.level==:mixing,
        "max_normalized_residual"=>maximum(x["residual"]/x["tolerance"] for x in rows),
        "rows"=>rows,
    )
end
