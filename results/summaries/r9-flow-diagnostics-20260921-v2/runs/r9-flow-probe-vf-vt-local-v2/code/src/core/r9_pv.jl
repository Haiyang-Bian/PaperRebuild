# R9-P1至P6：缺失输入的显式工程替代。原始结果表不进入任何构造运算。
r9_text(d) = sprint(io -> TOML.print(io, d; sorted = true))
r9_hash(d) = bytes2hex(sha256(r9_text(d)))

function r9_tree_order(n, edges, root)
    order, depth = [root], zeros(Int, n)
    for i in order, (a, b) in edges
        a == i || continue
        b in order && error("有向树重复节点")
        push!(order, b)
        depth[b] = depth[a] + 1
    end
    length(order) == n || error("有向树不连通")
    return order, depth
end

"""
    r9_pv_case(source_directory, protocol_path)

由原图44/38节点及额定设备构造第7.2节24小时替代案例，返回R2Case。
负荷、线路、管道、温度和端点条件依显式协议生成；金额CNY，能量MWh，管道用SI。
电源44重编号为1，并保留双向节点映射；高压馈线通过理想额定变压器折算。
初始热历史由预先声明的CF-CT周期参考解析生成，不使用优化结果或作者费用反求参数。
这不是作者同输入数据；协议和每类字段来源随案例保存。
"""
function r9_pv_case(source_directory, protocol_path)
    bundle = load_r9_sources(source_directory)
    p = TOML.parsefile(protocol_path)
    p["schema"] == "r9-pv-input-protocol-v1" || error("未知R9协议")
    p["T"] == 24 && p["dt_h"] == 1.0 || error("本版明确24个一小时时段")
    for key in ("electric_profile", "heat_profile", "pv_profile")
        x = p[key]
        length(x) == 24 && all(v -> isfinite(v) && 0 <= v <= 1, x) && maximum(x) == 1 ||
            error("比例时序非法：$key")
    end
    s, topology = bundle.data["inputs.toml"], bundle.data["topology.toml"]
    base, e, h = s["base"], p["electric"], p["heat"]
    0 < e["power_factor"] <= 1 || error("功率因数非法")
    0 < h["flow_min_factor"] <= 1 <= h["flow_max_factor"] || error("参考流量界非法")
    p["history_rule"] == "periodic_CF_CT_reference_computed_without_optimization" ||
        error("历史规则不支持")
    p["terminal_rule"] == "repeat_all_WMM_inlet_memory_and_reference_flows" ||
        error("终端规则不支持")
    p["commitment_rule"] ==
    "CHP_on_with_original_Pmin; equation_3_1_variable_cost_only; no_startup_claim" ||
        error("启停解释不支持")
    for key in (
        "rho_kg_m3",
        "cp_J_kgK",
        "length_m",
        "design_velocity_m_s",
        "reference_delta_K",
        "insulation_conductivity_W_mK",
        "insulation_thickness_m",
        "darcy_friction_factor",
    )
        isfinite(h[key]) && h[key] > 0 || error("非法工程参数：$key")
    end
    n, k, T = topology["electric"]["nodes"], topology["heat"]["nodes"], p["T"]
    n == 44 && k == 38 || error("本版保留原44/38规模")
    labels = [44; collect(1:43)]
    internal = invperm(labels)
    devices = Dict{String,Any}[]
    for g in base["chp"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"CHP",
                "electric_node"=>internal[g["electric_node"]],
                "heat_node"=>g["heat_node"],
                "heat_ratio"=>g["H_over_P"],
                "P_min"=>g["P_min_MW"],
                "P_max"=>g["P_max_MW"],
                "availability"=>fill(g["P_max_MW"], T),
                "cost_per_MWh"=>g["fuel_CNY_MWh_electric"],
            ),
        )
    end
    for g in base["eb"]
        cap = g["H_max_MW"] / g["eta"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"EB",
                "electric_node"=>internal[g["electric_node"]],
                "heat_node"=>g["heat_node"],
                "heat_ratio"=>g["eta"],
                "P_min"=>0.0,
                "P_max"=>cap,
                "availability"=>fill(cap, T),
                "cost_per_MWh"=>0.0,
            ),
        )
    end
    for g in base["pv"]
        cap = g["id"] == "PV1" ? s["pv_dispatch"]["pv1_capacity_MW"] : g["P_max_MW"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"PV",
                "electric_node"=>internal[g["electric_node"]],
                "heat_node"=>0,
                "heat_ratio"=>0.0,
                "P_min"=>0.0,
                "P_max"=>cap,
                "availability"=>cap .* p["pv_profile"],
                "cost_per_MWh"=>g["cost_CNY_MWh"],
            ),
        )
    end
    pf, S = e["power_factor"], base["electric_peak_MVA"]
    ep = [i == 1 ? 0.0 : S*pf/(n-1) for i in 1:n]
    eq = [i == 1 ? 0.0 : S*sqrt(1-pf^2)/(n-1) for i in 1:n]
    eedges = [[internal[a], internal[b]] for (a, b) in topology["electric"]["edges"]]
    order, depth = r9_tree_order(n, eedges, 1)
    envelope = copy(ep)
    for g in devices
        envelope[g["electric_node"]] += g["P_max"]
    end
    qenv = copy(eq)
    for j in reverse(order[2:end])
        a = only(a for (a, b) in eedges if b == j)
        envelope[a] += envelope[j]
        qenv[a] += qenv[j]
    end
    edges = Dict{String,Any}[]
    line_metadata = Dict{String,Any}[]
    for (i, j) in eedges
        pp, qq = envelope[j]/e["base_MVA"], qenv[j]/e["base_MVA"]
        r = e["path_squared_voltage_drop_budget"]/(2maximum(depth)*(pp+e["x_over_r"]*qq))
        cap = e["current_capacity_factor"]*hypot(pp, qq)/e["v_min_pu"]
        kv = labels[i] == 44 ? 110.0 : 10.0
        push!(
            edges,
            Dict("from"=>i, "to"=>j, "r_pu"=>r, "x_pu"=>r*e["x_over_r"], "ell_max_pu"=>cap^2),
        )
        push!(
            line_metadata,
            Dict(
                "original_from"=>labels[i],
                "original_to"=>labels[j],
                "nominal_kV"=>kv,
                "r_ohm_at_nominal_voltage"=>r*kv^2/e["base_MVA"],
                "r_ohm_referred_10kV"=>r*e["equivalent_base_kV"]^2/e["base_MVA"],
                "design_P_envelope_MW"=>envelope[j],
            ),
        )
    end
    # 参考端口质量按热负荷/温差确定；H15源注入抵消其下游的部分流量。
    hedges = topology["heat"]["edges"]
    horder, _ = r9_tree_order(k, hedges, 1)
    cp, rho = h["cp_J_kgK"], h["rho_kg_m3"]
    href = base["heat_peak_MW"]*p["heat_reference_fraction"]
    port = [j in (1, 15) ? 0.0 : href/(k-2)/(cp/1e6*h["reference_delta_K"]) for j in 1:k]
    port[15] = h["local_source_reference_heat_MW"]/(cp/1e6*h["reference_delta_K"])
    demand = [j == 15 ? -port[j] : port[j] for j in 1:k]
    for j in reverse(horder[2:end])
        a = only(a for (a, b) in hedges if b == j)
        demand[a] += demand[j]
    end
    port[1] = demand[1]
    pipes = Dict{String,Any}[]
    for (a, b) in hedges
        m = demand[b]
        m > 0 || error("参考方案需要反向/停流，禁止静默修正")
        area = m/(rho*h["design_velocity_m_s"])
        diameter = sqrt(4area/pi)
        epsilon =
            2pi*h["insulation_conductivity_W_mK"]/log(
                (diameter+2h["insulation_thickness_m"])/diameter,
            )
        mu = h["darcy_friction_factor"]*h["length_m"]/(2000rho*diameter*area^2)
        nh = ceil(Int, rho*area*h["length_m"]/(3600m*h["flow_min_factor"]))+1
        push!(
            pipes,
            Dict(
                "from"=>a,
                "to"=>b,
                "area_m2"=>area,
                "length_m"=>h["length_m"],
                "epsilon_W_mK"=>epsilon,
                "mu_kPa_s2_kg2"=>mu,
                "flow_min"=>m*h["flow_min_factor"],
                "flow_max"=>m*h["flow_max_factor"],
                "flow_history"=>fill(m, nh),
                "fixed_flow"=>fill(m, T),
            ),
        )
    end
    pressure = zeros(k)
    for j in horder[2:end]
        pipe = only(x for x in pipes if x["to"] == j)
        pressure[j] = pressure[pipe["from"]]+pipe["mu_kPa_s2_kg2"]*pipe["flow_max"]^2
    end
    d = Dict{String,Any}(
        "schema"=>"r2-case-v1",
        "id"=>p["id"],
        "origin"=>"synthetic",
        "T"=>T,
        "dt_h"=>p["dt_h"],
        "units"=>Dict(
            "power"=>"MW",
            "energy"=>"MWh",
            "temperature"=>"K",
            "flow"=>"kg/s",
            "time"=>"h",
            "pressure"=>"kPa",
        ),
        "grid_price"=>r9_tariff(s, collect(0:(T-1))),
        "ambient_K"=>fill(h["ambient_K"], T),
        "devices"=>devices,
        "electric"=>Dict(
            "base_MVA"=>e["base_MVA"],
            "base_kV"=>e["equivalent_base_kV"],
            "grid_max_MW"=>e["grid_max_MW"],
            "v_min_pu"=>e["v_min_pu"],
            "v_max_pu"=>e["v_max_pu"],
            "edges"=>edges,
            "nodes"=>[
                Dict(
                    "P_MW"=>ep[i] .* p["electric_profile"],
                    "Q_Mvar"=>eq[i] .* p["electric_profile"],
                ) for i in 1:n
            ],
        ),
        "heat"=>Dict(
            "rho_kg_m3"=>rho,
            "cp_J_kgK"=>cp,
            "pressure_max_kPa"=>2maximum(pressure)*h["pressure_margin_factor"]+h["pressure_margin_kPa"],
            "S_bounds_K"=>h["S_bounds_K"],
            "R_bounds_K"=>h["R_bounds_K"],
            "S_reference_K"=>h["source_temperature_K"],
            "R_reference_K"=>h["source_temperature_K"]-h["reference_delta_K"],
            "pipes"=>pipes,
            "nodes"=>[
                Dict(
                    "role"=>j in (1, 15) ? "source" : "load",
                    "flow_min"=>port[j]*h["flow_min_factor"],
                    "flow_max"=>port[j]*h["flow_max_factor"],
                    "return_K"=>h["source_temperature_K"]-h["reference_delta_K"],
                    "H_MW"=>j in (1, 15) ? zeros(T) :
                            base["heat_peak_MW"]/(k-2) .* p["heat_profile"],
                ) for j in 1:k
            ],
        ),
        "r9"=>Dict(
            "schema"=>"r9-pv-case-v1",
            "currency"=>"CNY",
            "protocol"=>p,
            "protocol_sha256"=>r9_hash(p),
            "source_hashes"=>bundle.hashes,
            "original_to_internal_electric"=>internal,
            "internal_to_original_electric"=>labels,
            "line_metadata"=>line_metadata,
            "original_input_ready"=>false,
            "optimized_to_construct_input"=>false,
        ),
    )
    reference = r9_periodic_heat_reference(d)
    d["r9"]["reference"] = reference
    for (i, pipe) in enumerate(pipes), side in ("S", "R")
        nh = length(pipe["flow_history"])
        pipe[side*"_history_K"] = [reference[side*"_in"][i][mod1(t, T)] for t in (1-nh):0]
    end
    validate_r2_input(d)
    c = R2Case(d, r9_hash(d))
    audit_r9_pv_input(c).pass || error("预优化参考方案未通过；保留协议，不自动改参")
    return c
