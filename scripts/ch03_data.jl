module Ch03Data

using CSV, SHA, TOML, XLSX

const ROOT = normpath(joinpath(@__DIR__, ".."))

"""解析一个数字单元格，允许MATLAB行末分号；拒绝表达式、空白和NaN，不执行源文件代码。"""
function number(value; finite = true)
    ismissing(value) && error("必需数字为空，不能补零")
    result = if value isa Real
        Float64(value)
    elseif value isa AbstractString
        token = strip(replace(strip(value), r";$" => ""))
        occursin(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$|^[+-]?Inf$", token) ||
            error("不是数字字面量：$value")
        parse(Float64, token)
    else
        error("不支持的单元格类型")
    end
    (isnan(result) || (finite && !isfinite(result))) && error("不允许非有限数字")
    return result
end

"""按登记SHA-256读取本地原件，哈希不符立即失败。返回路径和来源回执，不调用网络。"""
function source_file(id)
    registry = TOML.parsefile(joinpath(ROOT, "docs", "reading", "ch03", "sources.toml"))
    source = only(filter(s -> s["id"] == id, registry["sources"]))
    path = joinpath(ROOT, "data", "raw", "ch03", id, source["sha256"], source["filename"])
    isfile(path) || error("缺少 $(id)，请先运行 collect_ch03_data.jl")
    verify_hash(path, source["sha256"])
    return path, source
end

"""校验实际字节SHA-256；不以文件存在或文件名作为完整性证据。"""
function verify_hash(path, expected)
    bytes2hex(sha256(read(path))) == expected || error("原件SHA-256不符")
    return true
end

"""解析MATPOWER已锁定文件中的纯数字矩阵；不执行MATLAB代码。"""
function literal_matrix(text, name, columns)
    clean = replace(text, r"%[^\n]*" => "")
    found = match(Regex("mpc\\." * name * "\\s*=\\s*\\[([^]]*)\\]", "s"), clean)
    isnothing(found) && error("缺少矩阵 $name")
    rows = filter(!isempty, strip.(split(found.captures[1], ';')))
    vectors = [number.(split(row)) for row in rows]
    all(row -> length(row) == columns, vectors) || error("$name 列数不符")
    return reduce(vcat, permutedims.(vectors))
end

"""检查无向网络的节点/端点唯一性、连通分量与独立环数。不把方向当作已知物理流向。"""
function graph_metrics(nodes, edges)
    ids = Int.(nodes)
    length(unique(ids)) == length(ids) || error("重复节点ID")
    isempty(ids) && error("节点集为空")
    adjacency = Dict(i => Int[] for i in ids)
    seen_edges = Set{Tuple{Int,Int}}()
    for (u0, v0) in edges
        u, v = Int(u0), Int(v0)
        u != v || error("自环")
        haskey(adjacency, u) && haskey(adjacency, v) || error("管线端点不存在")
        edge = minmax(u, v)
        edge in seen_edges && error("重复无向边，须显式建模并行管线后才能接受")
        push!(seen_edges, edge)
        push!(adjacency[u], v)
        push!(adjacency[v], u)
    end
    seen = Set{Int}()
    components = 0
    for id in ids
        id in seen && continue
        components += 1
        queue = [id]
        while !isempty(queue)
            node = pop!(queue)
            node in seen && continue
            push!(seen, node)
            append!(queue, adjacency[node])
        end
    end
    cycles = length(seen_edges) - length(ids) + components
    return Dict{String,Any}(
        "nodes" => length(ids),
        "edges" => length(seen_edges),
        "components" => components,
        "cycles" => cycles,
        "radial" => components == 1 && cycles == 0,
    )
end

"""核验电网拓扑、阻抗、额定电压和上下界；rateA=0保留为未给出上限，不当作零容量。"""
function electric_metrics(bus, branch)
    all(isfinite, bus) && all(isfinite, branch) || error("电网含非有限数")
    all(bus[:, 3:4] .>= 0) || error("负荷为负，需另行解释")
    all(bus[:, 10] .> 0) || error("额定电压须为正")
    all(bus[:, 12] .>= bus[:, 13]) || error("电压界倒置")
    all(branch[:, 3:4] .>= 0) || error("负阻抗")
    all(v -> v in (0, 1), branch[:, 11]) || error("支路状态不是0/1")
    # 包括停用支路在内检查引用；连通性单独按投入支路计算。
    graph_metrics(bus[:, 1], eachrow(branch[:, 1:2]))
    active = branch[:, 11] .== 1
    result = graph_metrics(bus[:, 1], eachrow(branch[active, 1:2]))
    result["open_branches"] = count(!, active)
    result["unknown_rateA"] = count(==(0), branch[:, 6])
    result["base_kV"] = unique(bus[:, 10])
    return result
end

"""读取锁定的case33bw，显式将kW/kvar转MW/Mvar、Ω转标幺；返回原始及转换矩阵。"""
function read_matpower()
    path, source = source_file("matpower-case33bw-8.1")
    text = read(path, String)
    bus = literal_matrix(text, "bus", 13)
    branch = literal_matrix(text, "branch", 13)
    base = number(match(r"mpc\.baseMVA\s*=\s*([\d.]+);", text).captures[1])
    base > 0 || error("基准容量非正")
    metrics = electric_metrics(bus, branch)
    bus_MW = copy(bus)
    bus_MW[:, 3:4] ./= 1000
    Z_base_ohm = bus[1, 10]^2 / base
    branch_pu = copy(branch)
    branch_pu[:, 3:4] ./= Z_base_ohm
    metrics["base_MVA"] = base
    metrics["Z_base_ohm"] = Z_base_ohm
    metrics["P_total_MW"] = sum(bus_MW[:, 3])
    metrics["Q_total_Mvar"] = sum(bus_MW[:, 4])
    metrics["S_aggregate_MVA"] = hypot(metrics["P_total_MW"], metrics["Q_total_Mvar"])
    return (; bus, branch, bus_MW, branch_pu, metrics, source)
end

"""读取固定来源的明确单元格范围。Inf只允许在已登记的压力界列，空格或表达式不自动修复。"""
function numeric_range(sheet, range; infinite_columns = Int[])
    values = sheet[range]
    result = Matrix{Float64}(undef, size(values))
    start = XLSX.CellRef(first(split(range, ':')))
    for index in CartesianIndices(values)
        formula = XLSX.getFormula(
            sheet,
            XLSX.row_number(start) + index[1] - 1,
            XLSX.column_number(start) + index[2] - 1,
        )
        isnothing(formula) || isempty(formula) || error("输入含Excel公式，须先核查缓存与计算来源")
        result[index] = number(values[index]; finite = !(index[2] in infinite_columns))
    end
    return result
end

"""检查有限、非负的节点功率序列（MW）。仅用样本索引；未核时间间隔时不计算MWh。"""
function load_metrics(load, nodes)
    size(load, 2) == nodes || error("负荷列数与节点数不符")
    all(isfinite, load) && all(load .>= 0) || error("负荷空缺/非有限/负值")
    totals = vec(sum(load; dims = 2))
    return Dict(
        "samples" => size(load, 1),
        "nodes" => nodes,
        "minimum_total_MW" => minimum(totals),
        "peak_total_MW" => maximum(totals),
        "time_step_status" => "unverified; no energy integration",
    ),
    totals
end

"""读取Xin Qin作者工作簿或Chun Qin的Figshare衍生版，显式保留不同模式与单元格出处。"""
function read_barry(id)
    path, source = source_file(id)
    xf = XLSX.readxlsx(path)
    original = id == "qin2021-author-workbook"
    es = original ? xf["electricity"] : xf["Modified Barry Island HE-IES"]
    hs = original ? xf["heat"] : es
    ranges = Dict(
        "bus" => "B8:N40",
        "branch" => "B54:N90",
        "P" => original ? "A105:AG200" : "A97:AG192",
        "pipe" => original ? "B5:I37" : "B198:I230",
        "node" => original ? "B43:I75" : "B236:K268",
        "H" => original ? "A127:AG222" : "A284:AG379",
        "ambient" => original ? "B228:B323" : "B384:B479",
    )
    bus, branch = numeric_range(es, ranges["bus"]), numeric_range(es, ranges["branch"])
    P = numeric_range(es, ranges["P"])
    pipe = numeric_range(hs, ranges["pipe"])
    node = numeric_range(hs, ranges["node"]; infinite_columns = original ? [7, 8] : [8, 9])
    H = numeric_range(hs, ranges["H"])
    ambient = numeric_range(hs, ranges["ambient"])
    e = electric_metrics(bus, branch)
    h = graph_metrics(node[:, 1], eachrow(pipe[:, 1:2]))
    all(pipe[:, 3:4] .> 0) || error("管长/管径非正")
    all(pipe[:, 5:6] .>= 0) || error("粗糙度/传热系数为负")
    all(pipe[:, 7] .<= pipe[:, 8]) || error("流量边界倒置")
    ts = original ? 3 : 4
    all(node[:, ts] .<= node[:, ts+1]) || error("供温边界倒置")
    all(node[:, ts+2] .<= node[:, ts+3]) || error("回温边界倒置")
    # 温度的单位在工作簿表头未显式给出，不以数值外观推断后自动加273.15。
    h["pipe_length_sum_m"] = sum(pipe[:, 3])
    h["reversible_pipe_bounds"] = count(<(0), pipe[:, 7])
    h["temperature_unit_status"] = "pending source verification; raw values only"
    h["supply_lower_raw"] = minimum(node[:, ts])
    h["supply_upper_raw"] = maximum(node[:, ts+1])
    e["base_MVA"] = 100.0 # 明确来源：两个工作簿的electricity/Barry表A3。
    pstats, P_total = load_metrics(P, size(bus, 1))
    hstats, H_total = load_metrics(H, size(node, 1))
    size(P, 1) == size(H, 1) == size(ambient, 1) || error("序列长度不一致")
    return (;
        id,
        source,
        bus,
        branch,
        pipe,
        node,
        P,
        H,
        ambient,
        P_total,
        H_total,
        metrics = Dict("electric" => e, "heat" => h, "P" => pstats, "H" => hstats),
        ranges,
        sheet_electric = XLSX.sheetnames(xf)[1],
        sheet_heat = original ? "heat" : XLSX.sheetnames(xf)[1],
    )
end

"""验证论文人工转录参数与图示连通性；保留CHP数量矛盾，不据装机和自动修正原文。"""
function check_thesis(data)
    system = data["system"]
    for group in ("pv", "chp", "converters")
        ids = [d["id"] for d in data[group]]
        length(ids) == length(unique(ids)) || error("重复设备ID")
        for d in data[group]
            1 <= d["electric_node"] <= system["electric_nodes"] || error("电设备节点越界")
            haskey(d, "heat_node") &&
                !(1 <= d["heat_node"] <= system["heat_nodes"]) &&
                error("热设备节点越界")
        end
    end
    pv = sum(d["rated_kW"] for d in data["pv"]) / 1000
    chp = sum(d["rated_kW"] for d in data["chp"]) / 1000
    pv ≈ system["pv_capacity_MW"] || error("PV装机不一致")
    pv + chp ≈ system["distributed_capacity_MW"] || error("总装机不一致")
    tariff = data["tariff"]
    tariff["start_h"][1] == 0 && tariff["end_h"][end] == 24 || error("电价未覆盖整日")
    tariff["end_h"][1:(end-1)] == tariff["start_h"][2:end] || error("电价时段重叠或缺口")
    all(tariff["end_h"] .> tariff["start_h"]) || error("电价时段倒置")
    all(tariff["price"] .> 0) || error("非正电价需核验")
    capacities = [
        Dict(
            "id" => d["id"],
            "H_max_MW" => d["rated_heat_kW"] / 1000,
            "P_max_MW_derived" => d["rated_heat_kW"] / 1000 / d["COP"],
        ) for d in data["converters"]
    ]
    all(d -> d["COP"] > 0 && d["rated_heat_kW"] > 0, data["converters"]) ||
        error("转换设备参数非正")
    return Dict(
        "PV_total_MW" => pv,
        "CHP_total_MW_interpreted" => chp,
        "heat_graph" => graph_metrics(1:system["heat_nodes"], data["heat_topology"]["edges"]),
        "converters" => capacities,
        "price_USD_per_MWh" => tariff["price"] .* 1000,
        "CHP_count_conflict" => system["CHP_count_in_prose"] != length(data["chp"]),
        "ready_for_dispatch" => false,
    )
end

end # module
