"""
    R1Case

已验证的首批两电节点、两热节点教学案例。`data` 是显式 TOML 配置，`sha256` 绑定输入原字节。
输入单位 MW、MWh、kg/s、K、h；电网内部采用显式基值标幺制。不是通用实验平台。
"""
struct R1Case
    data::Dict{String,Any}
    sha256::String
end

"""
    load_case(path) -> R1Case

读取显式合成案例并检查单位、固定拓扑、数组长度、设备边界、初末状态与管道历史。
拒绝缺少必要输入、非有限数字、步长与建筑/储热标定不一致、风电疑点未解除的配置。
原论文输入不在此函数中猜测或补齐。
"""
function load_case(path)
    bytes = read(path)
    d = TOML.parse(String(copy(bytes)))
    required = (
        "schema",
        "origin",
        "units",
        "time",
        "electric",
        "heat",
        "devices",
        "building",
        "demand",
        "cost",
    )
    all(k -> haskey(d, k), required) || throw(ArgumentError("缺少案例顶层输入"))
    required_fields = Dict(
        "time" => ["T", "dt_h"],
        "electric" => [
            "nodes",
            "root",
            "from",
            "to",
            "S_base_MVA",
            "V_base_kV",
            "r_pu",
            "x_pu",
            "V_min_pu",
            "V_max_pu",
            "l_max_pu",
        ],
        "heat" => [
            "nodes",
            "supply_from",
            "return_from",
            "m",
            "rho_w",
            "A",
            "L",
            "c_w",
            "epsilon_W_mK",
            "tau_AM",
            "tau_min",
            "tau_max",
            "history_S",
            "history_R",
        ],
        "devices" => [
            "eta_G",
            "eta_loss",
            "P_CHP_min",
            "P_CHP_max",
            "H_CHP_min",
            "H_CHP_max",
            "P_EB_max",
            "COP_EB",
            "P_HP_max",
            "COP_HP",
            "BS_power_max",
            "E_BS_max",
            "E_BS_initial",
            "eta_BS_ch",
            "eta_BS_dis",
            "HS_power_max",
            "E_HS_max",
            "E_HS_initial",
            "eta_HS_ch",
            "eta_HS_dis",
            "eta_HS_loss",
            "storage_reference_dt_h",
            "storage_mode_scope",
        ],
        "building" => [
            "tau_initial",
            "tau_min",
            "tau_max",
            "eta_H",
            "U",
            "reference_dt_h",
            "eta_DH",
            "P_DH_max",
        ],
        "demand" => ["P_D", "Q_D", "P_PV_available", "P_WT_available", "tau_AM"],
        "cost" => ["grid_per_MWh", "CHP_per_MWh"],
    )
    for (section, fields) in required_fields
        d[section] isa AbstractDict || throw(ArgumentError("$section 必须为表"))
        all(k -> haskey(d[section], k), fields) || throw(ArgumentError("$section 缺少必要字段"))
    end
    d["schema"] == "r1-micro-v1" && d["origin"] == "synthetic" ||
        throw(ArgumentError("只接受标明合成来源的 v1 案例"))
    d["units"] == Dict(
        "power" => "MW",
        "energy" => "MWh",
        "mass_flow" => "kg/s",
        "temperature" => "K",
        "time" => "h",
    ) || throw(ArgumentError("单位必须显式匹配 MW/MWh/kg/s/K/h"))
    finite_tree(x) =
        x isa AbstractDict ? all(finite_tree, values(x)) :
        x isa AbstractVector ? all(finite_tree, x) : x isa Real ? isfinite(x) : true
    finite_tree(d) || throw(ArgumentError("输入含非有限值"))
    tm, e, h, v, b, dem, cost =
        (d[k] for k in ("time", "electric", "heat", "devices", "building", "demand", "cost"))
    T, Δt = tm["T"], tm["dt_h"]
    T isa Integer && 1 <= T <= 96 && Δt > 0 || throw(ArgumentError("时间索引或步长错误"))
    b["reference_dt_h"] == Δt == v["storage_reference_dt_h"] ||
        throw(ArgumentError("离散系数标定步长不一致"))
    e["nodes"] == [1, 2] && e["from"] == 1 && e["to"] == 2 && e["root"] == 1 ||
        throw(ArgumentError("本批只支持显式 1→2 径向支路"))
    h["nodes"] == [1, 2] && h["supply_from"] == 1 && h["return_from"] == 2 ||
        throw(ArgumentError("供回水方向不一致"))
    e["S_base_MVA"] > 0 &&
    e["V_base_kV"] > 0 &&
    e["r_pu"] >= 0 &&
    e["x_pu"] >= 0 &&
    e["l_max_pu"] > 0 || throw(ArgumentError("电网基值或支路参数错误"))
    0 < e["V_min_pu"] <= 1 <= e["V_max_pu"] || throw(ArgumentError("电压边界错误"))
    for key in ("P_D", "Q_D", "P_PV_available", "P_WT_available", "tau_AM")
        length(dem[key]) == T || throw(ArgumentError("$key 长度不等于 T"))
    end
    all(iszero, dem["P_WT_available"]) ||
        throw(ArgumentError("风电原式疑点未解除，案例暂不接入风电"))
    for key in ("P_D", "Q_D", "P_PV_available")
        all(>=(0), dem[key]) || throw(ArgumentError("$key 必须非负"))
    end
    all(>(0), dem["tau_AM"]) && all(>(0), h["history_S"]) && all(>(0), h["history_R"]) ||
        throw(ArgumentError("温度必须为 K"))
    length(cost["grid_per_MWh"]) == T &&
    all(>=(0), cost["grid_per_MWh"]) &&
    cost["CHP_per_MWh"] >= 0 || throw(ArgumentError("教学成本错误"))
    chp_heat(1.0, v["eta_G"], v["eta_loss"])
    0 <= v["P_CHP_min"] <= v["P_CHP_max"] && 0 <= v["H_CHP_min"] <= v["H_CHP_max"] ||
        throw(ArgumentError("CHP 边界错误"))
    for name in ("EB", "HP")
        v["P_$(name)_max"] >= 0 && v["COP_$name"] > 0 || throw(ArgumentError("转换设备参数错误"))
    end
    v["storage_mode_scope"] == "horizon" ||
        throw(ArgumentError("本批 z 按原式无 t 下标，固定于整个窗口"))
    for s in ("BS", "HS")
        0 <= v["E_$(s)_initial"] <= v["E_$(s)_max"] && v["$(s)_power_max"] >= 0 ||
            throw(ArgumentError("储能边界错误"))
        0 < v["eta_$(s)_ch"] <= 1 && 0 < v["eta_$(s)_dis"] <= 1 ||
            throw(ArgumentError("储能效率错误"))
    end
    # HS 原式效率方向未解除；教学闭环只接收与被动模型重合的单位效率特例。
    v["eta_HS_ch"] == v["eta_HS_dis"] == 1 && 0 < v["eta_HS_loss"] <= 1 ||
        throw(ArgumentError("耦合案例仅支持 HS 单位充放效率特例"))
    0 < b["tau_min"] <= b["tau_initial"] <= b["tau_max"] &&
    b["eta_H"] > 0 &&
    b["U"] >= 0 &&
    b["eta_DH"] > 0 &&
    b["P_DH_max"] >= 0 || throw(ArgumentError("建筑边界错误"))
    0 < h["tau_min"] < h["tau_max"] && h["tau_AM"] > 0 || throw(ArgumentError("热网温度边界错误"))
    kernel =
        fixed_flow_kernel(h["m"], h["rho_w"], h["A"], h["L"], Δt, h["epsilon_W_mK"]; c_w = h["c_w"])
    min(length(h["history_S"]), length(h["history_R"])) >= maximum(kernel.lags) ||
        throw(ArgumentError("供回水入口历史不足"))
    return R1Case(d, bytes2hex(sha256(bytes)))
end
