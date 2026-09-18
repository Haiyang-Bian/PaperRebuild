function r4_thermal_constraints!(model, v, c, options)
    s=options.spec
    mass=options.mass_schedule
    d=c.data
    h=d["heat"]
    pipes=h["pipes"]
    T=d["T"]
    n=length(pipes)
    C=h["cp"]/1e6*100
    # 温度以0°C为共同焓基准并缩放100K，保存时转换回K。
    for (key, count, band) in (
        ("τ_S", 3, s.supply_K),
        ("τ_R", 3, s.return_K),
        ("τ_source", 3, s.supply_K),
        ("τ_load", 3, s.return_K),
        ("τ_S_out", n, s.supply_K),
        ("τ_R_out", n, s.return_K),
    )
        v[key]=@variable(
            model,
            [1:count, 1:T],
            lower_bound=(band[1]-273.15)/100,
            upper_bound=(band[2]-273.15)/100,
            base_name=key
        )
    end
    if mass!==nothing
        for (key, values) in mass, i in axes(values, 1), t in 1:T
            fix(v[key][i, t], values[i, t]; force = true)
        end
    end
    M(key, i, t) = mass===nothing ? v[key][i, t] : mass[key][i, t]
    if s.loss==:exponential && mass===nothing
        v["m_safe"]=@variable(model, [1:n, 1:T], lower_bound=0, base_name="m_safe")
        v["attenuation"]=@variable(
            model,
            [1:n, 1:T],
            lower_bound=0,
            upper_bound=1,
            base_name="attenuation"
        )
    end
    for (p, pipe) in enumerate(pipes), t in 1:T
        i, j=pipe["from"], pipe["to"]
        on=v["u_H_arc"][p, t]
        m=M("m_pipe", p, t)
        @constraint(model, m>=options.min_flow[p]*on)
        # R4-T3：供回管视为一对，入口/出口交付热量不等同于单侧焓。
        @constraint(model, v["H_in"][p, t]==C*m*(v["τ_S"][i, t]-v["τ_R_out"][p, t]))
        @constraint(model, v["H_out"][p, t]==C*m*(v["τ_S_out"][p, t]-v["τ_R"][j, t]))
        UA=pipe["U_W_mK"]*pipe["length_m"]
        if s.loss==:reference
            Ls=UA*(pipe["S_ref_K"]-pipe["ambient_K"])/1e6
            Lr=UA*(pipe["R_ref_K"]-pipe["ambient_K"])/1e6
            @constraint(model, C*m*(v["τ_S"][i, t]-v["τ_S_out"][p, t])==Ls*on)
            @constraint(model, C*m*(v["τ_R"][j, t]-v["τ_R_out"][p, t])==Lr*on)
        else
            if mass===nothing
                ms=v["m_safe"][p, t]
                amin=options.min_flow[p]
                set_lower_bound(ms, amin)
                set_upper_bound(ms, max(amin, pipe["flow_max"]))
                @constraint(model, ms==m+amin*(1-on))
                a=v["attenuation"][p, t]
                @constraint(model, a==exp(-UA/(h["cp"]*ms)))
            else
                a=exp(-UA/(h["cp"]*max(m, options.min_flow[p])))
            end
            # R4-T2：只对运行弧约束出口。停流温度为占位值，不代表管内储热状态。
            Ta=(pipe["ambient_K"]-273.15)/100
            for (tin, tout, band) in (
                (v["τ_S"][i, t], v["τ_S_out"][p, t], s.supply_K),
                (v["τ_R"][j, t], v["τ_R_out"][p, t], s.return_K),
            )
                big=(band[2]-pipe["ambient_K"])/100
                gap=tout-Ta-(tin-Ta)*a
                @constraint(model, gap<=big*(1-on))
                @constraint(model, gap>=-big*(1-on))
            end
        end
    end
    for i in 1:3, t in 1:T
        ms, ml=M("m_source", i, t), M("m_load", i, t)
        @constraint(model, v["H_src"][i, t]==C*ms*(v["τ_source"][i, t]-v["τ_R"][i, t]))
        @constraint(model, v["H_D"][i, t]==C*ml*(v["τ_S"][i, t]-v["τ_load"][i, t]))
        inc=findall(p->p["to"]==i, pipes)
        out=findall(p->p["from"]==i, pipes)
        supply=ms+sum(M("m_pipe", p, t) for p in inc; init = 0)
        ret=ml+sum(M("m_pipe", p, t) for p in out; init = 0)
        Es=ms*v["τ_source"][i, t]+sum(M("m_pipe", p, t)*v["τ_S_out"][p, t] for p in inc; init = 0) -
           supply*v["τ_S"][i, t]
        Er=ml*v["τ_load"][i, t]+sum(M("m_pipe", p, t)*v["τ_R_out"][p, t] for p in out; init = 0) -
           ret*v["τ_R"][i, t]
        # R4-T4：独立的供、回水混合。内带1e-5K，最终A1仍为1e-4K。
        @constraint(model, Es<=supply*1e-7)
        @constraint(model, Es>=-supply*1e-7)
        @constraint(model, Er<=ret*1e-7)
        @constraint(model, Er>=-ret*1e-7)
    end
    nothing
end

"""
    build_r4_thermal(case; spec=R4ThermalSpec(), optimizer=nothing, modes=nothing,
        electric_schedule=nothing, heat_open=nothing, heat_active=nothing, mass_schedule=nothing)

构建集中式R4-T1至T6模型，不求解/写文件。源荷控制联合优化，保留原成本与设备边界。
heat_active为6×T的0/1实际循环方向，可全零；日阀门树仍须连通。
固定流量为含m_pipe/m_source/m_load的字典(kg/s)，代入系数后形成可公开验证的凸特例。
未固定流量时含非凸双线性关系，指数损耗还含非线性函数；不宣称MISOCP。
"""
function build_r4_thermal(
    c::R4Case;
    spec = R4ThermalSpec(),
    optimizer = nothing,
    modes = nothing,
    electric_schedule = nothing,
    heat_open = nothing,
    heat_active = nothing,
    mass_schedule = nothing,
)
    options=r4_thermal_options(c, spec, electric_schedule, heat_open, heat_active, mass_schedule)
    build_r4_model(c; spec = R4Spec(electric = spec.electric), optimizer, modes, options...)
end
