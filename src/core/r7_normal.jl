"""
    R7NormalCase(data)

第6章给定正向管流的正常调度输入。v1保留USD；v2显式currency及中性费用字段，
用于第7.5节人民币输入，不执行汇率换算。正常、事件继承及R7/R8费用链共同保持币种。
电压为幅值pu，
功率MW/Mvar、热量MWh、流率kg/s、压力Pa、温度K。启停跨场景共享，调度允许场景依赖。
显式区分node_method_fixed_v1和plug_flow_reference_v1；不将给定流量的条件最优冒充完整灾前规划。
"""
struct R7NormalCase
    data::Dict{String,Any}
    sha256::String
end

function with_r7_critical_load(c::R7NormalCase, critical_load_MW; provenance)
    r7_normal_assert(c)
    R7NormalCase(r7_service_input(c, critical_load_MW, provenance))
end

function with_r7_electric_domain(c::R7NormalCase, rule::AbstractString; provenance)
    r7_normal_assert(c)
    R7NormalCase(r7_electric_domain_input(c, rule, provenance))
end

function r7_normal_chp(d, g)
    x=deepcopy(g)
    x["schema"]=r7_money_schema(d, "r7-chp-component-v1")
    r7_currency_record!(x, d)
    for k in ("periods", "dt_h", "probabilities")
        x[k]=d[k]
    end
    R7CHPSpec(x)
end

function r7_normal_initial(d, pipe, side, w)
    x=pipe["initial_$(side)_profiles"][w]
    r7_initial_state(x)
end

