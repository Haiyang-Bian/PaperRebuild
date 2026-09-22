"""
    r7_flow_planning_spec(case; normal_flow, recovery_bounds, substeps=1)

R7-J1/H5连续流量安全规划的显式域。normal_flow显式选择正常正向无损或有损Gauss规格；recovery_bounds
按event:faults提供pipe/source/load的min/max矩阵(kg/s)，恢复允许停流但不允许反向。
流量在各事件/故障内跨新能源场景共享。原R7PlanningCase仅作为正常数据与事件的载体，
本规格显式替代其给定流量域，保留原数据哈希，不改变旧规划接口。
"""
function r7_flow_planning_spec(c::R7PlanningCase; normal_flow, recovery_bounds, substeps = 1)
    lossy=r7_is_lossy_flow(normal_flow)
    pairs=r7_planning_pairs(c)
    Set(keys(recovery_bounds))==Set(r7_planning_pair_key.(pairs)) ||
        error("连续规划流量界必须覆盖所有故障")
    s=Dict{String,Any}(
        "schema"=>"r7-flow-planning-spec-v1",
        "version"=>lossy ? "r7_shared_lossy_flow_v1" : "r7_shared_continuous_flow_v1",
        "case_sha256"=>c.sha256,
        "normal_flow"=>deepcopy(normal_flow),
        "substeps"=>substeps,
        "normal_domain"=>lossy ? "continuous_positive_lossy_gauss_fixed_electric_topology" :
                         "continuous_positive_lossless_fixed_electric_topology",
        "recovery_domain"=>lossy ? "continuous_nonnegative_lossy_gauss_shared_scenarios" :
                           "continuous_nonnegative_lossless_shared_scenarios",
        "state_rule"=>"same_normal_mass_labels_and_temperatures",
        "idle_temperature_rule"=>"free_zero_flow",
        "energy_balance"=>true,
        "bounds"=>[
            Dict(
                "event"=>p.event,
                "fault"=>p.fault,
                "bounds"=>Dict(
                    k=>r7_pack(Float64.(v)) for (k, v) in recovery_bounds[r7_planning_pair_key(p)]
                ),
            ) for p in pairs
        ],
    )
    r7_flow_planning_check(c, s)
    s
end

function r7_joint_bounds(s, pair)
    x=only(
        x for x in s["bounds"] if
        r7_planning_pair_key((event = x["event"], fault = x["fault"]))==r7_planning_pair_key(pair)
    )
    Dict(k=>r7_unpack(x["bounds"], k) for k in keys(x["bounds"]))
end

function r7_flow_planning_check(c, s)
    r7_planning_assert(c)
    lossy=r7_is_lossy_flow(s["normal_flow"])
    s["schema"]=="r7-flow-planning-spec-v1" &&
    s["version"]==(lossy ? "r7_shared_lossy_flow_v1" : "r7_shared_continuous_flow_v1") &&
    s["case_sha256"]==c.sha256 &&
    s["normal_domain"]==(
        lossy ? "continuous_positive_lossy_gauss_fixed_electric_topology" :
        "continuous_positive_lossless_fixed_electric_topology"
    ) &&
    s["recovery_domain"]==(
        lossy ? "continuous_nonnegative_lossy_gauss_shared_scenarios" :
        "continuous_nonnegative_lossless_shared_scenarios"
    ) &&
    s["state_rule"]=="same_normal_mass_labels_and_temperatures" &&
    s["idle_temperature_rule"]=="free_zero_flow" &&
    s["energy_balance"]===true || error("联合流量规格身份/范围错误")
    r7_normal_flow_check(c.normal, s["normal_flow"])
    s["substeps"] isa Integer && 1<=s["substeps"]<=64 || error("联合规划子步非法")
    pairs=r7_planning_pairs(c)
    [r7_planning_pair_key((event = x["event"], fault = x["fault"])) for x in s["bounds"]]==r7_planning_pair_key.(pairs) || error("故障界缺失/重复/顺序错误")
    h=c.normal.data["heat"]
    for pair in pairs
        b=r7_joint_bounds(s, pair)
        Set(keys(b))==Set(
            k*side for k in ("pipe", "source", "load") for side in ("_min", "_max")
        ) || error("恢复界字段错误")
        T=c.specification["events"][pair.event]["periods"]
        for kind in ("pipe", "source", "load")
            cap=kind=="pipe" ? [p["flow_max_kg_s"] for p in h["pipes"]] : h[kind*"_flow_max"]
            lo, hi=b[kind*"_min"], b[kind*"_max"]
            size(lo)==size(hi)==(length(cap), T) &&
            all(isfinite, lo) &&
            all(isfinite, hi) &&
            all(0 .<= lo .<= hi .<= cap) || error("非负恢复流量界错误")
        end
    end
    nothing
end

function r7_joint_fixed_domain(c, s)
    b=r7_normal_flow_check(c.normal, s["normal_flow"])
    all(b[k*"_min"]==b[k*"_max"] for k in ("pipe", "source", "load")) && all(
        begin
            x=r7_joint_bounds(s, p)
            all(x[k*"_min"]==x[k*"_max"] for k in ("pipe", "source", "load"))
        end for p in r7_planning_pairs(c)
    )
end
