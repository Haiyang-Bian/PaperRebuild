"""
    load_r9_sources(directory)

读取第7章原始输入、图7-2连接和作者结果台账，保存每份台账的字节哈希。
这是原PDF127–143的小批次转录接口，不是调度案例加载器；不填补缺失线路、管道或时序。
运行不要求本地论文原件存在，若要核验扫描字节须另走来源检查。
"""
function load_r9_sources(directory)
    names=("inputs.toml", "topology.toml", "reported-results.toml")
    data=Dict{String,Any}()
    hashes=Dict{String,String}()
    for name in names
        b=read(joinpath(directory, name))
        data[name]=TOML.parse(String(copy(b)))
        hashes[name]=bytes2hex(sha256(b))
    end
    r9_source_check(data)
    (; data, hashes)
end

# 图边方向为项目从根定向；不从画图方向推断真实功率或水流。
function r9_graph(nodes, edges, root; tree = false)
    nodes isa Int && nodes>0 && root in 1:nodes || error("非法节点或根")
    seen_edges=Set{Tuple{Int,Int}}()
    neighbors=[Int[] for _ in 1:nodes]
    for edge in edges
        length(edge)==2 && all(x->x isa Int && x in 1:nodes, edge) || error("边端点非法")
        a, b=edge
        a!=b || error("不允许自环")
        pair=minmax(a, b)
        pair in seen_edges && error("重复无向边")
        push!(seen_edges, pair)
        push!(neighbors[a], b)
        push!(neighbors[b], a)
    end
    reached=Set([root])
    queue=[root]
    while !isempty(queue)
        a=pop!(queue)
        for b in neighbors[a]
            if b ∉ reached
                push!(reached, b)
                push!(queue, b)
            end
        end
    end
    length(reached)==nodes || error("网络不连通")
    cycles=length(edges)-nodes+1
    tree && cycles!=0 && error("声明为树的连接存在环")
    Dict("nodes"=>nodes, "edges"=>length(edges), "connected"=>true, "cycles"=>cycles)
end

