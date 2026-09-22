"""
    R4ReconfigurationSpec(; policy=:joint, electric=:socp)

第4章显式重构版本。policy为fixed、electric、heat、joint，分别放开电开关和日热阀门。
electric为socp或exact；三节点、全节点带电/供热、单根连通树，不含孤岛或瞬态切换。
项目R4-N1至N6补全原式(4-22/29/34–40/47–51)，不改变旧R4Spec默认行为。
"""
struct R4ReconfigurationSpec
    policy::Symbol
    electric::Symbol
    function R4ReconfigurationSpec(; policy = :joint, electric = :socp)
        policy in (:fixed, :electric, :heat, :joint) || error("未知重构策略")
        electric in (:socp, :exact) || error("未知电网形式")
        new(policy, electric)
    end
end

"""
    r4_is_tree(edges, on; nodes=3)

独立图遍历检查无向网络是否连通且恰有nodes-1条边；拒绝自环、重复边及非二进制状态。
方向只是存储约定，不约束实际功率方向。既检查连通也检查边数，避免孤立根与非根环。
"""
function r4_is_tree(edges, on; nodes = 3)
    length(edges)==length(on) || return false
    all(x->x in (0, 1), on) || return false
    pairs=[minmax(x["from"], x["to"]) for x in edges]
    all(p->1<=p[1]<p[2]<=nodes, pairs) || return false
    length(unique(pairs))==length(pairs) || return false
    sum(on)==nodes-1 || return false
    visited=Set([1])
    for _ in 1:nodes
        for (p, (i, j)) in enumerate(pairs)
            on[p]==1 || continue
            (i in visited || j in visited) && (push!(visited, i); push!(visited, j))
        end
    end
    return length(visited)==nodes
end

function r4_network_check(d)
    n=d["network_control"]
    n["version"]=="r4_reconfiguration_checked_v1" || error("未知重构版本")
    e=d["electric"]["edges"]
    h=d["heat"]["pipes"]
    2<=length(e)<=3 && length(h)==6 || error("本批候选图最多三条电线、三对热方向弧")
    for rows in (e, h[1:3])
        all(x->1<=x["from"]<x["to"]<=3, rows) || error("候选物理边须按节点递增存储")
        length(unique((x["from"], x["to"]) for x in rows))==length(rows) || error("重复物理边")
    end
    for p in 1:3
        a=deepcopy(h[p])
        b=deepcopy(h[p+3])
        a["from"], a["to"]=a["to"], a["from"]
        a==b || error("反向弧必须引用同一物理管道参数")
    end
    r4_is_tree(e, n["electric_initial"]) && r4_is_tree(h[1:3], n["heat_initial"]) ||
        error("初始网络须为连通树")
    n["dwell_steps"] isa Integer && n["dwell_steps"]>=1 || error("动作间隔错误")
    n["stable_history_steps"] isa Integer && n["stable_history_steps"]>=n["dwell_steps"]-1 ||
        error("初始开关稳定历史不足")
    n["max_electric_actions"] isa Integer && n["max_electric_actions"]>=0 || error("动作次数错误")
    all(
        k->n[k] isa Real && isfinite(n[k]) && n[k]>=0,
        ("electric_action_cost", "heat_action_cost"),
    ) || error("动作成本错误")
    return true
end

function r4_switch_cost(c, s)
    haskey(c.data, "network_control") && haskey(s, "u_E") || return 0.0
    n=c.data["network_control"]
    T=c.data["T"]
    changes=sum(
        abs(s["u_E"][p][t]-(t==1 ? n["electric_initial"][p] : s["u_E"][p][t-1])) for
        p in eachindex(s["u_E"]), t in 1:T
    )
    valves=sum(abs(s["u_H"][p]-n["heat_initial"][p]) for p in eachindex(s["u_H"]))
    return n["electric_action_cost"]*changes+n["heat_action_cost"]*valves
end
