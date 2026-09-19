const R7_RECOVERY_CORE_FILE = @__FILE__

"""
    R7RecoveryCase(data)

第6章给定灾前边界和一个事件窗口的恢复输入。功率MW/Mvar、能量MWh、温度K、
流率kg/s、时间h；新能源场景加权，拓扑与管流跨场景共用。仅构造输入，不求解。
采用线性配电网、双水箱代理及原(6-12)电池和式容量；尚非完整灾前或嵌套模型。
"""
struct R7RecoveryCase
    data::Dict{String,Any}
    sha256::String
end

function r7_text(x)
    io = IOBuffer()
    TOML.print(io, x; sorted = true)
    String(take!(io))
end
r7_digest(x) = bytes2hex(sha256(IOBuffer(r7_text(x))))

function r7_numbers(x, shape, name; lo = -Inf, hi = Inf)
    x isa AbstractArray || error("$name必须显式提供数组")
    a = length(shape) == 1 ? Float64.(x) : reduce(vcat, permutedims.(Float64.(v) for v in x))
    size(a) == shape && all(y -> isfinite(y) && lo <= y <= hi, a) || error("$name形状或边界错误")
    a
end

function r7_connected_components(N, ends, z)
    adjacency = [Int[] for _ in 1:N]
    for (e, (i, j)) in enumerate(ends)
        z[e] == 1 || continue
        push!(adjacency[i], j)
        push!(adjacency[j], i)
    end
    groups = Vector{Int}[]
    seen = falses(N)
    for n in 1:N
        seen[n] && continue
        group, todo = Int[], [n]
        seen[n] = true
        while !isempty(todo)
            i = pop!(todo)
            push!(group, i)
            for j in adjacency[i]
                seen[j] && continue
                seen[j] = true
                push!(todo, j)
            end
        end
        push!(groups, sort(group))
    end
    groups
end

