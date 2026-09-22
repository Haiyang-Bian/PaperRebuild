# 最大流仅寻找候选割；证据由输入上的精确有理数求和重新核对，不信任算法状态。
function r9_trading_cut_set(supply, demand, links)
    n=length(supply)
    source, sink=n+1, n+2
    residual=zeros(n+2, n+2)
    for i in 1:n
        residual[source, i]=supply[i]
        residual[i, sink]=demand[i]
    end
    for (i, j, cap) in links
        residual[i, j]+=cap
        residual[j, i]+=cap
    end
    while true
        parent=zeros(Int, n+2)
        parent[source]=source
        queue=[source]
        for i in queue
            for j in 1:(n+2)
                if parent[j]==0 && residual[i, j]>1e-12
                    parent[j]=i
                    push!(queue, j)
                end
            end
            parent[sink]!=0 && break
        end
        parent[sink]==0 && return [i for i in 1:n if parent[i]==0]
        amount=Inf
        j=sink
        while j!=source
            i=parent[j]
            amount=min(amount, residual[i, j])
            j=i
        end
        j=sink
        while j!=source
            i=parent[j]
            residual[i, j]-=amount
            residual[j, i]+=amount
            j=i
        end
    end
end

"""
    r9_trading_heat_cut(case, nodes, t)

对指定热节点集合独立核算必要供热上界（项目R9-T8），功率单位MW。
保留管对必付的参考损耗，并用末端电节点的馈线容量、最低电负荷和最大本地产电限制电锅炉。
其余电压、无功、储能跨时段和热质量条件全部放宽；仅用输入的Float64系数作精确有理数运算。
positive_deficit是这一采用模型的容量矛盾，不能直接推断作者原始数据或所有热网模型不可行。
该检查不求解、不给优化器注入结果；无正缺口不证明调度可行。
"""
function r9_trading_heat_cut(c, nodes, t)
    haskey(c.data, "network_control") && error("旧固定树热割不能证明可切换候选图不可行")
    TOML.parse(c.source_text)==c.data && bytes2hex(sha256(c.source_text))==c.sha256 ||
        error("Heat cut input identity changed")
    d=c.data
    e, h=d["electric"], d["heat"]
    1<=t<=d["T"] || error("Heat cut time outside horizon")
    !isempty(nodes) && allunique(nodes) && all(i->i isa Integer && 1<=i<=h["nodes"], nodes) ||
        error("Heat cut nodes invalid")
    A=sort(collect(Int, nodes))
    exact(x) = Rational{BigInt}(Float64(x))
    zeroq=zero(Rational{BigInt})
    pairs(x) = Dict("numerator"=>string(numerator(x)), "denominator"=>string(denominator(x)))
    demand=sum((exact(h["H_background_MW"][i][t]) for i in A); init = zeroq)
    demand+=sum(
        (exact((1-a["flex"])*a["H_load"][t]) for a in d["actors"][2:end] if a["heat_node"] in A);
        init = zeroq,
    )
    internal=[j for (j, p) in enumerate(h["pipes"]) if p["from"] in A && p["to"] in A]
    crossing=[j for (j, p) in enumerate(h["pipes"]) if (p["from"] in A)!=(p["to"] in A)]
    losses=sum((exact(h["pipes"][j]["loss_MW"]) for j in internal); init = zeroq)
    imports=sum((exact(h["pipes"][j]["H_max_MW"]) for j in crossing); init = zeroq)
    supply=zeroq
    devices=Dict{String,Any}[]
    for (j, g) in enumerate(d["devices"])
        g["heat_node"] in A && g["kind"] in ("CHP", "P2H", "HS") || continue
        cap=exact(
            g["kind"]=="HS" ? g["availability_MW"][t] : g["availability_MW"][t]*g["heat_ratio"],
        )
        row=Dict{String,Any}("device"=>g["id"], "index"=>j, "nameplate_heat_MW"=>Float64(cap))
        if g["kind"]=="P2H"
            n=g["electric_node"]
            incident=[(l, p) for (l, p) in enumerate(e["edges"]) if n in (p["from"], p["to"])]
            # 只在明确的非根末端节点采用此局部电力上界；不把它扩展成未推导的网络替代。
            if n!=e["root"] && length(incident)==1 && last(only(incident))["to"]==n
                l, p=only(incident)
                k=exact(1/e["base_MVA"])
                available=(
                    exact(p["P_max_MW"]/e["base_MVA"]) -
                    exact(e["P_background_MW"][n][t]/e["base_MVA"])
                )/k
                available+=sum(
                    (
                        exact(x["availability_MW"][t]) for x in d["devices"] if
                        x["electric_node"]==n && x["kind"] in ("CHP", "PV", "BS")
                    );
                    init = zeroq,
                )
                available-=sum(
                    (
                        exact((1-a["flex"])*a["P_load"][t]) for
                        a in d["actors"][2:end] if a["electric_node"]==n
                    );
                    init = zeroq,
                )
                row["electric_node"]=n
                row["electric_edge"]=l
                row["electric_budget_MW"]=Float64(available)
                row["exact_electric_budget"]=pairs(available)
                cap=min(cap, exact(g["heat_ratio"])*max(zeroq, available))
            end
        end
        row["admissible_heat_upper_MW"]=Float64(cap)
        row["exact_heat_upper"]=pairs(cap)
        push!(devices, row)
        supply+=cap
    end
    deficit=demand+losses-supply-imports
    Dict{String,Any}(
        "schema"=>"r9-trading-heat-cut-v1",
        "input_sha256"=>c.sha256,
        "nodes"=>A,
        "t"=>t,
        "minimum_demand_MW"=>Float64(demand),
        "internal_loss_MW"=>Float64(losses),
        "maximum_supply_MW"=>Float64(supply),
        "maximum_import_MW"=>Float64(imports),
        "deficit_MW"=>Float64(deficit),
        "exact_deficit"=>pairs(deficit),
        "positive_deficit"=>deficit>0,
        "devices"=>devices,
        "internal_pipes"=>internal,
        "crossing_pipes"=>crossing,
        "complete_thermal_certification"=>false,
        "meaning"=>"necessary_coupled_capacity_only",
    )
