"""
    r7_linked_planning_spec(case; flows, substeps=16)

为R7-L1详细热规划声明每个事件/故障的给定流量，单位kg/s。flows按`event:faults`键
提供m_pipe/m_source/m_load矩阵；必须覆盖原事件下全部允许故障，不自动挑选易通过情景。
空间初态始终来自同一正常决策。该规格定义条件流量域，不是完整变流量优化。
"""
function r7_linked_planning_spec(c::R7PlanningCase; flows, substeps = 16)
    r7_planning_assert(c)
    pairs=r7_planning_pairs(c)
    Set(keys(flows))==Set(r7_planning_pair_key(p) for p in pairs) ||
        error("详细规划流量未覆盖全部故障")
    s=Dict{String,Any}(
        "schema"=>"r7-linked-planning-spec-v1",
        "version"=>"r7_state_linked_v1",
        "planning_case_sha256"=>c.sha256,
        "substeps"=>substeps,
        "normal_domain"=>c.specification["normal_domain"],
        "recovery_flow_domain"=>"prescribed_per_event_fault",
        "state_rule"=>"shared_normal_spatial_state",
        "node_rule"=>"substep_average_zero_node_volume",
        "flows"=>[
            Dict(
                "event"=>p.event,
                "fault"=>p.fault,
                "flow_schedule"=>Dict(
                    k=>r7_pack(flows[r7_planning_pair_key(p)][k]) for
                    k in ("m_pipe", "m_source", "m_load")
                ),
            ) for p in pairs
        ],
    )
    r7_linked_spec_check(c, s)
    s
end

function r7_linked_flow(s, pair)
    key=r7_planning_pair_key(pair)
    row=only(
        x for x in s["flows"] if r7_planning_pair_key((event = x["event"], fault = x["fault"]))==key
    )
    Dict(k=>r7_unpack(row["flow_schedule"], k) for k in ("m_pipe", "m_source", "m_load"))
end

function r7_linked_initial_profiles(c)
    d=c.normal.data
    [
        Dict(
            "pipe"=>a,
            "side"=>side,
            "scenario"=>w,
            "segments"=>[
                Dict(
                    "mass_kg"=>z.mass_kg,
                    "base_K"=>z.base_K,
                    "amplitude_K"=>z.amplitude_K,
                    "rate_per_kg"=>z.rate_per_kg,
                    "from_left"=>z.from_left,
                ) for z in r7_normal_initial(d, p, side, w).segments
            ],
        ) for (a, p) in enumerate(d["heat"]["pipes"]) for side in ("S", "R") for
        w in eachindex(d["probabilities"])
    ]
end

# 仅为参数化建模提供结构；模板初态不会成为恢复边界，随后由完整历史算子替换。
function r7_linked_template(c, s, pair)
    event=r7_event_template(c, pair.event)
    spec=r7_transport_spec(
        event;
        flow_schedule = r7_linked_flow(s, pair),
        profiles = r7_linked_initial_profiles(c),
        profile_origin = "symbolic_shared_normal_template",
        substeps = s["substeps"],
    )
    (; case = event, spec)
end

function r7_linked_spec_check(c, s)
    r7_planning_assert(c)
    s["schema"]=="r7-linked-planning-spec-v1" &&
    s["version"]=="r7_state_linked_v1" &&
    s["planning_case_sha256"]==c.sha256 &&
    s["normal_domain"]==c.specification["normal_domain"] &&
    s["recovery_flow_domain"]=="prescribed_per_event_fault" &&
    s["state_rule"]=="shared_normal_spatial_state" &&
    s["node_rule"]=="substep_average_zero_node_volume" || error("详细规划规格身份或边界错误")
    s["substeps"] isa Integer && 1<=s["substeps"]<=64 || error("详细规划子步非法")
    pairs=r7_planning_pairs(c)
    keys=[r7_planning_pair_key((event = x["event"], fault = x["fault"])) for x in s["flows"]]
    keys==[r7_planning_pair_key(p) for p in pairs] || error("详细规划故障流量缺失/重复/顺序错误")
    for p in pairs
        r7_linked_template(c, s, p)
    end
    nothing
end

# 从当前正常原值重新生成事件空间状态，任何旧轮证书都不能替代这一计算。
function r7_linked_event(c, s, n, pair)
    event=r7_planning_event(c, n, pair.event)
    spec=r7_transport_spec(
        event.case;
        flow_schedule = r7_linked_flow(s, pair),
        profiles = event.evidence["initial_pipe_profiles"],
        profile_origin = "same_normal_trajectory_"*n["run_id"],
        substeps = s["substeps"],
    )
    (; case = event.case, evidence = event.evidence, spec)
end