function R7RecoveryCase(input::AbstractDict)
    d = TOML.parse(r7_text(input))
    d["schema"] == "r7-recovery-case-v1" || error("恢复输入版本错误")
    d["origin"] in ("synthetic", "public_adapted", "thesis_verified") || error("来源缺失")
    !isempty(strip(d["name"])) && !isempty(strip(d["preplan_id"])) || error("缺案例或灾前计划身份")
    for (key, value) in (
        "power"=>"MW",
        "reactive"=>"Mvar",
        "energy"=>"MWh",
        "time"=>"h",
        "temperature"=>"K",
        "flow"=>"kg/s",
    )
        d["units"][key] == value || error("单位错误：$key")
    end
    T = d["periods"]
    T isa Integer && T > 0 || error("事件长度错误")
    isfinite(d["dt_h"]) && d["dt_h"] > 0 || error("时间步错误")
    d["event_start"] isa Integer && d["event_start"] >= 1 || error("事件起点错误")
    isfinite(d["renewable_factor"]) && 0 <= d["renewable_factor"] <= 1 ||
        error("事件新能源折减错误")
    isfinite(d["loss_limit_MWh"]) && d["loss_limit_MWh"] >= 0 || error("失供门槛错误")
    d["battery_rule"] == "paper_sum_bound" || error("首批不静默加入充放互斥")
    p = Float64.(d["probabilities"])
    !isempty(p) && all(isfinite, p) && all(>(0), p) && abs(sum(p)-1) <= 1e-8 ||
        error("场景概率错误")
    W = length(p)
    e, h = d["electric"], d["heat"]
    N, J = e["nodes"], h["nodes"]
    N isa Integer && N >= 1 && J isa Integer && J >= 2 || error("节点数错误")
    e["pcc_node"] isa Integer && 1 <= e["pcc_node"] <= N || error("PCC节点错误")
    e["flow_domain"] in ("forward_only", "signed") || error("须显式选择电支路方向解释")
    0 < e["v_min_pu"] <= e["v_ref_pu"] <= e["v_max_pu"] && e["S_base_MVA"] > 0 ||
        error("电压或标幺基准错误")
    all(isfinite, [e[k] for k in ("v_min_pu", "v_ref_pu", "v_max_pu", "S_base_MVA")]) || error("非有限电网边界")
    roots = r7_numbers(e["root_eligible"], (N,), "成网根节点"; lo = 0, hi = 1)
    all(isinteger, roots) || error("根资格必须为0/1")
    for line in e["lines"]
        i, j = line["from"], line["to"]
        i isa Integer && j isa Integer && 1 <= i <= N && 1 <= j <= N && i != j ||
            error("支路节点错误")
        line["base_closed"] in (0, 1) && line["vulnerable"] isa Bool || error("支路状态错误")
        for key in ("r_pu", "x_pu", "P_max_MW", "Q_max_Mvar")
            isfinite(line[key]) && line[key] >= 0 || error("支路参数错误")
        end
    end
    e["switch_budget"] isa Integer && e["switch_budget"] >= 0 || error("动作预算错误")
    e["fault_budget"] isa Integer &&
    0 <= e["fault_budget"] <= count(l->l["vulnerable"], e["lines"]) || error("故障预算错误")
    r7_numbers(e["load_MW"], (N, T), "电负荷"; lo = 0)
    r7_numbers(e["tan_phi"], (N,), "负荷无功比"; lo = 0)
    r7_numbers(e["shed_fraction_max"], (N,), "电负荷削减上限"; lo = 0, hi = 1)
    h["available"] === true || error("首批不支持供热网络自身故障")
    r7_numbers(h["load_MW"], (J, T), "热负荷"; lo = 0)
    r7_numbers(h["shed_fraction_max"], (J,), "热负荷削减上限"; lo = 0, hi = 1)
    for key in (
        "source_flow_max",
        "load_flow_max",
        "source_delta_min",
        "source_delta_max",
        "load_delta_min",
        "load_delta_max",
    )
        r7_numbers(h[key], (J,), key; lo = 0)
    end
    all(h["source_delta_min"] .<= h["source_delta_max"]) &&
    all(h["load_delta_min"] .<= h["load_delta_max"]) || error("端口温差范围错误")
    h["c_J_kgK"] > 0 && isfinite(h["c_J_kgK"]) && h["rho_kg_m3"] > 0 && isfinite(h["rho_kg_m3"]) ||
        error("水参数错误")
    r7_numbers(h["ambient_K"], (T,), "环境温度"; lo = 0)
    all(
        isfinite(h[key]) for
        key in ("S_min_K", "S_max_K", "R_min_K", "R_max_K", "S_reference_K", "R_reference_K")
    ) || error("非有限水箱温度")
    0 < h["R_min_K"] < h["R_max_K"] < h["S_min_K"] < h["S_max_K"] || error("水箱温度范围错误")
    h["S_min_K"] <= h["S_reference_K"] <= h["S_max_K"] &&
    h["R_min_K"] <= h["R_reference_K"] <= h["R_max_K"] || error("Taylor参考温度错误")
    maximum(h["ambient_K"]) <= h["R_min_K"] || error("首批须保持水温高于环境")
    r7_numbers(h["reference_flow_kg_s"], (T,), "参考循环流"; lo = 0)
    !isempty(h["pipes"]) || error("双水箱须有显式管内容积")
    ends = Tuple{Int,Int}[]
    for pipe in h["pipes"]
        i, j = pipe["from"], pipe["to"]
        i isa Integer && j isa Integer && 1<=i<=J && 1<=j<=J && i!=j || error("热管节点错误")
        push!(ends, (i, j))
        for key in (
            "volume_S_m3",
            "volume_R_m3",
            "flow_max_kg_s",
            "flow_change_max_kg_s",
            "UA_S_W_K",
            "UA_R_W_K",
        )
            isfinite(pipe[key]) && pipe[key] >= 0 || error("热管参数错误")
        end
        pipe["volume_S_m3"] > 0 && pipe["volume_R_m3"] > 0 || error("供回水容积必须分别为正")
        r7_numbers(
            pipe["normal_flow_kg_s"],
            (T,),
            "常态管流";
            lo = -pipe["flow_max_kg_s"],
            hi = pipe["flow_max_kg_s"],
        )
        r7_numbers(pipe["initial_S_K"], (W,), "灾前供水管温"; lo = h["S_min_K"], hi = h["S_max_K"])
        r7_numbers(pipe["initial_R_K"], (W,), "灾前回水管温"; lo = h["R_min_K"], hi = h["R_max_K"])
    end
    length(r7_connected_components(J, ends, ones(Int, length(ends)))) == 1 ||
        error("两个集总水箱不能跨不连通热网使用")
    ids = [dev["id"] for dev in d["devices"]]
    all(id -> id isa AbstractString && !isempty(strip(id)), ids) &&
    length(unique(ids)) == length(ids) || error("设备身份缺失或重复")
    for dev in d["devices"]
        dev["kind"] in ("CHP", "GT", "EB", "PV", "BES") || error("设备类别错误")
        n = dev["electric_node"]
        n isa Integer && 1 <= n <= N || error("设备电节点错误")
        isfinite(dev["P_max_MW"]) && dev["P_max_MW"] >= 0 || error("设备容量错误")
        if dev["kind"] in ("CHP", "GT")
            isfinite(dev["Q_max_Mvar"]) && dev["Q_max_Mvar"] >= 0 || error("无功容量错误")
        end
        if dev["kind"] in ("CHP", "EB")
            j = dev["heat_node"]
            j isa Integer && 1<=j<=J || error("产热节点错误")
            isfinite(dev["heat_ratio"]) && dev["heat_ratio"] > 0 || error("转换系数错误")
        end
        if dev["kind"] == "CHP"
            0 <= dev["P_min_MW"] <= dev["P_max_MW"] &&
            0 <= dev["Q_min_Mvar"] <= dev["Q_max_Mvar"] || error("CHP下界错误")
            u = r7_numbers(dev["commitment"], (T,), "继承启停"; lo = 0, hi = 1)
            all(isinteger, u) && dev["previous_commitment"] in (0, 1) || error("启停不是二值")
            r7_numbers(
                dev["previous_P_MW"],
                (W,),
                "故障前CHP出力";
                lo = dev["P_min_MW"]*dev["previous_commitment"],
                hi = dev["P_max_MW"]*dev["previous_commitment"],
            )
            for key in ("ramp_MW_h", "startup_MW", "shutdown_MW")
                isfinite(dev[key]) && dev[key] >= 0 || error("爬坡参数错误")
            end
        elseif dev["kind"] == "PV"
            r7_numbers(dev["available_MW"], (T, W), "新能源可用功率"; lo = 0, hi = dev["P_max_MW"])
        elseif dev["kind"] == "BES"
            0 <= dev["E_min_MWh"] <= dev["E_max_MWh"] && isfinite(dev["E_max_MWh"]) ||
                error("电池能量界错误")
            0 < dev["eta_ch"] <= 1 && 0 < dev["eta_dis"] <= 1 || error("电池效率错误")
            r7_numbers(
                dev["initial_MWh"],
                (W,),
                "继承电池能量";
                lo = dev["E_min_MWh"],
                hi = dev["E_max_MWh"],
            )
        end
    end
    for n in 1:N
        roots[n] == 0 && continue
        any(
            g->g["electric_node"]==n && g["kind"] in ("CHP", "GT", "BES") && g["P_max_MW"]>0,
            d["devices"],
        ) || error("成网根须有显式CHP/GT/电池；成网能力仍是输入假设")
    end
    for j in 1:J
        h["source_flow_max"][j] == 0 ||
            any(g->g["kind"] in ("CHP", "EB") && g["heat_node"]==j, d["devices"]) ||
            error("热源端口无设备")
    end
    R7RecoveryCase(d, r7_digest(d))
