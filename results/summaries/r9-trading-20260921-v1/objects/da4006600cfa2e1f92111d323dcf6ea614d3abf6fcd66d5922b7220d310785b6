"""
    R9TradingCase(data)

第7.3节多主体交易输入；主体、电节点、热节点和设备分别编号，允许多个主体共用节点。
功率MW、能量MWh、流量kg/s、温度K、时间h、货币CNY。保存原文本及哈希，检查有限边界。
这是独立规模接口，不改变旧R4Case，也不将稳态能量/质量包络称为完整温度或水力模型。
"""
struct R9TradingCase
    data::Dict{String,Any}
    sha256::String
    source_text::String
end

function R9TradingCase(data::AbstractDict)
    text=r4_text(data)
    d=TOML.parse(text)
    r9_trading_check(d)
    R9TradingCase(d, bytes2hex(sha256(text)), text)
end

"""读取冻结的R9交易TOML，保留原字节哈希；拒绝错误单位、归属、容量、偏好与时序。"""
function load_r9_trading_case(path::AbstractString)
    text=read(path, String)
    d=TOML.parse(text)
    r9_trading_check(d)
    R9TradingCase(d, bytes2hex(sha256(text)), text)
end

function r9_trading_check(d)
    d["schema"]=="r9-trading-case-v1" && d["origin"]=="synthetic" || error("交易输入身份错误")
    d["units"]==Dict(
        "power"=>"MW",
        "energy"=>"MWh",
        "flow"=>"kg/s",
        "temperature"=>"K",
        "time"=>"h",
        "money"=>"CNY",
    ) || error("交易单位错误")
    pos(x) = x isa Real && isfinite(x) && x>0
    nonneg(x) = x isa Real && isfinite(x) && x>=0
    T=d["T"]
    T isa Int && T>0 && pos(d["dt_h"]) || error("交易时域错误")
    seq(x) = length(x)==T && all(nonneg, x)
    seq(d["grid_price"]) || error("外部电价错误")
    e, h=d["electric"], d["heat"]
    n, k=e["nodes"], h["nodes"]
    r9_graph(n, [[x["from"], x["to"]] for x in e["edges"]], e["root"]; tree = true)
    r9_graph(k, [[x["from"], x["to"]] for x in h["pipes"]], h["root"]; tree = true)
    for key in ("base_MVA", "base_kV", "grid_max_MW", "grid_Q_max_Mvar", "v_min_pu", "v_max_pu")
        pos(e[key]) || error("电网有限正边界缺失：$key")
    end
    e["v_min_pu"]<=1<=e["v_max_pu"] || error("根电压越界")
    for key in ("P_background_MW", "Q_background_Mvar")
        length(e[key])==n && all(seq, e[key]) || error("非市场电负荷错误")
    end
    length(h["H_background_MW"])==k && all(seq, h["H_background_MW"]) || error("非市场热负荷错误")
    for edge in e["edges"]
        all(nonneg(edge[x]) for x in ("r_pu", "x_pu")) &&
        all(pos(edge[x]) for x in ("P_max_MW", "Q_max_Mvar", "ell_max_pu")) || error("线路参数非法")
    end
    pos(h["cp_J_kgK"]) && 0<h["delta_min_K"]<=h["delta_max_K"]<Inf || error("热量转换参数错误")
    h["model"]=="steady_energy_mass_envelope" || error("未知热网域")
    for pipe in h["pipes"]
        all(pos(pipe[x]) for x in ("H_max_MW", "flow_max_kg_s", "length_m")) &&
        nonneg(pipe["U_W_mK"]) || error("管道边界错误")
        all(pos(pipe[x]) for x in ("S_ref_K", "R_ref_K", "ambient_K")) &&
        pipe["S_ref_K"]>pipe["R_ref_K"]>=pipe["ambient_K"] || error("管道参考温度错误")
        isapprox(pipe["loss_MW"], r4_loss(pipe); atol = 1e-14, rtol = 0) &&
        0<=pipe["loss_MW"]<pipe["H_max_MW"] || error("冻结热损耗错误")
    end
    actors=d["actors"]
    length(actors)>=2 &&
    actors[1]["id"]=="DSO" &&
    actors[1]["electric_node"]==actors[1]["heat_node"]==0 || error("运营商索引错误")
    allunique(x["id"] for x in actors) || error("重复主体ID")
    for (i, a) in enumerate(actors)
        i==1 || (a["electric_node"] in 1:n && a["heat_node"] in 1:k) || error("主体节点非法")
        0<=a["flex"]<1 && nonneg(a["Q_ratio"]) || error("负荷域错误")
        for carrier in ("P", "H")
            seq(a[carrier*"_load"]) && seq(a[carrier*"_preferred"]) && nonneg(a["sat_"*carrier]) ||
                error("偏好/负荷非法")
        end
        pos(a["retail_limit_MW"]) || error("交易须有有限边界")
    end
    all(iszero, actors[1]["P_load"]) && all(iszero, actors[1]["H_load"]) ||
        error("DSO非市场负荷须逐节点登记")
    allunique(g["id"] for g in d["devices"]) || error("重复设备ID")
    for g in d["devices"]
        kind=g["kind"]
        kind in ("CHP", "PV", "P2H", "BS", "HS") || error("未知设备")
        g["owner"] in eachindex(actors) || error("设备主体错误")
        (kind=="HS" ? g["electric_node"]==0 : g["electric_node"] in 1:n) || error("设备电节点错误")
        (kind in ("PV", "BS") ? g["heat_node"]==0 : g["heat_node"] in 1:k) ||
            error("设备热节点错误")
        if g["owner"]>1
            a=actors[g["owner"]]
            g["electric_node"] in (0, a["electric_node"]) &&
            g["heat_node"] in (0, a["heat_node"]) || error("设备越过主体端口")
        end
        all(
            nonneg(g[x]) for x in (
                "power_max_MW",
                "power_min_MW",
                "energy_max_MWh",
                "initial_MWh",
                "cost_CNY_MWh",
                "heat_ratio",
            )
        ) || error("设备参数错误")
        g["power_min_MW"]<=g["power_max_MW"] && g["initial_MWh"]<=g["energy_max_MWh"] ||
            error("设备初态/边界错误")
        all(0<g[x]<=1 for x in ("eta_ch", "eta_dis")) && 0<=g["loss_per_h"]<1 ||
            error("储能效率/损耗错误")
        seq(g["availability_MW"]) &&
        all(g["power_min_MW"] .<= g["availability_MW"] .<= g["power_max_MW"]) ||
            error("可用出力错误")
        kind in ("CHP", "P2H") && !pos(g["heat_ratio"]) && error("热电转换比缺失")
        kind in ("BS", "HS") ||
            (g["energy_max_MWh"]==g["initial_MWh"]==0) ||
            error("非储能设备带入能量状态")
    end
    s=d["settlement"]
    for key in ("P_buy", "P_sell", "H_buy", "H_sell", "P_peer", "H_peer", "fee")
        seq(s[key]) || error("结算时序错误")
    end
    all(s["P_buy"] .> s["P_sell"]) && all(s["H_buy"] .> s["H_sell"]) || error("买卖价差错误")
    return true
