"""
    build_r4_heat_reconstruction(case, parent; spec, optimizer=nothing)

构建固定父调度的热状态相容性问题，不求解、不写文件。
R4-HC1–HC5：逐管显热、分别冻结的供回损耗、端口转换、双网络混合及质量守恒。
既有MW与kg/s A1不变；建模带宽用A1的十分之一吸收父存档数值误差。
变量温度内部用(τ-273.15)/100，输出再转回K。envelope是线性必要条件，
mixing含流量乘温度的二次等式带，不称凸模型。
"""
function build_r4_heat_reconstruction(
    c::R4Case,
    parent;
    spec = R4HeatCompatibilitySpec(),
    optimizer = nothing,
)
    d=c.data
    z=r4_heat_data(c, parent)
    h=d["heat"]
    T=z.T
    n=length(z.pipes)
    model=optimizer===nothing ? Model() : Model(optimizer)
    v=Dict{String,Any}()
    for (k, N) in (("m_pipe", n), ("m_source", 3), ("m_load", 3))
        v[k]=@variable(model, [1:N, 1:T], lower_bound=0, base_name=k)
    end
    band(expr, target, tol) = @constraint(model, -tol<=expr-target<=tol)
    dp=z.p_tol/10
    df=z.f_tol/10
    Δmin=max(0, spec.supply_K[1]-spec.return_K[2])
    Δmax=spec.supply_K[2]-spec.return_K[1]
    for t in 1:T
        for (p, pipe) in enumerate(z.pipes)
            m=v["m_pipe"][p, t]
            set_upper_bound(m, pipe["flow_max"]*z.on[p, t])
            spec.fixed_mass && band(m, z.q["m_pipe"][p, t], df)
            set_start_value(m, clamp(z.q["H_in"][p, t]/(z.cp*40), 0, pipe["flow_max"]*z.on[p, t]))
            for k in ("H_in", "H_out")
                H=z.q[k][p, t]
                @constraint(model, z.cp*Δmin*m<=H+dp)
                @constraint(model, z.cp*Δmax*m>=H-dp)
            end
            # 有限温度带下，供回管各自的热损失都必须由正质量流承担。
            @constraint(model, z.cp*(spec.supply_K[2]-spec.supply_K[1])*m>=z.Ls[p, t]-dp)
            @constraint(model, z.cp*(spec.return_K[2]-spec.return_K[1])*m>=z.Lr[p, t]-dp)
        end
        for i in 1:3
            for (k, Hkey, port) in (("m_source", "H_src", "source"), ("m_load", "H_D", "load"))
                m=v[k][i, t]
                H=z.q[Hkey][i, t]
                set_upper_bound(m, d["actors"][i]["port_flow_max"])
                spec.fixed_mass && band(m, z.q[k][i, t], df)
                set_start_value(m, clamp(H/(z.cp*30), 0, d["actors"][i]["port_flow_max"]))
                @constraint(model, z.cp*max(Δmin, h[port*"_delta_min"])*m<=H+dp)
                @constraint(model, z.cp*min(Δmax, h[port*"_delta_max"])*m>=H-dp)
            end
            inc=findall(p->p["to"]==i, z.pipes)
            out=findall(p->p["from"]==i, z.pipes)
            @constraint(
                model,
                v["m_source"][i, t]+sum(v["m_pipe"][p, t] for p in inc; init = 0) ==
                v["m_load"][i, t]+sum(v["m_pipe"][p, t] for p in out; init = 0)
            )
        end
    end
    if spec.level==:mixing
        for (k, N, bounds) in (
            ("τ_S", 3, spec.supply_K),
            ("τ_R", 3, spec.return_K),
            ("τ_source", 3, spec.supply_K),
            ("τ_load", 3, spec.return_K),
            ("τ_S_out", n, spec.supply_K),
            ("τ_R_out", n, spec.return_K),
        )
            v[k]=@variable(model, [1:N, 1:T], base_name=k)
            for x in v[k]
                set_lower_bound(x, (bounds[1]-273.15)/100)
                set_upper_bound(x, (bounds[2]-273.15)/100)
                set_start_value(x, (sum(bounds)/2-273.15)/100)
            end
        end
        C=100*z.cp
        for t in 1:T
            for (p, pipe) in enumerate(z.pipes)
                i, j=pipe["from"], pipe["to"]
                m=v["m_pipe"][p, t]
                # H_in位于供水入口/回水出口截面；H_out位于供水出口/回水入口。
                band(C*m*(v["τ_S"][i, t]-v["τ_R_out"][p, t]), z.q["H_in"][p, t], dp)
                band(C*m*(v["τ_S_out"][p, t]-v["τ_R"][j, t]), z.q["H_out"][p, t], dp)
                band(C*m*(v["τ_S"][i, t]-v["τ_S_out"][p, t]), z.Ls[p, t], dp)
                band(C*m*(v["τ_R"][j, t]-v["τ_R_out"][p, t]), z.Lr[p, t], dp)
            end
            for i in 1:3
                ms=v["m_source"][i, t]
                ml=v["m_load"][i, t]
                band(C*ms*(v["τ_source"][i, t]-v["τ_R"][i, t]), z.q["H_src"][i, t], dp)
                band(C*ml*(v["τ_S"][i, t]-v["τ_load"][i, t]), z.q["H_D"][i, t], dp)
                for (diff, Hkey, port) in (
                    (v["τ_source"][i, t]-v["τ_R"][i, t], "H_src", "source"),
                    (v["τ_S"][i, t]-v["τ_load"][i, t], "H_D", "load"),
                )
                    if z.q[Hkey][i, t]>z.p_tol
                        @constraint(model, h[port*"_delta_min"]/100<=diff<=h[port*"_delta_max"]/100)
                    end
                end
                inc=findall(p->p["to"]==i, z.pipes)
                out=findall(p->p["from"]==i, z.pipes)
                # 以0°C为共同焓基准；质量守恒使基准选择不改变热平衡。
                mi=ms+sum(v["m_pipe"][p, t] for p in inc; init = 0)
                mr=ml+sum(v["m_pipe"][p, t] for p in out; init = 0)
                Es=ms*v["τ_source"][i, t] +
                   sum(v["m_pipe"][p, t]*v["τ_S_out"][p, t] for p in inc; init = 0)-mi*v["τ_S"][
                    i,
                    t,
                ]
                Er=ml*v["τ_load"][i, t] +
                   sum(v["m_pipe"][p, t]*v["τ_R_out"][p, t] for p in out; init = 0)-mr*v["τ_R"][
                    i,
                    t,
                ]
                # 内部温度尺度100K；同时限制混合温度误差，避免小流量隐藏温差。
                @constraint(model, Es<=mi*1e-7)
                @constraint(model, Es>=-mi*1e-7)
                @constraint(model, Er<=mr*1e-7)
                @constraint(model, Er>=-mr*1e-7)
            end
        end
    end
    @objective(model, Min, 0)
    (;
        model,
        variables = v,
        spec,
        formula_ids = ["R4-HC1", "R4-HC2", "R4-HC3", "R4-HC4", "R4-HC5"],
        constraint_types = string.(list_of_constraint_types(model)),
    )
end
