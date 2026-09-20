"""
    r7_linked_pipe_replay(case, spec, pair, pipe, side, scenario, normal_inlet, event_inlet)

R7-L1连续回放同一管道的灾前历史和灾后控制，温度K、质量kg、流量kg/s、时间h。
normal_inlet恰有event_start-1项，event_inlet有periods*substeps项；不读取或猜测未来正常入口。
返回事件起点至结束的空间状态和输运步；正常与恢复均复用已核查塞流参考，保留原平均节点假设。
"""
function r7_linked_pipe_replay(c, s, pair, a, side, w, normal_inlet, event_inlet)
    d=c.normal.data
    h=d["heat"]
    e=c.specification["events"][pair.event]
    p=h["pipes"][a]
    side in ("S", "R") || error("管侧非法")
    n=s["substeps"]
    length(normal_inlet)==e["event_start"]-1 && length(event_inlet)==e["periods"]*n ||
        error("串联入口历史长度错误")
    state=r7_normal_initial(d, p, side, w)
    for t in eachindex(normal_inlet)
        state=r7_pipe_step(
            state;
            mass_flow_kg_s = p["normal_flow_kg_s"][t],
            inlet_K = normal_inlet[t],
            ambient_K = h["ambient_K"][t],
            dt_h = d["dt_h"],
            cp_J_kgK = h["c_J_kgK"],
            UA_W_K = p["UA_$(side)_W_K"],
            reference_K = h["$(side)_min_K"],
        ).state
    end
    flow=r7_linked_flow(s, pair)["m_pipe"]
    states=R7PipeState[state]
    steps=Any[]
    for k in eachindex(event_inlet)
        t=cld(k, n)
        x=r7_pipe_step(
            state;
            mass_flow_kg_s = flow[a, t],
            inlet_K = event_inlet[k],
            ambient_K = h["ambient_K"][e["event_start"]+t-1],
            dt_h = d["dt_h"]/n,
            cp_J_kgK = h["c_J_kgK"],
            UA_W_K = p["UA_$(side)_W_K"],
            reference_K = h["$(side)_min_K"],
        )
        push!(steps, x)
        state=x.state
        push!(states, state)
    end
    (; states, steps)
end

"""
    r7_linked_pipe_map(case, spec, pair, pipe, side, scenario; deadline=Inf)

提取R7-L1的仿射输运矩阵：列为灾前入口、灾后入口；行为出口均温、逐管库存、全部空间段端温。
用同一初态的线性算子基向量提取系数，不是最优值差分；给定流量与时间划分决定分段几何。
事件初始库存与空间温度是灾前变量的函数，不能独立优化或替换成同均温的其他分布。
"""
function r7_linked_pipe_map(c, s, pair, a, side, w; deadline = Inf)
    e=c.specification["events"][pair.event]
    H=e["event_start"]-1
    K=e["periods"]*s["substeps"]
    context=(h = c.normal.data["heat"], K = K)
    baseline=fill(context.h["$(side)_reference_K"], H+K)
    function values(input)
        time()<deadline || error("linked_build_deadline")
        sim=r7_linked_pipe_replay(c, s, pair, a, side, w, input[1:H], input[(H+1):end])
        r7_thermal_samples(sim, context, side)
    end
    y0=values(baseline)
    A=zeros(length(y0), H+K)
    for k in eachindex(baseline)
        pulse=copy(baseline)
        pulse[k]+=100
        y=values(pulse)
        length(y)==length(y0) || error("空间采样几何不应依赖入口温度")
        A[:, k]=(y-y0)/100
    end
    (; A, b = y0-A*baseline, history_columns = H, event_columns = K)
end