end

"""
    r9_trading_case(source_directory, protocol_path)

按原图44电/38热节点、表7-6至7-9构造八聚合商的24小时替代输入（R9-T1—T4）。
表7-9按放大前数据解释，聚合负荷只乘一次1.5；其余负荷由原总量减原表合计后分配。
同一热节点的主体负荷分别保存，网络注入时再求和；原节点编号不变。
设备归属与电热节点分开；不继承7.2的6MW光伏、WMM历史或终端温度。
缺失储热、偏好、价格、网络参数由先验协议明确给定，不读取作者收益或优化结果。
"""
function r9_trading_case(source_directory, protocol_path)
    bundle=load_r9_sources(source_directory)
    p=TOML.parsefile(protocol_path)
    p["schema"]=="r9-trading-protocol-v1" && p["T"]==24 && p["dt_h"]==1 ||
        error("协议时域/版本错误")
    p["load_table_rule"]=="table_7_9_before_factor; multiply_aggregators_once_by_1_5" ||
        error("未声明负荷解释")
    p["p2h_rule"]=="numerical_EB_tables_define_conversion; HP_label_does_not_add_unlisted_capacity" ||
        error("未声明P2H解释")
    s, topology=bundle.data["inputs.toml"], bundle.data["topology.toml"]
    base, tr=s["base"], s["trading"]
    ep, hp, sp=p["electric"], p["heat"], p["storage"]
    T=p["T"]
    for key in ("electric_profile", "heat_profile", "pv_profile")
        length(p[key])==T && all(x->isfinite(x)&&0<=x<=1, p[key]) && maximum(p[key])==1 ||
            error("比例时序错误")
    end
    pf=ep["power_factor"]
    0<pf<=1 || error("功率因数非法")
    ratio=sqrt(1-pf^2)/pf
    actors=Dict{String,Any}[]
    for a in [
        Dict("id"=>"DSO", "electric_node"=>0, "heat_node"=>0, "electric_MW"=>0.0, "heat_MW"=>0.0);
        tr["aggregators"]
    ]
        loadP=tr["load_factor"]*a["electric_MW"] .* p["electric_profile"]
        loadH=tr["load_factor"]*a["heat_MW"] .* p["heat_profile"]
        push!(
            actors,
            Dict(
                "id"=>a["id"],
                "electric_node"=>a["electric_node"],
                "heat_node"=>a["heat_node"],
                "P_load"=>loadP,
                "H_load"=>loadH,
                "P_preferred"=>copy(loadP),
                "H_preferred"=>copy(loadH),
                "flex"=>p["demand"]["flex_fraction"],
                "sat_P"=>p["demand"]["dissatisfaction_CNY_h_MW2"],
                "sat_H"=>p["demand"]["dissatisfaction_CNY_h_MW2"],
                "Q_ratio"=>ratio,
                "retail_limit_MW"=>p["settlement"]["retail_limit_MW"],
            ),
        )
    end
    owner(e) = something(findfirst(a->a["electric_node"]==e, actors), 1)
    devices=Dict{String,Any}[]
    function add(
        id,
        kind,
        own,
        en,
        hn,
        cap;
        lo = 0.0,
        cost = 0.0,
        heat_ratio = 0.0,
        energy = 0.0,
        eta_ch = 1.0,
        eta_dis = 1.0,
        loss = 0.0,
        availability = fill(cap, T),
        source = "thesis",
    )
        push!(
            devices,
            Dict(
                "id"=>id,
                "kind"=>kind,
                "owner"=>own,
                "electric_node"=>en,
                "heat_node"=>hn,
                "power_max_MW"=>cap,
                "power_min_MW"=>lo,
                "availability_MW"=>availability,
                "heat_ratio"=>heat_ratio,
                "energy_max_MWh"=>energy,
                "initial_MWh"=>energy*sp["initial_fraction"],
                "eta_ch"=>eta_ch,
                "eta_dis"=>eta_dis,
                "loss_per_h"=>loss,
                "cost_CNY_MWh"=>cost,
                "origin"=>source,
            ),
        )
    end
    for g in tr["chp"]
        add(
            g["id"],
            "CHP",
            owner(g["electric_node"]),
            g["electric_node"],
            g["heat_node"],
            g["P_max_MW"];
            lo = g["P_min_MW"],
            cost = g["fuel_CNY_MWh_electric"],
            heat_ratio = g["H_over_P"],
        )
    end
    for g in [base["eb"]; tr["eb"]]
        add(
            g["id"],
            "P2H",
            owner(g["electric_node"]),
            g["electric_node"],
            g["heat_node"],
            g["H_max_MW"]/g["eta"];
            heat_ratio = g["eta"],
        )
    end
    for g in base["pv"]
        add(
            g["id"],
            "PV",
            owner(g["electric_node"]),
            g["electric_node"],
            0,
            g["P_max_MW"];
            cost = g["cost_CNY_MWh"],
            availability = g["P_max_MW"] .* p["pv_profile"],
        )
    end
    for g in tr["battery"]
        add(
            g["id"],
            "BS",
            owner(g["electric_node"]),
            g["electric_node"],
            0,
            g["P_max_MW"];
            cost = g["cost_CNY_MWh"],
            energy = g["E_max_MWh"],
            eta_ch = sp["battery_eta_ch"],
            eta_dis = sp["battery_eta_dis"],
            loss = sp["battery_loss_per_h"],
        )
    end
    for (q, id) in enumerate(sp["heat_owners"])
        i=only(findall(a->a["id"]==id, actors))
        add(
            "HS$q",
            "HS",
            i,
            0,
            actors[i]["heat_node"],
            sp["heat_power_MW"];
            cost = sp["heat_cycle_CNY_MWh"],
            energy = sp["heat_energy_MWh"],
            eta_ch = sp["heat_eta_ch"],
            eta_dis = sp["heat_eta_dis"],
            loss = sp["heat_loss_per_h"],
            source = "synthetic_missing_heat_storage",
        )
    end
    n, k=44, 38
    activeP=[a["electric_node"] for a in actors[2:end]]
    activeH=unique(a["heat_node"] for a in actors[2:end])
    othersP=setdiff(1:n, [44; activeP])
    othersH=setdiff(1:k, [1; activeH])
    missingP=base["electric_peak_MVA"]*pf-sum(a["electric_MW"] for a in tr["aggregators"])
    missingH=base["heat_peak_MW"]-sum(a["heat_MW"] for a in tr["aggregators"])
    missingP>=0 && missingH>=0 || error("原表合计超过基础总量，不能负数分摊")
    bgP=[j in othersP ? missingP/length(othersP) : 0.0 for j in 1:n]
    bgH=[j in othersH ? missingH/length(othersH) : 0.0 for j in 1:k]
    baseP, baseH=copy(bgP), copy(bgH)
    for a in tr["aggregators"]
        baseP[a["electric_node"]]+=a["electric_MW"]
        baseH[a["heat_node"]]+=a["heat_MW"]
    end
    # 网络额定包络用7.1设备与未放大负荷设计；不根据7.3优化结果增容。
    envelopeP=copy(baseP)
    envelopeQ=ratio .* baseP
    envelopeH=copy(baseH)
    for g in base["chp"]
        envelopeP[g["electric_node"]]+=g["P_max_MW"]
        envelopeH[g["heat_node"]]+=g["P_max_MW"]*g["H_over_P"]
    end
    for g in base["eb"]
        envelopeP[g["electric_node"]]+=g["H_max_MW"]/g["eta"]
        envelopeH[g["heat_node"]]+=g["H_max_MW"]
    end
    for g in base["pv"]
        envelopeP[g["electric_node"]]+=g["P_max_MW"]
    end
    ee, hh=topology["electric"]["edges"], topology["heat"]["edges"]
    order, depth=r9_tree_order(n, ee, 44)
    for j in reverse(order[2:end])
        i=only(x[1] for x in ee if x[2]==j)
        envelopeP[i]+=envelopeP[j]
        envelopeQ[i]+=envelopeQ[j]
    end
    hedges, _=r9_tree_order(k, hh, 1)
    for j in reverse(hedges[2:end])
        i=only(x[1] for x in hh if x[2]==j)
        envelopeH[i]+=envelopeH[j]
    end
    edges=Dict{String,Any}[]
    for (i, j) in ee
        P, Q=envelopeP[j]/ep["base_MVA"], envelopeQ[j]/ep["base_MVA"]
        r=ep["path_squared_voltage_drop_budget"]/(2maximum(depth)*(P+ep["x_over_r"]*Q))
        push!(
            edges,
            Dict(
                "from"=>i,
                "to"=>j,
                "r_pu"=>r,
                "x_pu"=>r*ep["x_over_r"],
                "P_max_MW"=>ep["capacity_factor"]*envelopeP[j],
                "Q_max_Mvar"=>ep["capacity_factor"]*envelopeQ[j],
                "ell_max_pu"=>(ep["capacity_factor"]*hypot(P, Q)/ep["v_min_pu"])^2,
            ),
        )
    end
    pipes=Dict{String,Any}[]
    for (i, j) in hh
        design=envelopeH[j]
        mass=design/(hp["cp_J_kgK"]/1e6*(hp["S_reference_K"]-hp["R_reference_K"]))
        area=mass/(hp["rho_kg_m3"]*hp["velocity_m_s"])
        diameter=sqrt(4area/pi)
        U=2pi*hp["insulation_W_mK"]/log((diameter+2hp["insulation_thickness_m"])/diameter)
        cap=hp["capacity_factor"]*design
        q=Dict{String,Any}(
            "from"=>i,
            "to"=>j,
            "H_max_MW"=>cap,
            "flow_max_kg_s"=>cap/(hp["cp_J_kgK"]/1e6*hp["delta_min_K"]),
            "length_m"=>hp["length_m"],
            "U_W_mK"=>U,
            "S_ref_K"=>hp["S_reference_K"],
            "R_ref_K"=>hp["R_reference_K"],
            "ambient_K"=>hp["ambient_K"],
            "design_area_m2"=>area,
        )
        q["loss_MW"]=r4_loss(q)
        push!(pipes, q)
    end
    tariff=r9_tariff(s, collect(0:(T-1)))
    prices=p["settlement"]
    settlement=Dict{String,Any}(
        "P_buy"=>prices["P_buy_tariff_factor"] .* tariff,
        "P_sell"=>prices["P_sell_tariff_factor"] .* tariff,
        "H_buy"=>fill(prices["H_buy_CNY_MWh"], T),
        "H_sell"=>fill(prices["H_sell_CNY_MWh"], T),
        "fee"=>fill(prices["fee_CNY_MWh"], T),
    )
    for carrier in ("P", "H")
        settlement[carrier*"_peer"]=(settlement[carrier*"_buy"]+settlement[carrier*"_sell"])/2
    end
    d=Dict{String,Any}(
        "schema"=>"r9-trading-case-v1",
        "id"=>p["id"],
        "origin"=>"synthetic",
        "T"=>T,
        "dt_h"=>p["dt_h"],
        "units"=>Dict(
            "power"=>"MW",
            "energy"=>"MWh",
            "flow"=>"kg/s",
            "temperature"=>"K",
            "time"=>"h",
            "money"=>"CNY",
        ),
        "grid_price"=>tariff,
        "actors"=>actors,
        "devices"=>devices,
        "settlement"=>settlement,
        "electric"=>Dict(
            "nodes"=>n,
            "root"=>44,
            "edges"=>edges,
            "base_MVA"=>ep["base_MVA"],
            "base_kV"=>ep["base_kV"],
            "grid_max_MW"=>ep["grid_max_MW"],
            "grid_Q_max_Mvar"=>ep["grid_Q_max_Mvar"],
            "v_min_pu"=>ep["v_min_pu"],
            "v_max_pu"=>ep["v_max_pu"],
            "P_background_MW"=>[x .* p["electric_profile"] for x in bgP],
            "Q_background_Mvar"=>[ratio*x .* p["electric_profile"] for x in bgP],
        ),
        "heat"=>Dict(
            "nodes"=>k,
            "root"=>1,
            "pipes"=>pipes,
            "cp_J_kgK"=>hp["cp_J_kgK"],
            "delta_min_K"=>hp["delta_min_K"],
            "delta_max_K"=>hp["delta_max_K"],
            "H_background_MW"=>[x .* p["heat_profile"] for x in bgH],
            "model"=>"steady_energy_mass_envelope",
        ),
        "provenance"=>Dict(
            "source_hashes"=>bundle.hashes,
            "protocol_sha256"=>bytes2hex(sha256(read(protocol_path))),
            "protocol"=>p,
            "original_node_ids_preserved"=>true,
            "table_P_total_MW"=>sum(a["electric_MW"] for a in tr["aggregators"]),
            "table_H_total_MW"=>sum(a["heat_MW"] for a in tr["aggregators"]),
            "background_P_peak_MW"=>missingP,
            "background_H_peak_MW"=>missingH,
            "inactive_electric_ties"=>tr["new_electric_ties"],
            "inactive_heat_ties"=>tr["new_heat_ties"],
        ),
    )
    R9TradingCase(d)
end
