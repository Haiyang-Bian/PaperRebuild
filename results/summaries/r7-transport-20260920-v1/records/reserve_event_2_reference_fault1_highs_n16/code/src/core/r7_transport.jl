const R7_TRANSPORT_PROXY_VARIABLES=("E_S", "E_R", "H_CF", "H_loss_S", "H_loss_R")
const R7_TRANSPORT_PROXY_ROWS=(
    "6-80:82",
    "R7-A3/90",
    "6-89",
    "6-85",
    "6-86",
    "R7-A4/76:78",
    "R7-A4/77:79",
)

"""
    r7_transport_spec(case; flow_schedule, profiles, profile_origin, substeps=16)

R7-D1逐管恢复的显式输入：给定管流与源荷端口流（kg/s），重新优化设备、电网和失供。
flow_schedule须含m_pipe、m_source、m_load矩阵；空间初态必填。采用温区、历史与故障边界不变。
当前固定流量域不等于全变流量恢复；子步平均热网络也不等于连续节点或水力模型。
"""
function r7_transport_spec(
    c::R7RecoveryCase;
    flow_schedule,
    profiles,
    profile_origin,
    substeps = 16,
    uniform_assumption = false,
)
    s=Dict{String,Any}(
        "schema"=>"r7-transport-spec-v1",
        "version"=>"r7_transport_recovery_v1",
        "case_sha256"=>c.sha256,
        "substeps"=>substeps,
        "mode"=>"same_dispatch",
        "profiles"=>deepcopy(profiles),
        "profile_origin"=>String(profile_origin),
        "uniform_assumption"=>uniform_assumption,
        "flow_schedule"=>Dict(
            k=>r7_pack(flow_schedule[k]) for k in ("m_pipe", "m_source", "m_load")
        ),
        "flow_domain"=>"prescribed_schedule",
        "node_rule"=>"substep_average",
    )
    r7_transport_inputs(c, s)
    s
end

function r7_transport_inputs(c, s)
    r7_recovery_assert(c)
    s["schema"]=="r7-transport-spec-v1" &&
    s["version"]=="r7_transport_recovery_v1" &&
    s["case_sha256"]==c.sha256 &&
    s["flow_domain"]=="prescribed_schedule" &&
    s["node_rule"]=="substep_average" &&
    s["mode"]=="same_dispatch" || error("逐管恢复规格身份错误")
    h=c.data["heat"]
    T=c.data["periods"]
    J=h["nodes"]
    A=length(h["pipes"])
    shape=Dict("m_pipe"=>(A, T), "m_source"=>(J, T), "m_load"=>(J, T))
    Set(keys(s["flow_schedule"]))==Set(keys(shape)) || error("流量计划字段错误")
    v=Dict(k=>r7_unpack(s["flow_schedule"], k) for k in keys(shape))
    all(size(v[k])==shape[k] && all(isfinite, v[k]) for k in keys(shape)) ||
        error("流量计划形状或有限性错误")
    for (a, p) in enumerate(h["pipes"]), t in 1:T
        f=v["m_pipe"][a, t]
        abs(f)<=p["flow_max_kg_s"] && abs(f-p["normal_flow_kg_s"][t])<=p["flow_change_max_kg_s"] ||
            error("给定管流超原边界")
    end
    for j in 1:J, t in 1:T
        ms, ml=v["m_source"][j, t], v["m_load"][j, t]
        0<=ms<=h["source_flow_max"][j] && 0<=ml<=h["load_flow_max"][j] ||
            error("给定端口流超原边界")
        mass=ms-ml+sum(
            ((p["to"]==j)-(p["from"]==j))*v["m_pipe"][a, t] for (a, p) in enumerate(h["pipes"])
        )
        abs(mass)<=1e-10*max(1, ms, ml) || error("给定流量不守恒；不自动投影或裁剪")
    end
    r7_thermal_context(c, s, v)
end