end

"""读取显式灾前边界与事件窗口；保存规范化输入及其哈希，不将手算边界冒充正常运行最优解。"""
load_r7_recovery_case(path::AbstractString) = R7RecoveryCase(TOML.parsefile(path))

function r7_recovery_assert(c)
    r7_digest(c.data) == c.sha256 || error("恢复输入在构造后改变")
end

"""
    r7_faults(case)

按(6-50)枚举不超过故障预算的全部线路组合，包含零内部断线；事件期PCC仍断开。
首批穷举限20条脆弱线路，超出时显式拒绝，不静默截断最坏情形集合。
"""
function r7_faults(c::R7RecoveryCase)
    r7_recovery_assert(c)
    lines = c.data["electric"]["lines"]
    eligible = findall(l->l["vulnerable"], lines)
    length(eligible) <= 20 || error("故障穷举超过首批规模；使用后续对手算法")
    out = Vector{Int}[]
    for mask in 0:(2^length(eligible)-1)
        count_ones(mask) <= c.data["electric"]["fault_budget"] || continue
        gamma = zeros(Int, length(lines))
        for (k, e) in enumerate(eligible)
            gamma[e] = (mask >> (k-1)) & 1
        end
        push!(out, gamma)
    end
    out
end

function r7_check_fault(c, gamma)
    ls = c.data["electric"]["lines"]
    length(gamma)==length(ls) && all(x->x in (0, 1), gamma) || error("故障向量错误")
    sum(gamma)<=c.data["electric"]["fault_budget"] &&
    all(i->ls[i]["vulnerable"]||gamma[i]==0, eachindex(ls)) || error("故障不在允许集合")
end

function r7_heat_constants(c)
    h = c.data["heat"]
    C = Dict(
        side=>h["c_J_kgK"]*h["rho_kg_m3"]*sum(p["volume_$(side)_m3"] for p in h["pipes"])/3.6e9
        for side in ("S", "R")
    )
    E0 = Dict(
        side=>[
            h["c_J_kgK"]*h["rho_kg_m3"]/3.6e9*sum(
                p["volume_$(side)_m3"]*(p["initial_$(side)_K"][w]-h["$(side)_min_K"]) for
                p in h["pipes"]
            ) for w in eachindex(c.data["probabilities"])
        ] for side in ("S", "R")
    )
    (; C, E0)
end

r7_pack(a) = Dict("shape"=>collect(size(a)), "data"=>Float64.(vec(Array(a))))
r7_unpack(v, k) = reshape(Float64.(v[k]["data"]), Tuple(Int.(v[k]["shape"])))