function R7NormalCase(input::AbstractDict)
    d=TOML.parse(r7_text(input))
    r7_check_currency_schema(d, "r7-normal-case-v1")
    d["origin"] in ("synthetic", "public_adapted", "thesis_verified") || error("正常输入来源缺失")
    !isempty(strip(d["name"])) || error("案例名称缺失")
    d["flow_control"]=="prescribed_positive" || error("本接口是给定正向管流的条件调度")
    d["thermal_model"] in ("node_method_fixed_v1", "plug_flow_reference_v1") ||
        error("未声明热输运版本")
    d["heat_terminal_rule"] in ("free", "pipe_inventory_initial") || error("未声明热末端条件")
    r7_battery_rule(d)
    d["scenario_information"]=="full_trajectory_after_shared_commitment" ||
        error("须显式给出场景信息结构")
    for (k, unit) in (
        "power"=>"MW",
        "reactive"=>"Mvar",
        "energy"=>"MWh",
        "time"=>"h",
        "temperature"=>"K",
        "flow"=>"kg/s",
        "pressure"=>"Pa",
        "price"=>r7_currency(d)*"/MWh",
    )
        d["units"][k]==unit || error("正常输入单位错误：$k")
    end
    T, dt=d["periods"], d["dt_h"]
    T isa Integer && T>0 && isfinite(dt) && dt>0 || error("正常运行时域错误")
    probabilities=Float64.(d["probabilities"])
    !isempty(probabilities) &&
    all(isfinite, probabilities) &&
    all(>(0), probabilities) &&
    abs(sum(probabilities)-1)<=1e-8 || error("场景概率错误")
    W=length(probabilities)
    e, h=d["electric"], d["heat"]
    N, J=e["nodes"], h["nodes"]
    N isa Integer && N>=1 && J isa Integer && J>=2 || error("节点数错误")
    e["pcc_node"] isa Integer && 1<=e["pcc_node"]<=N || error("PCC节点错误")
    e["flow_domain"] in ("forward_only", "signed") || error("电支路方向解释缺失")
    r7_check_electric_domain(d)
    for k in (
        "S_base_MVA",
        "v_min_pu",
        "v_max_pu",
        "v_ref_pu",
        "pcc_min_MW",
        "pcc_max_MW",
        "qcc_min_Mvar",
        "qcc_max_Mvar",
    )
        isfinite(e[k]) || error("非有限电网边界：$k")
    end
    e["S_base_MVA"]>0 &&
    0<e["v_min_pu"]<=e["v_ref_pu"]<=e["v_max_pu"] &&
    e["pcc_min_MW"]<=e["pcc_max_MW"] &&
    e["qcc_min_Mvar"]<=e["qcc_max_Mvar"] || error("电网边界错误")
    r7_check_money_fields(d, e, ("price_USD_MWh",))
    r7_numbers(e[r7_money_key(d, "price_USD_MWh")], (T,), "PCC电价")
    r7_numbers(e["load_MW"], (N, T), "固定电负荷"; lo = 0)
    r7_check_load_service(d)
    r7_numbers(e["tan_phi"], (N,), "负荷功率因数"; lo = 0)
    ends=Tuple{Int,Int}[]
    for l in e["lines"]
        i, j=l["from"], l["to"]
        i isa Integer && j isa Integer && 1<=i<=N && 1<=j<=N && i!=j || error("电支路节点错误")
        l["base_closed"] in (0, 1) || error("固定电拓扑状态错误")
        for k in ("r_pu", "x_pu", "P_max_MW", "Q_max_Mvar")
            isfinite(l[k]) && l[k]>=0 || error("电支路参数错误")
        end
        push!(ends, (i, j))
    end
    z=[l["base_closed"] for l in e["lines"]]
    sum(z)==N-1 && length(r7_connected_components(N, ends, z))==1 ||
        error("正常电拓扑须为连接PCC的固定树")
    h["available"]===true || error("正常热网必须显式可用")
    for k in ("c_J_kgK", "rho_kg_m3", "pressure_max_Pa")
        isfinite(h[k]) && h[k]>0 || error("水或压力参数错误")
    end
    for k in (
        "S_min_K",
        "S_max_K",
        "R_min_K",
        "R_max_K",
        "S_reference_K",
        "R_reference_K",
        "delta_pressure_min_Pa",
        "delta_pressure_max_Pa",
    )
        isfinite(h[k]) || error("非有限温度/压差")
    end
    0<h["R_min_K"]<h["R_max_K"]<h["S_min_K"]<h["S_max_K"] || error("供回温度范围错误")
    for side in ("S", "R")
        h["$(side)_min_K"]<=h["$(side)_reference_K"]<=h["$(side)_max_K"] || error("参考温度越界")
    end
    0<=h["delta_pressure_min_Pa"]<=h["delta_pressure_max_Pa"]<=h["pressure_max_Pa"] ||
        error("供回压差错误")
    r7_numbers(h["ambient_K"], (T,), "环境温度"; lo = 1, hi = h["R_min_K"])
    r7_numbers(h["load_MW"], (J, T), "固定热负荷"; lo = 0)
    for k in (
        "source_flow_max",
        "load_flow_max",
        "source_delta_min",
        "source_delta_max",
        "load_delta_min",
        "load_delta_max",
    )
        r7_numbers(h[k], (J,), k; lo = 0)
    end
    all(h["source_delta_min"] .<= h["source_delta_max"]) &&
    all(h["load_delta_min"] .<= h["load_delta_max"]) || error("端口温差错误")
    ms=r7_numbers(h["source_flow_kg_s"], (J, T), "热源端口流率"; lo = 0)
    md=r7_numbers(h["load_flow_kg_s"], (J, T), "热荷端口流率"; lo = 0)
    all(ms .<= h["source_flow_max"]) && all(md .<= h["load_flow_max"]) || error("端口流量越界")
    !isempty(h["pipes"]) || error("须显式提供供回水管")
    hends=Tuple{Int,Int}[]
    for p in h["pipes"]
        i, j=p["from"], p["to"]
        i isa Integer && j isa Integer && 1<=i<=J && 1<=j<=J && i!=j || error("热管节点错误")
        push!(hends, (i, j))
        for k in ("volume_S_m3", "volume_R_m3", "flow_max_kg_s")
            isfinite(p[k]) && p[k]>0 || error("管道体积/容量错误")
        end
        for k in (
            "UA_S_W_K",
            "UA_R_W_K",
            "mu_S_Pa_s2_kg2",
            "mu_R_Pa_s2_kg2",
            "valve_max_Pa",
            "flow_change_max_kg_s",
        )
            isfinite(p[k]) && p[k]>=0 || error("管道参数错误：$k")
        end
        f=r7_numbers(p["normal_flow_kg_s"], (T,), "给定管流"; lo = 0, hi = p["flow_max_kg_s"])
        all(>(0), f) || error("正常网络子问题暂不支持停流/反向；参考核能力不等于网络能力")
        for side in ("S", "R")
            length(p["initial_$(side)_profiles"])==W || error("初始管温场景数错误")
            for w in 1:W
                state=r7_normal_initial(d, p, side, w)
                M=r7_pipe_check(state)
                abs(M-h["rho_kg_m3"]*p["volume_$(side)_m3"])<=1e-8*max(1, M) ||
                    error("初始管温质量与体积不符")
                all(
                    h["$(side)_min_K"]<=value<=h["$(side)_max_K"] for s in state.segments for
                    value in
                    (s.base_K+s.amplitude_K, s.base_K+s.amplitude_K*exp(-s.rate_per_kg*s.mass_kg))
                ) || error("初始管温越界")
            end
            if d["thermal_model"]=="node_method_fixed_v1"
                all(!haskey(x, "schema") for x in p["initial_$(side)_profiles"]) ||
                    error("指数空间初态仅用于显式塞流参考，不能替代作者节点法历史")
                all(==(first(f)), f) || error("作者节点法入口当前只实现恒定流量特例")
                k=ceil(Int, h["rho_kg_m3"]*p["volume_$(side)_m3"]/(first(f)*3600dt))
                hist=p["history_$(side)_K"]
                hist isa AbstractArray && length(hist)>=k || error("节点法历史不足")
                r7_numbers(
                    hist,
                    (length(hist), W),
                    "节点法入口历史";
                    lo = h["$(side)_min_K"],
                    hi = h["$(side)_max_K"],
                )
            end
        end
    end
    length(r7_connected_components(J, hends, ones(Int, length(hends))))==1 || error("热网不连通")
    for j in 1:J, t in 1:T
        incoming=sum(p["normal_flow_kg_s"][t] for p in h["pipes"] if p["to"]==j; init = 0.0)
        outgoing=sum(p["normal_flow_kg_s"][t] for p in h["pipes"] if p["from"]==j; init = 0.0)
        abs(incoming+ms[j, t]-outgoing-md[j, t])<=1e-8*max(
            1,
            incoming,
            outgoing,
            ms[j, t],
            md[j, t],
        ) || error("给定流量不满足节点质量守恒")
        incoming+ms[j, t]>0 && outgoing+md[j, t]>0 || error("节点混合流率为零")
        md[j, t]>0 || h["load_MW"][j][t]==0 || error("有热需求却没有负荷端口流")
    end
    ds=d["devices"]
    ids=[g["id"] for g in ds]
    all(x->x isa String&&!isempty(strip(x)), ids) && length(unique(ids))==length(ids) ||
        error("设备身份错误")
    for g in ds
        r7_check_money_fields(d, g, ("cost_P_USD_MWh",))
        g["kind"] in ("CHP", "GT", "PV", "EB", "BES") || error("设备类别错误")
        g["electric_node"] isa Integer && 1<=g["electric_node"]<=N || error("设备电节点错误")
        isfinite(g["P_max_MW"]) && g["P_max_MW"]>=0 || error("设备容量错误")
        isfinite(g[r7_money_key(d, "cost_P_USD_MWh")]) && g[r7_money_key(d, "cost_P_USD_MWh")]>=0 ||
            error("设备费用错误")
        if g["kind"] in ("CHP", "EB")
            g["heat_node"] isa Integer &&
            1<=g["heat_node"]<=J &&
            maximum(ms[g["heat_node"], :])>0 || error("热设备缺正源端口")
            isfinite(g["heat_ratio"]) && g["heat_ratio"]>0 || error("热电转换错误")
        end
        if g["kind"]=="CHP"
            r7_normal_chp(d, g)
        elseif g["kind"]=="GT"
            isfinite(g["Q_max_Mvar"]) && g["Q_max_Mvar"]>=0 || error("GT无功错误")
        elseif g["kind"]=="PV"
            r7_numbers(g["available_MW"], (T, W), "PV可用出力"; lo = 0, hi = g["P_max_MW"])
        elseif g["kind"]=="BES"
            0<=g["E_min_MWh"]<=g["E_max_MWh"] && isfinite(g["E_max_MWh"]) ||
                error("电池能量范围错误")
            0<g["eta_ch"]<=1 && 0<g["eta_dis"]<=1 || error("电池效率错误")
            r7_numbers(g["initial_MWh"], (W,), "电池初值"; lo = g["E_min_MWh"], hi = g["E_max_MWh"])
        end
    end
    for j in 1:J
        maximum(ms[j, :])==0 ||
            any(g->g["kind"] in ("CHP", "EB")&&g["heat_node"]==j, ds) ||
            error("正源流量没有设备")
    end
    R7NormalCase(d, r7_digest(d))
