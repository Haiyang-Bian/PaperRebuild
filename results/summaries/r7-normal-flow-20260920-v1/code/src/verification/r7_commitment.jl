"""
    validate_r7_chp(spec, values)

独立核验灾前CHP数值。以逐段实际持续小时数检查最短启停，不复用建模侧滑动求和。
沿用A1容量、爬坡和二值门槛；重算启动/期望运行费用并返回末端尚需延续的时长。
只证明该设备约束块，不认证网络、完整灾前目标最优性或未来灾后调度。
"""
function validate_r7_chp(s::R7CHPSpec, values::AbstractDict)
    r7_chp_assert(s)
    d=s.data
    T, W, dt=d["periods"], length(d["probabilities"]), d["dt_h"]
    shape=Dict(
        "u_CHP"=>(T,),
        "ν_on"=>(T,),
        "ν_off"=>(T,),
        "P_CHP"=>(T, W),
        "Q_CHP"=>(T, W),
        "H_CHP"=>(T, W),
    )
    Set(keys(values))==Set(keys(shape)) || error("CHP值字段不完整")
    all(size(values[k])==size_ && all(isfinite, values[k]) for (k, size_) in shape) ||
        error("CHP值形状或有限性错误")
    rows=Dict{String,Any}[]
    function rec(id, t, w, res, unit, tol)
        push!(
            rows,
            Dict(
                "formula"=>id,
                "t"=>t,
                "scenario"=>w,
                "residual"=>abs(Float64(res)),
                "unit"=>unit,
                "tolerance"=>tol,
                "pass"=>abs(res)<=tol,
            ),
        )
    end
    scale=max(1.0, d["P_max_MW"], d["Q_max_Mvar"], d["heat_ratio"]*d["P_max_MW"])
    pt=1e-6*(1+scale)
    u, on, off, P, Q, H=(values[k] for k in ("u_CHP", "ν_on", "ν_off", "P_CHP", "Q_CHP", "H_CHP"))
    previous_state=d["previous_commitment"]
    age=d["previous_duration_h"]
    before=Float64(previous_state)
    for t in 1:T
        for a in (u, on, off)
            rec("R7-N1", t, 0, min(abs(a[t]), abs(a[t]-1)), "1", 1e-6)
        end
        rec("R7-N1", t, 0, on[t]-max(u[t]-before, 0), "1", 1e-6)
        rec("R7-N1", t, 0, off[t]-max(before-u[t], 0), "1", 1e-6)
        state=u[t]>=0.5 ? 1 : 0
        if state!=previous_state
            required=d[previous_state==1 ? "min_on_h" : "min_off_h"]
            rec("R7-N2/N3", t, 0, max(0, required-age), "h", 1e-6*(1+dt))
            age=0.0
        end
        previous_state=state
        age+=dt
        for w in 1:W
            for (id, a, lo, hi, unit) in (
                ("6-2", P, d["P_min_MW"], d["P_max_MW"], "MW"),
                ("6-3", Q, d["Q_min_Mvar"], d["Q_max_Mvar"], "Mvar"),
            )
                rec(id, t, w, max(0, lo*u[t]-a[t, w], a[t, w]-hi*u[t]), unit, pt)
            end
            prev=t==1 ? d["previous_P_MW"][w] : P[t-1, w]
            rec(
                "6-4",
                t,
                w,
                max(0, P[t, w]-prev-before*d["ramp_MW_h"]*dt-(1-before)*d["startup_MW"]),
                "MW",
                pt,
            )
            rec(
                "6-5",
                t,
                w,
                max(0, prev-P[t, w]-u[t]*d["ramp_MW_h"]*dt-(1-u[t])*d["shutdown_MW"]),
                "MW",
                pt,
            )
            rec("6-11", t, w, H[t, w]-d["heat_ratio"]*P[t, w], "MW", pt)
        end
        before=u[t]
    end
    remaining=max(0, d[previous_state==1 ? "min_on_h" : "min_off_h"]-age)
    d["terminal_rule"]=="complete_within_horizon" && rec("R7-N4", T, 0, remaining, "h", 1e-6*(1+dt))
    startup=d["startup_cost_USD"]*sum(on)
    running=dt*sum(d["probabilities"][w]*d["cost_P_USD_MWh"]*P[t, w] for t in 1:T, w in 1:W)
    Dict(
        "component_pass"=>all(r["pass"] for r in rows),
        "normal_network_verified"=>false,
        "preplan_optimality_verified"=>false,
        "startup_cost_USD"=>startup,
        "running_cost_USD"=>running,
        "total_cost_USD"=>startup+running,
        "rows"=>rows,
        "terminal_state"=>previous_state,
        "terminal_duration_h"=>age,
        "terminal_remaining_h"=>remaining,
        "spec_sha256"=>s.sha256,
    )
end

"""
    r7_chp_event_boundary(spec, values; event_start, periods)

从通过设备块验算的原值提取事件窗口启停和故障前出力，保留每个场景与输入/原值哈希。
区间t开始时的爬坡前值为P[t-1]，t=1用输入历史；不会误取事件末值或跨场景均值。
此接口只连接CHP，不将给定电池/热状态或设备块结果升级为完整灾前计划。
"""
function r7_chp_event_boundary(s::R7CHPSpec, values::AbstractDict; event_start, periods)
    checked=validate_r7_chp(s, values)
    checked["component_pass"] || error("不继承未通过核验的CHP计划")
    d=s.data
    event_start isa Integer &&
    periods isa Integer &&
    periods>0 &&
    1<=event_start<=event_start+periods-1<=d["periods"] || error("事件超出CHP时域")
    a=event_start
    u=Int.(round.(values["u_CHP"]))
    # 输入按(T,W)保存，事件前功率仍为W向量；不平均或重新优化。
    fields=Dict(
        "commitment"=>u[a:(a+periods-1)],
        "previous_commitment"=>a==1 ? d["previous_commitment"] : u[a-1],
        "previous_P_MW"=>a==1 ? copy(d["previous_P_MW"]) : collect(values["P_CHP"][a-1, :]),
    )
    Dict(
        "schema"=>"r7-chp-event-boundary-v1",
        "device_id"=>d["id"],
        "event_start"=>a,
        "periods"=>periods,
        "dt_h"=>d["dt_h"],
        "probabilities"=>copy(d["probabilities"]),
        "spec_sha256"=>s.sha256,
        "values_sha256"=>r7_digest(Dict(k=>r7_pack(v) for (k, v) in values)),
        "scope"=>"chp_component_only",
        "preplan_optimality_verified"=>false,
        "fields"=>fields,
    )
end