end

# 按树先供后回，时间用mod1连接上一日。固定流量使供温线性，CF-CT参考不需要求解器。
function r9_periodic_heat_reference(d)
    h, T = d["heat"], d["T"]
    pipes, nodes = h["pipes"], h["nodes"]
    E, N = length(pipes), length(nodes)
    order, _ = r9_tree_order(N, [[p["from"], p["to"]] for p in pipes], 1)
    m = [first(p["fixed_flow"]) for p in pipes]
    ports = vec(r2_fixed_port_flows(d, repeat(m, 1, T))[:, 1])
    cp, amb = h["cp_J_kgK"], only(unique(d["ambient_K"]))
    sinlet, sout, rinlet, rout = (zeros(E, T) for _ in 1:4)
    smix, rmix, rport, source_heat = (zeros(N, T) for _ in 1:4)
    function transmit(p, inputs, t)
        pipe = pipes[p]
        nh = length(pipe["flow_history"])
        w = water_mass_weights(
            fill(m[p], nh+1),
            h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"],
            3600d["dt_h"],
        )
        star = sum(w.w[s+1]*inputs[mod1(t-s, T)] for s in 0:nh)
        return amb+(star-amb)*exp(-pipe["epsilon_W_mK"]*pipe["length_m"]/(cp*m[p]))
    end
    for j in order, t in 1:T
        incoming = findall(p -> p["to"] == j, pipes)
        outgoing = findall(p -> p["from"] == j, pipes)
        local_m = nodes[j]["role"] == "source" ? ports[j] : 0.0
        smix[j, t] =
            (sum(m[p]*sout[p, t] for p in incoming; init = 0.0)+local_m*h["S_reference_K"])/(
                sum(m[incoming])+local_m
            )
        for p in outgoing
            sinlet[p, t] = smix[j, t]
            sout[p, t] =
                amb+(sinlet[p, t]-amb)*exp(-pipes[p]["epsilon_W_mK"]*pipes[p]["length_m"]/(cp*m[p]))
        end
        nodes[j]["role"] == "load" &&
            (rport[j, t] = smix[j, t]-nodes[j]["H_MW"][t]/(cp/1e6*ports[j]))
    end
    for j in reverse(order)
        incoming = findall(p -> p["from"] == j, pipes)
        upstream = findall(p -> p["to"] == j, pipes)
        local_m = nodes[j]["role"] == "load" ? ports[j] : 0.0
        for t in 1:T
            rmix[j, t] =
                (sum(m[p]*rout[p, t] for p in incoming; init = 0.0)+local_m*rport[j, t])/(
                    sum(m[incoming])+local_m
                )
            nodes[j]["role"] == "source" &&
                (source_heat[j, t] = cp/1e6*ports[j]*(h["S_reference_K"]-rmix[j, t]))
        end
        for p in upstream
            rinlet[p, :] .= rmix[j, :]
            for t in 1:T
                rout[p, t] = transmit(p, rinlet[p, :], t)
            end
        end
    end
    return Dict(
        "S_in"=>r2_extract(sinlet),
        "S_out"=>r2_extract(sout),
        "R_in"=>r2_extract(rinlet),
        "R_out"=>r2_extract(rout),
        "S_mix"=>r2_extract(smix),
        "R_mix"=>r2_extract(rmix),
        "R_load"=>r2_extract(rport),
        "source_heat_MW"=>r2_extract(source_heat),
        "port_flow_kg_s"=>ports,
    )
end

"""
    load_r9_pv_case(path)

读取冻结R9替代输入，验证R2单位、参考周期、节点映射与协议身份；不下载、求解或改写数据。
返回哈希对应实际文件字节的R2Case；原始数据缺口不会因替代输入可运行而被解除。
"""
function load_r9_pv_case(path)
    c = load_r2_case(path)
    audit_r9_pv_input(c).pass || error("R9替代输入核查失败")
    return c
end