end

"""读取第6章给定流量正常案例并验证显式初始空间管温、单位、场景、拓扑与端口守恒。"""
load_r7_normal_case(path::AbstractString) = R7NormalCase(TOML.parsefile(path))
r7_normal_assert(c) = r7_digest(c.data)==c.sha256 || error("正常案例构造后被修改")

function with_r7_battery_rule(c::R7NormalCase, rule::AbstractString)
    r7_normal_assert(c)
    d=deepcopy(c.data)
    d["battery_rule"]=String(rule)
    R7NormalCase(d)
end

function r7_normal_shape(c)
    d=c.data
    T=d["periods"]
    W=length(d["probabilities"])
    N, J, G, L, A=d["electric"]["nodes"],
    d["heat"]["nodes"],
    length(d["devices"]),
    length(d["electric"]["lines"]),
    length(d["heat"]["pipes"])
    shapes=Dict(
        "P"=>(G, T, W),
        "Q"=>(G, T, W),
        "H"=>(G, T, W),
        "P_ch"=>(G, T, W),
        "P_dis"=>(G, T, W),
        "E_BES"=>(G, T+1, W),
        "P_PCC"=>(T, W),
        "Q_PCC"=>(T, W),
        "P_line"=>(L, T, W),
        "Q_line"=>(L, T, W),
        "v"=>(N, T, W),
        "τ_S"=>(J, T, W),
        "τ_R"=>(J, T, W),
        "τ_source"=>(J, T, W),
        "τ_load"=>(J, T, W),
        "τ_pipe_S"=>(A, T, W),
        "τ_pipe_R"=>(A, T, W),
        "E_pipe_S"=>(A, T+1, W),
        "E_pipe_R"=>(A, T+1, W),
        "Φ_S"=>(J, T),
        "Φ_R"=>(J, T),
        "Φ_val_S"=>(A, T),
        "Φ_val_R"=>(A, T),
    )
    r7_exclusive_battery(d) && (shapes["b_BES"]=(G, T, W))
    shapes
end