"""
    r7_transport_port_witness(case, recovery, thermal_spec)

R7-D2：用已保存空间初态与流量，分别按入口温区上下界独立回放，形成出口与混合节点的必要温区。
由此计算源、荷端口功率范围和原调度的MW缺口。首段尚未有新水到达时，区间退化为真实初态出口。
不求解、不改变控制，不声称求得最小不可行约束集；区间未触发不代表完整热模型可行。
"""
function r7_transport_port_witness(c, r, spec)
    x=r7_thermal_inputs(c, r, spec)
    h=x.h
    cw=h["c_J_kgK"]/1e6
    pipe_bounds=Dict{Tuple{Int,String,Int},Any}()
    for a in 1:x.A, side in ("S", "R"), w in 1:x.W
        lo=r7_thermal_pipe_replay(x, a, side, w, fill(h[side*"_min_K"], x.K))
        hi=r7_thermal_pipe_replay(x, a, side, w, fill(h[side*"_max_K"], x.K))
        pipe_bounds[(a, side, w)]=(lo, hi)
    end
    rows=Dict{String,Any}[]
    for j in 1:x.J, k in 1:x.K, w in 1:x.W
        t=cld(k, x.n)
        ms=x.v["m_source"][j, t]
        ml=x.v["m_load"][j, t]
        node=Dict{String,Tuple{Float64,Float64}}()
        for (side, rate) in (("S", ms), ("R", ml))
            mass=rate
            lower=rate*h[side*"_min_K"]
            upper=rate*h[side*"_max_K"]
            for (a, p) in enumerate(h["pipes"])
                f=x.v["m_pipe"][a, t]
                _, to=r7_thermal_ends(p, side, f)
                if to==j && f!=0
                    lo, hi=pipe_bounds[(a, side, w)]
                    mass+=abs(f)
                    lower+=abs(f)*lo.steps[k].outlet_mean_K
                    upper+=abs(f)*hi.steps[k].outlet_mean_K
                end
            end
            node[side]=mass>0 ? (lower/mass, upper/mass) :
                       (h[side*"_reference_K"], h[side*"_reference_K"])
        end
        for (kind, flow, target, lo, hi) in (
            (
                "source",
                ms,
                x.generated[j, t, w],
                max(h["source_delta_min"][j], h["S_min_K"]-node["R"][2]),
                min(h["source_delta_max"][j], h["S_max_K"]-node["R"][1]),
            ),
            (
                "load",
                ml,
                x.served[j, t, w],
                max(h["load_delta_min"][j], node["S"][1]-h["R_max_K"]),
                min(h["load_delta_max"][j], node["S"][2]-h["R_min_K"]),
            ),
        )
            flow==0 && target==0 && continue
            gap=max(cw*flow*lo-target, target-cw*flow*hi, 0)
            push!(
                rows,
                Dict(
                    "kind"=>kind,
                    "node"=>j,
                    "step"=>k,
                    "time"=>t,
                    "scenario"=>w,
                    "flow_kg_s"=>flow,
                    "target_MW"=>target,
                    "minimum_MW"=>cw*flow*lo,
                    "maximum_MW"=>cw*flow*hi,
                    "gap_MW"=>gap,
                    "violated"=>gap>1e-6,
                    "S_node_lo_K"=>node["S"][1],
                    "S_node_hi_K"=>node["S"][2],
                    "R_node_lo_K"=>node["R"][1],
                    "R_node_hi_K"=>node["R"][2],
                ),
            )
        end
    end
    Dict(
        "schema"=>"r7-transport-interval-witness-v1",
        "case_sha256"=>c.sha256,
        "parent_result_sha256"=>r7_digest(r),
        "spec_sha256"=>r7_digest(spec),
        "rows"=>rows,
        "conflict_found"=>any(z["violated"] for z in rows),
        "target_scope"=>"original_parent_dispatch_not_curtailment",
        "sufficiency_claimed"=>false,
    )
end
