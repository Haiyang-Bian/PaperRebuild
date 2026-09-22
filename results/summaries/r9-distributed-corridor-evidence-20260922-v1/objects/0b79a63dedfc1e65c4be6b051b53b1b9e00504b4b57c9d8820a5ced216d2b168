function r4_validate_thermal!(row, bound, c, result)
    spec=r4_thermal_spec(result["thermal"])
    spec.electric==Symbol(result["spec"]["electric"]) || error("电网版本不一致")
    spec.policy==Symbol(result["reconfiguration"]["policy"]) || error("策略版本不一致")
    d=c.data
    h=d["heat"]
    cp=h["cp"]/1e6
    T=d["T"]
    pipes=h["pipes"]
    n=length(pipes)
    s=result["values"]
    for (key, count, band) in (
        ("τ_S", 3, spec.supply_K),
        ("τ_R", 3, spec.return_K),
        ("τ_source", 3, spec.supply_K),
        ("τ_load", 3, spec.return_K),
        ("τ_S_out", n, spec.supply_K),
        ("τ_R_out", n, spec.return_K),
    )
        a=r4_heat_matrix(s, key, count, T)
        for i in 1:count, t in 1:T
            bound("R4-T5_temperature", "heat", key*string(i), t, a[i, t], band..., "K", 1e-4)
        end
    end
    p_tol=1e-6*(1+d["electric"]["grid_max"])
    f_tol=1e-6*(1+maximum(p["flow_max"] for p in pipes))
    mins=r4_thermal_min_flow(c, spec)
    V(k, i, t) = s[k][i][t]
    savedmass=get(result, "mass_schedule", nothing)
    fixed=r4_thermal_mass(c, savedmass)
    if fixed!==nothing
        for (key, a) in fixed, i in axes(a, 1), t in 1:T
            row("R4-T6_fixed_mass", "heat", key*string(i), t, V(key, i, t)-a[i, t], "kg/s", f_tol)
        end
    end
    if spec.loss==:exponential && fixed===nothing
        r4_heat_matrix(s, "m_safe", n, T)
        r4_heat_matrix(s, "attenuation", n, T)
    end
    for (p, pipe) in enumerate(pipes), t in 1:T
        i, j=pipe["from"], pipe["to"]
        on=V("u_H_arc", p, t)
        m=V("m_pipe", p, t)
        bound("R4-T1_active_mass", "heat", p, t, m, mins[p]*on, pipe["flow_max"]*on, "kg/s", f_tol)
        Si, Ro, So, Rj=V("τ_S", i, t), V("τ_R_out", p, t), V("τ_S_out", p, t), V("τ_R", j, t)
        row("R4-T3_in", "heat", p, t, V("H_in", p, t)-cp*m*(Si-Ro), "MW", p_tol)
        row("R4-T3_out", "heat", p, t, V("H_out", p, t)-cp*m*(So-Rj), "MW", p_tol)
        UA=pipe["U_W_mK"]*pipe["length_m"]
        Ta=pipe["ambient_K"]
        if spec.loss==:reference
            Ls=UA*(pipe["S_ref_K"]-Ta)/1e6*on
            Lr=UA*(pipe["R_ref_K"]-Ta)/1e6*on
        else
            if on>0.5 && m>0
                # 独立按保存的实际温度/流量回算，不使用模型辅助衰减量。
                alpha=exp(-UA/(h["cp"]*m))
                Ls=cp*m*(Si-Ta)*(1-alpha)
                Lr=cp*m*(Rj-Ta)*(1-alpha)
            elseif on>0.5
                Ls, Lr=Inf, Inf
            else
                Ls, Lr=0.0, 0.0
            end
            if fixed===nothing
                ms=V("m_safe", p, t)
                row("R4-T2_safe_mass", "heat", p, t, ms-m-mins[p]*(1-on), "kg/s", f_tol)
                bound(
                    "R4-T2_safe_bounds",
                    "heat",
                    p,
                    t,
                    ms,
                    mins[p],
                    max(mins[p], pipe["flow_max"]),
                    "kg/s",
                    f_tol,
                )
                a=ms>0 ? exp(-UA/(h["cp"]*ms)) : Inf
                row("R4-T2_attenuation", "heat", p, t, V("attenuation", p, t)-a, "1", 1e-6)
            end
        end
        row("R4-T2_supply_loss", "heat", p, t, cp*m*(Si-So)-Ls, "MW", p_tol)
        row("R4-T2_return_loss", "heat", p, t, cp*m*(Rj-Ro)-Lr, "MW", p_tol)
        row("R4-T2_total_loss", "heat", p, t, V("H_in", p, t)-V("H_out", p, t)-Ls-Lr, "MW", p_tol)
        if on>0.5
            row("R4-T2_supply_temperature", "heat", p, t, m>0 ? So-(Si-Ls/(cp*m)) : Inf, "K", 1e-4)
            row("R4-T2_return_temperature", "heat", p, t, m>0 ? Ro-(Rj-Lr/(cp*m)) : Inf, "K", 1e-4)
        end
    end
    for i in 1:3, t in 1:T
        ms, ml=V("m_source", i, t), V("m_load", i, t)
        row(
            "R4-T3_source",
            "heat",
            i,
            t,
            V("H_src", i, t)-cp*ms*(V("τ_source", i, t)-V("τ_R", i, t)),
            "MW",
            p_tol,
        )
        row(
            "R4-T3_load",
            "heat",
            i,
            t,
            V("H_D", i, t)-cp*ml*(V("τ_S", i, t)-V("τ_load", i, t)),
            "MW",
            p_tol,
        )
        inc=findall(p->p["to"]==i, pipes)
        out=findall(p->p["from"]==i, pipes)
        for (name, total, energy, target) in (
            (
                "supply",
                ms+sum(V("m_pipe", p, t) for p in inc; init = 0),
                ms*V("τ_source", i, t)+sum(
                    V("m_pipe", p, t)*V("τ_S_out", p, t) for p in inc;
                    init = 0,
                ),
                V("τ_S", i, t),
            ),
            (
                "return",
                ml+sum(V("m_pipe", p, t) for p in out; init = 0),
                ml*V("τ_load", i, t)+sum(
                    V("m_pipe", p, t)*V("τ_R_out", p, t) for p in out;
                    init = 0,
                ),
                V("τ_R", i, t),
            ),
        )
            row("R4-T4_"*name*"_enthalpy", "heat", i, t, cp*(energy-total*target), "MW", p_tol)
            total>1e-10 &&
                row("R4-T4_"*name*"_mixing", "heat", i, t, energy/total-target, "K", 1e-4)
        end
    end
    nothing
end

"""
    validate_r4_thermal(case, result)

从保存的K、kg/s、MW数值独立核查R4-T1至T6、设备、电网、动作与账本。
指数衰减由实际正流量重新计算；活动管出口与混合温度均按1e-4K验收，避免小流量掩盖温差。
停流的温度占位值只检查范围，不认证管内储热。模型、原电网和费用状态仍分别报告。
"""
function validate_r4_thermal(c::R4Case, result)
    result["spec"]["version"]=="r4_thermal_checked_v1" || error("热模型版本错误")
    r4_thermal_spec(result["thermal"])
    validate_r4_solution(c, result)
end
