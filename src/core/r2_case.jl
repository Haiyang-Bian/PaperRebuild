"""
    R2Case(data, sha256)

第3章合成案例及原始配置哈希。规范化单位为 MW、MWh、K、kg/s、h；管道几何和物性用 SI，
压力用 kPa，电网用显式 MVA/kV 基准的标幺值。使用 [`load_r2_case`](@ref) 验证后构造。
"""
struct R2Case
    data::Dict{String,Any}
    sha256::String
end

"""
    R2Spec(; formulation=:wmm_checked_v1, heat_balance=nothing, loss=nothing, ...)

模型解释与独立近似开关。WMM 默认 exact/wmm/exact/wmm；SCHPD 默认 mc/reference/dominant/fv，
分别表示热功率、热损耗、节点混合、管温动态。改变开关会改变数学模型，必须随运行保存。
literal 版本当前有未解除的原式阻断，构建时显式返回 blocked，不替换为项目补全版。
"""
struct R2Spec
    formulation::Symbol
    heat_balance::Symbol
    loss::Symbol
    mixing::Symbol
    dynamics::Symbol
    dynamics_product::Symbol
end
function R2Spec(;
    formulation = :wmm_checked_v1,
    heat_balance = nothing,
    loss = nothing,
    mixing = nothing,
    dynamics = nothing,
    dynamics_product = nothing,
)
    formulation in (:wmm_literal, :wmm_checked_v1, :schpd_literal, :schpd_mc_v1) ||
        throw(ArgumentError("未知 R2 模型版本"))
    wmm = startswith(string(formulation), "wmm")
    h = isnothing(heat_balance) ? (wmm ? :exact : :mc) : heat_balance
    l = isnothing(loss) ? (wmm ? :wmm : :reference) : loss
    m = isnothing(mixing) ? (wmm ? :exact : :dominant) : mixing
    d = isnothing(dynamics) ? (wmm ? :wmm : :fv) : dynamics
    dp = isnothing(dynamics_product) ? (wmm ? :exact : :mc) : dynamics_product
    h in (:exact, :mc) &&
    l in (:wmm, :reference, :dynamic) &&
    m in (:exact, :dominant) &&
    d in (:wmm, :fv) &&
    dp in (:exact, :mc) || throw(ArgumentError("非法近似开关"))
    (d == :wmm && l == :dynamic || d == :fv && l == :wmm) &&
        throw(ArgumentError("损耗开关与动态离散不兼容"))
    return R2Spec(formulation, h, l, m, d, dp)
end

function r2_tree(edges, n)
    length(edges) == n - 1 || throw(ArgumentError("需要有 n-1 条边的径向树"))
    parents = zeros(Int, n)
    reached = Set([1])
    for e in edges
        i, j = e["from"], e["to"]
        1 <= i <= n && 2 <= j <= n && i != j && parents[j] == 0 ||
            throw(ArgumentError("非法端点、重复父节点或根入边"))
        parents[j] = i
    end
    for _ in 1:n, e in edges
        e["from"] in reached && push!(reached, e["to"])
    end
    length(reached) == n || throw(ArgumentError("网络不连通或有环"))
end

# region r2-input
"""
    load_r2_case(path)

读取 TOML 合成小系统。核查径向电/热拓扑、全部单位、时序、有限边界、正流量与历史覆盖。
热源/负荷端口流量均用正幅值，质量守恒按节点角色取符号（项目补全 R2-C01）。
第3章作者原始输入尚不完整；本接口不自动把公开工作簿变成作者算例。
"""
function load_r2_case(path)
    bytes = read(path)
    d = TOML.parse(String(copy(bytes)))
    validate_r2_input(d)
    return R2Case(d, bytes2hex(sha256(bytes)))
end

