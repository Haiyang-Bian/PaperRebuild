"""
    r7_thermal_spec(case, recovery; profiles, profile_origin, substeps=1, mode=:same_dispatch)

构造R7-T1逐管热重构契约。profiles必须逐管、逐侧、逐场景提供空间质量段；
profile_origin说明状态来源。显式传profiles=:uniform才允许从原平均温度生成均匀假设。
固定原管流、端口流和设备热出力；same_dispatch固定供热，curtail_heat仅允许增加热失供。
每原时段均分substeps个子步，单位K、kg/s、MW、MWh、h。不会求解或改写原恢复记录。
"""
function r7_thermal_spec(
    c::R7RecoveryCase,
    recovery;
    profiles,
    profile_origin,
    substeps = 1,
    mode = :same_dispatch,
)
    validate_r7_recovery(c, recovery)["model_pass"] || error("原恢复候选未通过采用模型")
    substeps isa Integer && 1<=substeps<=64 || error("热重构细分须为1至64整数")
    mode in (:same_dispatch, :curtail_heat) || error("热重构模式未定义")
    !isempty(strip(profile_origin)) || error("空间初态来源必须显式说明")
    h=c.data["heat"]
    W=length(c.data["probabilities"])
    list=profiles===:uniform ?
         [
        Dict(
            "pipe"=>a,
            "side"=>side,
            "scenario"=>w,
            "segments"=>[
                Dict(
                    "mass_kg"=>p["volume_$(side)_m3"]*h["rho_kg_m3"],
                    "base_K"=>p["initial_$(side)_K"][w],
                    "amplitude_K"=>0.0,
                    "rate_per_kg"=>0.0,
                    "from_left"=>true,
                ),
            ],
        ) for (a, p) in enumerate(h["pipes"]) for side in ("S", "R") for w in 1:W
    ] : deepcopy(profiles)
    s=Dict{String,Any}(
        "schema"=>"r7-thermal-spec-v1",
        "case_sha256"=>c.sha256,
        "parent_run_id"=>recovery["run_id"],
        "parent_result_sha256"=>r7_digest(recovery),
        "profile_origin"=>String(profile_origin),
        "uniform_assumption"=>profiles===:uniform,
        "substeps"=>substeps,
        "mode"=>string(mode),
        "profiles"=>list,
        "version"=>"r7_thermal_reconstruction_v1",
    )
    r7_thermal_inputs(c, recovery, s)
    s
end

function r7_thermal_state(x)
    R7PipeState([
        R7PipeSegment(
            Float64(p["mass_kg"]),
            Float64(p["base_K"]),
            Float64(p["amplitude_K"]),
            Float64(p["rate_per_kg"]),
            p["from_left"]::Bool,
        ) for p in x["segments"]
    ])
end

function r7_thermal_extrema(s)
    [
        value for p in s.segments for
        value in (p.base_K+p.amplitude_K, p.base_K+p.amplitude_K*exp(-p.rate_per_kg*p.mass_kg))
    ]
end

function r7_thermal_inputs(c, r, spec)
    r7_recovery_assert(c)
    spec["schema"]=="r7-thermal-spec-v1" &&
    spec["version"]=="r7_thermal_reconstruction_v1" &&
    spec["case_sha256"]==c.sha256 &&
    spec["parent_run_id"]==r["run_id"] &&
    spec["parent_result_sha256"]==r7_digest(r) || error("热重构父记录身份不符")
    spec["mode"] in ("same_dispatch", "curtail_heat") || error("热重构模式错误")
    n=spec["substeps"]
    n isa Integer && 1<=n<=64 || error("热重构细分错误")
    !isempty(strip(spec["profile_origin"])) && spec["uniform_assumption"] isa Bool ||
        error("空间状态来源缺失")
    validate_r7_recovery(c, r)["model_pass"] || error("父恢复候选不合格")
    d=c.data
    h=d["heat"]
    T=d["periods"]
    W=length(d["probabilities"])
    A=length(h["pipes"])
    J=h["nodes"]
    states=Dict{Tuple{Int,String,Int},R7PipeState}()
    for p in spec["profiles"]
        a, side, w=p["pipe"], p["side"], p["scenario"]
        a isa Integer && 1<=a<=A && side in ("S", "R") && w isa Integer && 1<=w<=W ||
            error("初态索引错误")
        key=(a, side, w)
        haskey(states, key) && error("初态重复")
        state=r7_thermal_state(p)
        inv=r7_pipe_inventory(state; cp_J_kgK = h["c_J_kgK"], reference_K = h["$(side)_min_K"])
        pipe=h["pipes"][a]
        mass=pipe["volume_$(side)_m3"]*h["rho_kg_m3"]
        abs(inv.mass_kg-mass)<=1e-10*max(1, mass) || error("初态质量与管容积不符")
        mean=pipe["initial_$(side)_K"][w]
        abs(inv.mean_K-mean)<=8eps(max(1.0, abs(mean))) || error("初态均温与灾前继承不符")
        all(x->h["$(side)_min_K"]-1e-4<=x<=h["$(side)_max_K"]+1e-4, r7_thermal_extrema(state)) ||
            error("初始空间温度越界")
        states[key]=state
    end
    length(states)==2A*W || error("初始空间状态不完整")
    v=Dict(k=>r7_unpack(r["values"], k) for k in ("m_pipe", "m_source", "m_load", "H", "H_shed"))
    all(x->x>=0, v["m_source"]) && all(x->x>=0, v["m_load"]) || error("端口流不能为负，不静默裁剪")
    generated=zeros(J, T, W)
    served=zeros(J, T, W)
    for j in 1:J, t in 1:T, w in 1:W
        generated[j, t, w]=sum(
            v["H"][g, t, w] for
            (g, z) in enumerate(d["devices"]) if z["kind"] in ("CHP", "EB") && z["heat_node"]==j;
            init = 0.0,
        )
        served[j, t, w]=h["load_MW"][j][t]-v["H_shed"][j, t, w]
    end
    (; d, h, T, W, A, J, n, K = T*n, dt = d["dt_h"]/n, states, v, generated, served)