end

"""
    audit_r9_trading_capacity(case)

仅从输入检查电/热网络的必要容量割（项目R9-T7），不求解原调度、不改变输入。
忽略损耗、热质量/温度、电压、储能跨时段和电热转换耗电，逐时允许全部装置取最大出力，
使问题更容易；任意节点集合的最低需求仍不能超过集合内最大供给加跨边界输入容量。
候选集合用纯Julia增广路寻找，最后对保存的Float64边界作精确有理数求和。
positive_deficit证明这一放宽能流系统的字面边界矛盾；无违反不证明原问题可行。
功率为MW、时段索引为1:T；本证据不包含对完整温度场或水压的认证。
"""
function audit_r9_trading_capacity(c)
    haskey(c.data, "network_control") && error("先显式选定活动图；旧容量审计不隐式决定拓扑")
    TOML.parse(c.source_text)==c.data && bytes2hex(sha256(c.source_text))==c.sha256 ||
        error("Capacity audit input identity changed")
    d=c.data
    rows=Dict{String,Any}[]
    exact(x) = Rational{BigInt}(Float64(x))
    for carrier in ("P", "H"), t in 1:d["T"]
        network=carrier=="P" ? d["electric"] : d["heat"]
        n=network["nodes"]
        supply_parts=[Float64[] for _ in 1:n]
        demand_parts=[[Float64(network[carrier*"_background_MW"][i][t])] for i in 1:n]
        carrier=="P" && push!(supply_parts[network["root"]], network["grid_max_MW"])
        for a in d["actors"][2:end]
            i=a[carrier=="P" ? "electric_node" : "heat_node"]
            push!(demand_parts[i], (1-a["flex"])*a[carrier*"_load"][t])
        end
        for g in d["devices"]
            i=g[carrier=="P" ? "electric_node" : "heat_node"]
            i==0 && continue
            cap=carrier=="P" ? (g["kind"] in ("PV", "CHP", "BS") ? g["availability_MW"][t] : 0.0) :
                (
                g["kind"] in ("CHP", "P2H") ? g["availability_MW"][t]*g["heat_ratio"] :
                g["kind"]=="HS" ? g["availability_MW"][t] : 0.0
            )
            push!(supply_parts[i], cap)
        end
        links=[
            (p["from"], p["to"], Float64(p[carrier*"_max_MW"])) for
            p in network[carrier=="P" ? "edges" : "pipes"]
        ]
        A=r9_trading_cut_set(sum.(supply_parts), sum.(demand_parts), links)
        required=sum((exact(q) for i in A for q in demand_parts[i]); init = zero(Rational{BigInt}))
        generated=sum((exact(q) for i in A for q in supply_parts[i]); init = zero(Rational{BigInt}))
        crossing=[j for (j, (i, k, _)) in enumerate(links) if (i in A)!=(k in A)]
        imported=sum((exact(links[j][3]) for j in crossing); init = zero(Rational{BigInt}))
        deficit=required-generated-imported
        push!(
            rows,
            Dict(
                "carrier"=>carrier,
                "t"=>t,
                "nodes"=>A,
                "crossing_edges"=>crossing,
                "minimum_demand_MW"=>Float64(required),
                "maximum_local_supply_MW"=>Float64(generated),
                "maximum_import_MW"=>Float64(imported),
                "deficit_MW"=>Float64(deficit),
                "exact_deficit_numerator"=>string(numerator(deficit)),
                "exact_deficit_denominator"=>string(denominator(deficit)),
                "positive_deficit"=>deficit>0,
            ),
        )
    end
    Dict(
        "schema"=>"r9-trading-capacity-audit-v1",
        "input_sha256"=>c.sha256,
        "rows"=>rows,
        "violations"=>count(r->r["positive_deficit"], rows),
        "meaning"=>"necessary_capacity_only; no_violation_does_not_prove_feasibility",
        "original_input_reproduction"=>false,
    )
end