function validate_r2_input(d)
    d["schema"] == "r2-case-v1" || throw(ArgumentError("不支持的输入schema"))
    d["origin"] == "synthetic" || throw(ArgumentError("本批仅接收标明 synthetic 的案例"))
    d["units"] == Dict(
        "power" => "MW",
        "energy" => "MWh",
        "temperature" => "K",
        "flow" => "kg/s",
        "time" => "h",
        "pressure" => "kPa",
    ) || throw(ArgumentError("单位契约不匹配"))
    finite_positive(x) = isfinite(x) && x > 0
    T, dt = d["T"], d["dt_h"]
    T isa Int && T > 0 && finite_positive(dt) || throw(ArgumentError("非法时间轴"))
    function series(x; nonnegative = false)
        length(x) == T && all(isfinite, x) && (!nonnegative || all(>=(0), x)) ||
            throw(ArgumentError("非法时序长度或数值"))
    end
    for field in ("grid_price", "ambient_K")
        series(d[field])
    end
    all(>=(0), d["grid_price"]) || throw(ArgumentError("首批电价非负"))
    all(>(0), d["ambient_K"]) || throw(ArgumentError("绝对温度必须为正"))
    e, h = d["electric"], d["heat"]
    n, k = length(e["nodes"]), length(h["nodes"])
    r2_tree(e["edges"], n)
    r2_tree(h["pipes"], k)
    e["v_min_pu"] > 0 &&
    e["v_min_pu"] <= 1 <= e["v_max_pu"] &&
    finite_positive(e["base_MVA"]) &&
    finite_positive(e["base_kV"]) &&
    finite_positive(e["grid_max_MW"]) || throw(ArgumentError("非法电基值或边界"))
    for node in e["nodes"]
        series(node["P_MW"]; nonnegative = true)
        series(node["Q_Mvar"]; nonnegative = true)
    end
    for edge in e["edges"]
        all(x -> isfinite(x) && x >= 0, [edge["r_pu"], edge["x_pu"]]) &&
        finite_positive(edge["ell_max_pu"]) || throw(ArgumentError("非法支路参数"))
    end
    for key in ("rho_kg_m3", "cp_J_kgK", "pressure_max_kPa")
        finite_positive(h[key]) || throw(ArgumentError("非法物性或压力"))
    end
    for side in ("S", "R")
        b = h[side*"_bounds_K"]
        length(b) == 2 && all(isfinite, b) && 0 < b[1] <= b[2] ||
            throw(ArgumentError("非法管温边界"))
        b[1] <= h[side*"_reference_K"] <= b[2] || throw(ArgumentError("参考温度越界"))
    end
    h["S_bounds_K"][1] > h["R_bounds_K"][2] || throw(ArgumentError("首批要求供水高于回水"))
    for node in h["nodes"]
        node["role"] in ("source", "load", "transit") || throw(ArgumentError("未知热节点角色"))
        series(node["H_MW"]; nonnegative = true)
        node["role"] == "load" ||
            all(iszero, node["H_MW"]) ||
            throw(ArgumentError("只有负荷节点有需求"))
        0 <= node["flow_min"] <= node["flow_max"] && isfinite(node["flow_max"]) ||
            throw(ArgumentError("非法端口流量界"))
        h["R_bounds_K"][1] <= node["return_K"] <= h["R_bounds_K"][2] ||
            throw(ArgumentError("回水边界越界"))
    end
    for pipe in h["pipes"]
        all(finite_positive, [pipe[x] for x in ("area_m2", "length_m", "flow_min", "flow_max")]) && pipe["flow_min"] <= pipe["flow_max"] ||
            throw(ArgumentError("管内流量必须严格正向且有界"))
        all(x -> isfinite(x) && x >= 0, [pipe["epsilon_W_mK"], pipe["mu_kPa_s2_kg2"]]) ||
            throw(ArgumentError("非法损耗或摩阻"))
        history = pipe["flow_history"]
        M = h["rho_kg_m3"] * pipe["area_m2"] * pipe["length_m"]
        Td = ceil(Int, M / (3600 * dt * pipe["flow_min"])) + 1
        length(history) >= Td && all(x -> pipe["flow_min"] <= x <= pipe["flow_max"], history) ||
            throw(ArgumentError("历史流量长度不足或越界"))
        for side in ("S", "R")
            a = pipe[side*"_history_K"]
            b = h[side*"_bounds_K"]
            length(a) == length(history) && all(x -> b[1] <= x <= b[2], a) ||
                throw(ArgumentError("入口历史温度缺失或越界"))
        end
        series(pipe["fixed_flow"])
        all(x -> pipe["flow_min"] <= x <= pipe["flow_max"], pipe["fixed_flow"]) ||
            throw(ArgumentError("固定流量参考越界"))
    end
    for g in d["devices"]
        g["kind"] in ("CHP", "EB", "PV", "GT") && 1 <= g["electric_node"] <= n ||
            throw(ArgumentError("非法设备类型或电节点"))
        0 <= g["P_min"] <= g["P_max"] &&
        all(isfinite, [g["P_min"], g["P_max"], g["cost_per_MWh"]]) ||
            throw(ArgumentError("非法设备边界"))
        if g["kind"] in ("CHP", "EB")
            1 <= g["heat_node"] <= k &&
            h["nodes"][g["heat_node"]]["role"] == "source" &&
            finite_positive(g["heat_ratio"]) || throw(ArgumentError("非法热设备映射"))
        end
        series(g["availability"]; nonnegative = true)
        all(x -> x <= g["P_max"], g["availability"]) || throw(ArgumentError("可用出力超过容量"))
    end
    return nothing
end
# endregion r2-input
