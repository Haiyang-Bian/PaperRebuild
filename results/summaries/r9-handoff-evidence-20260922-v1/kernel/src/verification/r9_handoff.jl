"""
    r9_handoff_temperature_check(case, transport_spec; deadline=Inf)

R9-DH1：给定完整管温及灾后流量，以允许入口温区两端分别独立水团回放。
非负传热系数下平流/散热保持温度顺序，两次回放夹住任意合法入口控制。
最热入口仍存在过冷点，或最冷入口仍存在过热点，即给定状态/流量违反必要温区。
单位K，沿用A1的1e-4 K；不求解、不改变原值。适用原输运核支持的给定正流、零流及反流。
通过不证明设备、电网、混合、供热或完整调度可行；该条件属于项目详细热模型。
"""
function r9_handoff_temperature_check(c::R7RecoveryCase, spec; deadline = Inf)
    (isfinite(deadline) || deadline == Inf) || error("温区预检截止时间非法")
    time() < deadline || error("handoff_temperature_check_deadline")
    x = r7_transport_inputs(c, spec)
    tol = 1e-4
    rows = Dict{String,Any}[]
    for a in 1:x.A, side in ("S", "R"), w in 1:x.W
        time() < deadline || error("handoff_temperature_check_deadline")
        loK, hiK = x.h[side*"_min_K"], x.h[side*"_max_K"]
        lower = r7_thermal_pipe_replay(x, a, side, w, fill(loK, x.K))
        upper = r7_thermal_pipe_replay(x, a, side, w, fill(hiK, x.K))
        for k in 1:x.K
            t = cld(k, x.n)
            if lower.steps[k].outlet_mean_K !== nothing
                lo, hi = lower.steps[k].outlet_mean_K, upper.steps[k].outlet_mean_K
                lo <= hi + 1e-10 || error("入口温度顺序未保持")
                gap = max(loK - hi, lo - hiK, 0.0)
                push!(
                    rows,
                    Dict(
                        "pipe" => a,
                        "side" => side,
                        "scenario" => w,
                        "substep" => k,
                        "time" => t,
                        "relation" => "R7-T1-transport/R7-T-bound",
                        "lower_response_K" => lo,
                        "upper_response_K" => hi,
                        "minimum_K" => loK,
                        "maximum_K" => hiK,
                        "gap_K" => gap,
                        "inlet_independent" => lo == hi,
                        "conflict" => gap > tol,
                    ),
                )
            end
            # 两次水团分段可以不同：比较最热状态的最冷点和最冷状态的最热点，不按段序号配对。
            coldmax = maximum(r7_thermal_extrema(lower.states[k+1]))
            hotmin = minimum(r7_thermal_extrema(upper.states[k+1]))
            gap = max(loK - hotmin, coldmax - hiK, 0.0)
            push!(
                rows,
                Dict(
                    "pipe" => a,
                    "side" => side,
                    "scenario" => w,
                    "substep" => k,
                    "time" => t,
                    "relation" => "R7-T4-spatial",
                    "cold_state_max_K" => coldmax,
                    "hot_state_min_K" => hotmin,
                    "minimum_K" => loK,
                    "maximum_K" => hiK,
                    "gap_K" => gap,
                    "conflict" => gap > tol,
                ),
            )
        end
    end
    time() < deadline || error("handoff_temperature_check_deadline")
    conflicts = filter(r -> r["conflict"], rows)
    Dict(
        "schema" => "r9-handoff-temperature-v1",
        "case_sha256" => c.sha256,
        "spec_sha256" => r7_digest(spec),
        "tolerance_K" => tol,
        "necessary_condition_pass" => isempty(conflicts),
        "conflict_count" => length(conflicts),
        "maximum_unavoidable_violation_K" => maximum((r["gap_K"] for r in rows); init = 0.0),
        "rows" => rows,
        "optimization_performed" => false,
        "sufficiency_claimed" => false,
        "flow_schedule_unchanged" => true,
    )
end