function r9_source_check(data)
    d, g, t=(data[n] for n in ("inputs.toml", "topology.toml", "reported-results.toml"))
    d["schema"]=="r9-source-inputs-v1" &&
    g["schema"]=="r9-topology-transcription-v1" &&
    t["schema"]=="r9-author-targets-v1" || error("第7章台账版本错误")
    d["source_sha256"]==g["source_sha256"]==t["source_sha256"] &&
    occursin(r"^[a-f0-9]{64}$", d["source_sha256"]) || error("来源身份不一致")
    d["status"]=="partial_original_input_not_runnable" &&
    !g["electrical_parameters_available"] &&
    !g["thermal_parameters_available"] || error("原始数据缺口不能被转录检查改成完成")
    for (key, nkey, ekey) in (
        ("electric", "electric_nodes", "electric_edges"),
        ("heat", "heat_nodes", "heat_pipe_pairs"),
    )
        x=g[key]
        x["nodes"]==d["base"][nkey] && length(x["edges"])==d["base"][ekey] ||
            error("拓扑数目与文字不同")
        r9_graph(x["nodes"], x["edges"], x["root"]; tree = true)
    end
    for (group, kind) in (
        ("base", "pv"),
        ("base", "chp"),
        ("base", "eb"),
        ("trading", "chp"),
        ("trading", "eb"),
        ("trading", "battery"),
        ("trading", "aggregators"),
        ("reserve", "p2h"),
        ("resilience", "chp"),
        ("resilience", "gt"),
    )
        items=d[group][kind]
        length(unique(x["id"] for x in items))==length(items) || error("主体/设备ID重复")
        for x in items
            x["electric_node"] in 1:g["electric"]["nodes"] || error("设备电节点不存在")
            haskey(x, "heat_node") &&
                !(x["heat_node"] in 1:g["heat"]["nodes"]) &&
                error("设备热节点不存在")
            for (k, v) in x
                v isa Real && !(isfinite(v) && v>=0) && error("负值或非有限参数：$k")
            end
            haskey(x, "P_min_MW") && x["P_min_MW"]>x["P_max_MW"] && error("出力界倒置")
            haskey(x, "eta") && !(0<x["eta"]<=1) && error("电热转换效率错误")
        end
    end
    d["reserve"]["market_role"]=="price_taker" || error("第7.4节不是策略定价案例")
    d["resilience"]["penalty_CNY_MWh"]==1000*d["resilience"]["penalty_literal_CNY_kWh"] ||
        error("失供罚价单位未转换")
    !d["base"]["electric_peak_is_active_power"] || error("MVA峰值不得静默视为MW")
    for side in ("electric", "heat")
        x=g[side]
        r9_graph(x["nodes"], vcat(x["edges"], d["trading"]["new_$(side)_ties"]), x["root"])
    end
    length(unique(x["id"] for x in d["gaps"]))==length(d["gaps"]) || error("缺口ID重复")
    Set("R9-D0$i" for i in 1:7) ⊆ Set(x["id"] for x in d["gaps"]) ||
        error("本版原始输入缺口不能通过删除登记消失")
    for section in ("7.2", "7.3", "7.4", "7.5")
        any(x -> section in x["scope"], d["gaps"]) || error("缺失场景输入门槛")
    end
    # 台账含不同维度的数值数组；只要求同一张表内与行标签严格对应。
    for (table, labels) in (
        ("four_modes", "mode"),
        ("bargaining", "actor"),
        ("trading", "scheme"),
        ("reserve", "scheme"),
        ("resilience", "scheme"),
        ("commitment", "hours"),
        ("iterations", "iteration"),
    )
        block=t[table]
        n=length(block[labels])
        n>0 && length(unique(block[labels]))==n || error("作者表格行标重复或缺失")
        for (key, value) in block
            if value isa Vector && key!=labels
                length(value)==n && all(x -> x isa Real && isfinite(x), value) ||
                    error("作者表格 $table/$key 数值长度或类型错误")
            end
        end
    end
    r9_tariff(d, collect(0:23))
    nothing
end

"""
    r9_tariff(input_ledger, hour_starts)

按原表7-4返回CNY/MWh价格。项目明确以半开区间和小时起点解释钟点；
24点应写作下一日0点，不悄悄模24。跨午夜谷段拆成[21,24)和[0,5)。
不把该零售分时价用于7.4的外生市场价。
"""
function r9_tariff(d, hours)
    tariff=d["base"]["tariff"]
    result=Float64[]
    for h in hours
        isfinite(h) && 0<=h<24 || error("小时起点须在[0,24)")
        hit=String[]
        for band in ("peak", "flat", "valley"), interval in tariff[band*"_intervals_h"]
            length(interval)==2 && 0<=interval[1]<interval[2]<=24 || error("费率区间错误")
            interval[1]<=h<interval[2] && push!(hit, band)
        end
        length(hit)==1 || error("费率区间缺失或重叠")
        p=tariff[only(hit)*"_CNY_MWh"]
        isfinite(p) && p>=0 || error("电价非法")
        push!(result, p)
    end
    result
end

"""
    r9_original_input_gate(bundle, section; require_complete=false)

返回7.2–7.5各自尚缺的原始输入；require_complete=true时拒绝不完整的作者同输入运行。
该门槛不禁止另行冻结、明确标注来源及假设的替代算例；不能用作者结果表反求缺失参数。
"""
function r9_original_input_gate(bundle, section; require_complete = false)
    section in ("7.2", "7.3", "7.4", "7.5") || error("未知第7章子任务")
    r9_source_check(bundle.data)
    gaps=[deepcopy(g) for g in bundle.data["inputs.toml"]["gaps"] if section in g["scope"]]
    require_complete &&
        !isempty(gaps) &&
        error("作者同输入尚不完整："*join(getindex.(gaps, "id"), ", "))
    Dict("section"=>section, "original_input_ready"=>isempty(gaps), "gaps"=>gaps)
end
