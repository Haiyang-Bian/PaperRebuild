# R7-D4：给定流量后温度输运为仿射算子；求解器只接收系数，验证器重新做水团回放。
function r7_normal_pipe_replay(d, p, side, w, inlet)
    h=d["heat"]
    T=d["periods"]
    s=r7_normal_initial(d, p, side, w)
    states=R7PipeState[s]
    steps=Any[]
    for t in 1:T
        x=r7_pipe_step(
            s;
            mass_flow_kg_s = p["normal_flow_kg_s"][t],
            inlet_K = inlet[t],
            ambient_K = h["ambient_K"][t],
            dt_h = d["dt_h"],
            cp_J_kgK = h["c_J_kgK"],
            UA_W_K = p["UA_$(side)_W_K"],
            reference_K = h["$(side)_min_K"],
        )
        push!(steps, x)
        s=x.state
        push!(states, s)
    end
    (;
        states,
        steps,
        outlet = [x.outlet_mean_K for x in steps],
        energy = [
            r7_pipe_inventory(s; cp_J_kgK = h["c_J_kgK"], reference_K = h["$(side)_min_K"]).relative_heat_MWh
            for s in states
        ],
    )
end

function r7_normal_pipe_map(d, p, side)
    T, W=d["periods"], length(d["probabilities"])
    # 热方程线性叠加：用相同初态的1 K入口为基准，再施加100 K单位基向量。
    # 这是已证明仿射算子的系数提取，不是最优值的有限差分或流量导数。
    base=[r7_normal_pipe_replay(d, p, side, w, ones(T)) for w in 1:W]
    A=zeros(T, T)
    E=zeros(T+1, T)
    for k in 1:T
        pulse=ones(T)
        pulse[k]+=100
        x=r7_normal_pipe_replay(d, p, side, 1, pulse)
        A[:, k]=(x.outlet-base[1].outlet)/100
        E[:, k]=(x.energy-base[1].energy)/100
    end
    b=hcat((x.outlet-A*ones(T) for x in base)...)
    eb=hcat((x.energy-E*ones(T) for x in base)...)
    if d["thermal_model"]=="node_method_fixed_v1"
        h=d["heat"]
        flow=first(p["normal_flow_kg_s"])
        # 以A=1,L=V表示相同M与UA；J只依赖UA/M，未猜测原管径。
        kernel=fixed_flow_kernel(
            flow,
            h["rho_kg_m3"],
            1.0,
            p["volume_$(side)_m3"],
            d["dt_h"],
            p["UA_$(side)_W_K"]/p["volume_$(side)_m3"];
            c_w = h["c_J_kgK"]/1000,
        )
        fill!(A, 0)
        fill!(b, 0)
        hist=p["history_$(side)_K"]
        for t in 1:T, w in 1:W
            b[t, w]=(1-kernel.J)*h["ambient_K"][t]
            for (lag, weight) in zip(kernel.lags, kernel.weights)
                if t-lag>0
                    w==1 && (A[t, t-lag]+=kernel.J*weight)
                else
                    b[t, w]+=kernel.J*weight*hist[end+t-lag][w]
                end
            end
        end
    end
    (; A, b, E, eb)
end
