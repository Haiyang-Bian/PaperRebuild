function r4_validate_network!(row, bound, c, result)
    s=result["values"]
    n=c.data["network_control"]
    T=c.data["T"]
    e=c.data["electric"]["edges"]
    h=c.data["heat"]["pipes"][1:3]
    config=get(result, "reconfiguration", Dict{String,Any}())
    thermal=get(result["spec"], "version", "")=="r4_thermal_checked_v1"
    for key in ("u_E", "u_H_arc", "a_E"), p in eachindex(s[key]), t in 1:T
        x=s[key][p][t]
        row(key*"_binary", "model", p, t, abs(x-round(x)), "1", 1e-6)
        bound(key, "model", p, t, x, 0, 1, "1", 1e-6)
    end
    for key in ("u_H", "a_H"), p in 1:3
        x=s[key][p]
        row(key*"_binary", "model", p, 0, abs(x-round(x)), "1", 1e-6)
        bound(key, "model", p, 0, x, 0, 1, "1", 1e-6)
    end
    for t in 1:T
        on=[round(Int, s["u_E"][p][t]) for p in eachindex(e)]
        row("electric_tree", "model", 0, t, r4_is_tree(e, on) ? 0.0 : 1.0, "1", 1e-6)
    end
    row("heat_tree", "model", 0, 0, r4_is_tree(h, round.(Int, s["u_H"])) ? 0.0 : 1.0, "1", 1e-6)
    for p in 1:3
        row(
            "valve_action",
            "model",
            p,
            0,
            s["a_H"][p]-abs(s["u_H"][p]-n["heat_initial"][p]),
            "1",
            1e-6,
        )
        for t in 1:T
            row(
                "heat_direction",
                "model",
                p,
                t,
                thermal ? max(0, s["u_H_arc"][p][t]+s["u_H_arc"][p+3][t]-s["u_H"][p]) :
                s["u_H_arc"][p][t]+s["u_H_arc"][p+3][t]-s["u_H"][p],
                "1",
                1e-6,
            )
        end
    end
    for p in eachindex(e)
        for t in 1:T
            prev=t==1 ? n["electric_initial"][p] : s["u_E"][p][t-1]
            row("switch_action", "model", p, t, s["a_E"][p][t]-abs(s["u_E"][p][t]-prev), "1", 1e-6)
            row(
                "dwell",
                "model",
                p,
                t,
                max(0, sum(s["a_E"][p][k] for k in max(1, t-n["dwell_steps"]+1):t)-1),
                "1",
                1e-6,
            )
        end
        row(
            "action_limit",
            "model",
            p,
            0,
            max(0, sum(s["a_E"][p])-n["max_electric_actions"]),
            "1",
            1e-6,
        )
    end
    for (key, edges, on, nt) in (("F_E", e, s["u_E"], T), ("F_H", h, [[x] for x in s["u_H"]], 1))
        for t in 1:nt
            for p in eachindex(edges)
                bound(key, "model", p, t, s[key][p][t], -2on[p][t], 2on[p][t], "1", 1e-6)
            end
            for i in 1:3
                flow=sum(
                    s[key][p][t]*(x["from"]==i ? 1 : x["to"]==i ? -1 : 0) for
                    (p, x) in enumerate(edges)
                )
                row(
                    "virtual_connectivity",
                    "model",
                    key*string(i),
                    t,
                    flow-(i==1 ? 2 : -1),
                    "1",
                    1e-6,
                )
            end
        end
    end
    policy=get(config, "policy", "joint")
    policy in ("fixed", "electric", "heat", "joint") || error("保存的策略错误")
    if policy in ("fixed", "heat")
        for p in eachindex(e), t in 1:T
            row("fixed_electric", "model", p, t, s["u_E"][p][t]-n["electric_initial"][p], "1", 1e-6)
        end
    end
    if policy in ("fixed", "electric")
        for p in 1:3
            row("fixed_heat", "model", p, 0, s["u_H"][p]-n["heat_initial"][p], "1", 1e-6)
        end
    end
    for (key, valuekey) in (("electric_schedule", "u_E"), ("heat_open", "u_H"))
        haskey(config, key) || continue
        for p in eachindex(config[key])
            if key=="heat_open"
                row(
                    "frozen_topology",
                    "model",
                    key*string(p),
                    0,
                    s[valuekey][p]-config[key][p],
                    "1",
                    1e-6,
                )
            else
                for t in 1:T
                    row(
                        "frozen_topology",
                        "model",
                        key*string(p),
                        t,
                        s[valuekey][p][t]-config[key][p][t],
                        "1",
                        1e-6,
                    )
                end
            end
        end
    end
    if haskey(config, "heat_direction")
        for p in 1:3, t in 1:T
            row(
                "frozen_direction",
                "model",
                p,
                t,
                s["u_H_arc"][p][t]-config["heat_direction"][p][t]*s["u_H"][p],
                "1",
                1e-6,
            )
        end
    end
    if haskey(config, "heat_active")
        thermal || error("旧版本不能含循环/闲置计划")
        plan=r4_heat_matrix(config, "heat_active", 6, T)
        all(x->x in (0, 1), plan) || error("保存循环计划不是二进制")
        for p in 1:6, t in 1:T
            row("R4-T1_frozen_active", "heat", p, t, s["u_H_arc"][p][t]-plan[p, t], "1", 1e-6)
        end
    end
end

"""
    validate_r4_reconfiguration(case, result)

从保存数值独立核查连通树、开关动作/间隔、日阀门、热方向、开路输运与损耗。
复用设备和能量流数值验证器；逐支路原电网等式仍独立报告。物理通过不含动态热网。
费用按真实状态变化计算，不信任动作辅助量；原始目标与实际费用分别校核。
"""
function validate_r4_reconfiguration(c::R4Case, r)
    haskey(c.data, "network_control") || error("重构输入缺失")
    r["spec"]["version"]=="r4_reconfiguration_checked_v1" || error("重构版本错误")
    return validate_r4_solution(c, r)
end
