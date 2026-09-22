"""
    validate_r9_network(case, values)

从保存拓扑、动作和虚拟流逐式重验R9-RN1/N3；另用独立图遍历检查连通径向。
检查初始状态、不可控边、日热阀门、逐时电开关及动作间隔/次数。容差为原A1的1e-6。
不求解，不替代电热物理检查；费用按CNY/次计算，不乘时间步。旧输入返回空检查与零费用。
"""
function validate_r9_network(c::R9TradingCase, s)
    TOML.parse(c.source_text)==c.data || error("网络输入被原位改写")
    haskey(c.data, "network_control") ||
        return Dict("rows"=>Dict{String,Any}[], "switching_CNY"=>0.0)
    d=c.data
    n=d["network_control"]
    rows=Dict{String,Any}[]
    function row(id, i, t, x)
        r=abs(Float64(x))
        push!(
            rows,
            Dict(
                "equation"=>id,
                "scope"=>"model",
                "entity"=>string(i),
                "t"=>t,
                "residual"=>r,
                "unit"=>"1",
                "tolerance"=>1e-6,
                "pass"=>isfinite(r)&&r<=1e-6,
            ),
        )
    end
    switching=0.0
    for (side, key, suffix, nt) in (("electric", "edges", "E", d["T"]), ("heat", "pipes", "H", 1))
        net=d[side]
        edges=net[key]
        L, N=length(edges), net["nodes"]
        u, a, f=(s[p*"_"*suffix] for p in ("u", "a", "F"))
        for x in (u, a, f)
            length(x)==L && all(y->length(y)==nt && all(isfinite, y), x) ||
                error("拓扑数值维度或有限性错误")
        end
        enabled=n["policy"] in (side, "joint")
        for j in 1:L, t in 1:nt
            open=u[j][t]
            prev=t==1 ? n[side*"_initial"][j] : u[j][t-1]
            row("R9-RN1-integer-"*suffix, j, t, max(abs(open-round(open)), -open, open-1))
            row("R9-RN3-action-"*suffix, j, t, a[j][t]-abs(open-prev))
            row("R9-RN3-action-bound-"*suffix, j, t, max(0, -a[j][t], a[j][t]-1))
            if !enabled || n[side*"_switchable"][j]==0
                row("R9-RN1-fixed-"*suffix, j, t, open-n[side*"_initial"][j])
            end
            row("R9-RN1-commodity-"*suffix, j, t, max(0, abs(f[j][t])-(N-1)*open))
            switching+=n[side*"_action_CNY"]*abs(open-prev)
        end
        for t in 1:nt
            on=[round(Int, x[t]) for x in u]
            row("R9-RN1-tree-"*suffix, "all", t, r4_is_tree(edges, on; nodes = N) ? 0 : 1)
            row("R9-RN1-edge-count-"*suffix, "all", t, sum(x[t] for x in u)-(N-1))
            for i in 1:N
                balance=sum(f[j][t] for j in 1:L if edges[j]["from"]==i; init = 0.0) -
                        sum(f[j][t] for j in 1:L if edges[j]["to"]==i; init = 0.0)
                row("R9-RN1-flow-"*suffix, i, t, balance-(i==net["root"] ? N-1 : -1))
            end
        end
        if side=="electric"
            for j in 1:L
                row("R9-RN3-max-actions", j, 0, max(0, sum(a[j])-n["electric_max_actions"]))
                for t in 1:nt
                    lo=max(1, t-n["dwell_steps"]+1)
                    row("R9-RN3-dwell", j, t, max(0, sum(a[j][lo:t])-1))
                end
            end
        end
    end
    Dict("rows"=>rows, "switching_CNY"=>switching)
end

function r9_switching_cost(c, s)
    haskey(c.data, "network_control") && haskey(s, "u_E") || return 0.0
    n=c.data["network_control"]
    cost=0.0
    for (side, suffix) in (("electric", "E"), ("heat", "H"))
        for (j, row) in enumerate(s["u_"*suffix])
            prev=n[side*"_initial"][j]
            for on in row
                cost+=n[side*"_action_CNY"]*abs(on-prev)
                prev=on
            end
        end
    end
    cost
end