end

# 固定空间坐标：供水左端from，回水左端to；负管流翻转两侧实际入/出口。
function r7_thermal_ends(pipe, side, flow)
    left, right=side=="S" ? (pipe["from"], pipe["to"]) : (pipe["to"], pipe["from"])
    flow>=0 ? (left, right) : (right, left)
end

function r7_thermal_pipe_replay(x, a, side, w, inlet)
    s=x.states[(a, side, w)]
    p=x.h["pipes"][a]
    states=R7PipeState[s]
    steps=Any[]
    for k in 1:x.K
        t=cld(k, x.n)
        step=r7_pipe_step(
            s;
            mass_flow_kg_s = x.v["m_pipe"][a, t],
            inlet_K = inlet[k],
            ambient_K = x.h["ambient_K"][t],
            dt_h = x.dt,
            cp_J_kgK = x.h["c_J_kgK"],
            UA_W_K = p["UA_$(side)_W_K"],
            reference_K = x.h["$(side)_min_K"],
        )
        push!(steps, step)
        s=step.state
        push!(states, s)
    end
    (; states, steps)
end

function r7_thermal_samples(replay, x, side)
    # 停流的出口仅为内部零占位；物理验证不把它当温度。
    outlet=[s.outlet_mean_K===nothing ? 0.0 : s.outlet_mean_K for s in replay.steps]
    energy=[
        r7_pipe_inventory(s; cp_J_kgK = x.h["c_J_kgK"], reference_K = x.h["$(side)_min_K"]).relative_heat_MWh
        for s in replay.states
    ]
    extrema=vcat((r7_thermal_extrema(s) for s in replay.states)...)
    vcat(outlet, energy, extrema)
end

function r7_thermal_pipe_map(x, a, side, w; deadline = Inf)
    baseline=fill(x.h["$(side)_reference_K"], x.K)
    ref=r7_thermal_pipe_replay(x, a, side, w, baseline)
    y0=r7_thermal_samples(ref, x, side)
    A=zeros(length(y0), x.K)
    for k in 1:x.K
        time()<deadline || error("thermal_build_deadline")
        input=copy(baseline)
        input[k]+=100
        # 已知线性平流散热算子的基向量提取，不是流量导数或最优值差分。
        A[:, k]=(r7_thermal_samples(r7_thermal_pipe_replay(x, a, side, w, input), x, side)-y0)/100
    end
    (; A, b = y0-A*baseline)
end

"""
    r7_thermal_port_witness(case, recovery, spec)

R7-T5解析必要条件：固定源流下，供温下界与回温上界给出不可省略的最小加热功率。
同时检查固定供热是否超过给定流量与温度边界的上限。返回MW缺口，不以未触发代替完整热验证。
"""
function r7_thermal_port_witness(c, r, spec)
    x=r7_thermal_inputs(c, r, spec)
    h=x.h
    cw=h["c_J_kgK"]/1e6
    rows=Dict{String,Any}[]
    for j in 1:x.J, t in 1:x.T, w in 1:x.W
        lo=cw*x.v["m_source"][j, t]*max(h["source_delta_min"][j], h["S_min_K"]-h["R_max_K"])
        hi=cw*x.v["m_load"][j, t]*min(h["load_delta_max"][j], h["S_max_K"]-h["R_min_K"])
        for (kind, gap) in (
            ("source_minimum_heat", lo-x.generated[j, t, w]),
            ("load_maximum_heat", x.served[j, t, w]-hi),
        )
            gap>1e-6 &&
                push!(rows, Dict("kind"=>kind, "node"=>j, "time"=>t, "scenario"=>w, "gap_MW"=>gap))
        end
    end
    rows
end
