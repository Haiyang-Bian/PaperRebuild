# R9-RN1—N5：可切换候选图与完整设备接入设计。旧交易输入不隐式升级。
function r9_network_check(d)
    n=d["network_control"]
    n["version"]=="r9_network_checked_v1" || error("未知规模重构版本")
    n["design"] in ("legacy", "equipment") || error("未知网络设计")
    bytes2hex(sha256(r4_text(n["protocol"])))==n["protocol_sha256"] || error("网络协议哈希改变")
    occursin(r"^[a-f0-9]{64}$", n["parent_sha256"]) || error("父输入身份缺失")
    n["policy"] in ("fixed", "electric", "heat", "joint") || error("未知网络控制策略")
    for (side, key) in (("electric", "edges"), ("heat", "pipes"))
        edges=d[side][key]
        initial, switchable=n[side*"_initial"], n[side*"_switchable"]
        length(initial)==length(switchable)==length(edges) || error("开关索引形状错误")
        all(x->x in (0, 1), [initial; switchable]) || error("开关状态不是二进制")
        r4_is_tree(edges, initial; nodes = d[side]["nodes"]) || error("初始拓扑必须连通径向")
        all(initial[i]==1 || switchable[i]==1 for i in eachindex(edges)) ||
            error("常开联络边必须可切换")
    end
    n["dwell_steps"] isa Int && n["dwell_steps"]>=1 || error("动作间隔错误")
    n["stable_history_steps"] isa Int && n["stable_history_steps"]>=n["dwell_steps"]-1 ||
        error("缺少此前稳定历史")
    n["electric_max_actions"] isa Int && n["electric_max_actions"]>=0 || error("动作次数错误")
    all(x->x isa Real && isfinite(x) && x>=0, (n["electric_action_CNY"], n["heat_action_CNY"])) ||
        error("动作成本错误")
    n["terminal_rule"]=="free_topology_no_periodic_restoration" || error("终端规则未声明")
    for key in (
        "dwell_steps",
        "stable_history_steps",
        "electric_max_actions",
        "electric_action_CNY",
        "heat_action_CNY",
        "terminal_rule",
    )
        n[key]==n["protocol"][key] || error("控制参数与冻结协议不同")
    end
    true
end

r9_trading_version(c) =
    haskey(c.data, "network_control") ? "r9_trading_reconfiguration_v1" :
    "r9_trading_energy_mass_v1"

# 无向树的唯一物理路径；候选联络线只能读取父输入，不读取优化结果。
function r9_network_path(edges, nodes, source, target)
    source in 1:nodes && target in 1:nodes && source!=target || error("联络端点错误")
    seen=falses(nodes)
    previous=zeros(Int, nodes)
    byedge=zeros(Int, nodes)
    queue=[source]
    seen[source]=true
    for i in queue
        for (j, e) in enumerate(edges)
            o=e["from"]==i ? e["to"] : e["to"]==i ? e["from"] : 0
            o==0 && continue
            seen[o] && continue
            seen[o]=true
            previous[o]=i
            byedge[o]=j
            push!(queue, o)
        end
    end
    seen[target] || error("联络端点不连通")
    path=Int[]
    i=target
    while i!=source
        push!(path, byedge[i])
        i=previous[i]
    end
    reverse(path)
end

function r9_equipment_design!(d, p)
    e, h=d["electric"], d["heat"]
    ne, nh=e["nodes"], h["nodes"]
    P=[maximum(x) for x in e["P_background_MW"]]
    Q=[maximum(x) for x in e["Q_background_Mvar"]]
    H=[maximum(x) for x in h["H_background_MW"]]
    for a in d["actors"][2:end]
        demand=(1+a["flex"])*maximum(a["P_load"])
        P[a["electric_node"]]+=demand
        Q[a["electric_node"]]+=a["Q_ratio"]*demand
        H[a["heat_node"]]+=(1+a["flex"])*maximum(a["H_load"])
    end
    # 绝对额定包络是保守设计规则，不是保证同时可达的设备运行点。
    for g in d["devices"]
        g["electric_node"]>0 && (P[g["electric_node"]]+=g["power_max_MW"])
        g["heat_node"]>0 && (
            H[g["heat_node"]]+=g["power_max_MW"] *
                               (g["kind"] in ("CHP", "P2H") ? g["heat_ratio"] : 1.0)
        )
    end
    for (side, key, envelopes) in (("electric", "edges", (P, Q)), ("heat", "pipes", (H,)))
        net=d[side]
        edges=net[key]
        order, depth=r9_tree_order(net["nodes"], [[x["from"], x["to"]] for x in edges], net["root"])
        for j in reverse(order[2:end])
            i=only(x["from"] for x in edges if x["to"]==j)
            for envelope in envelopes
                envelope[i]+=envelope[j]
            end
        end
        for edge in edges
            j=edge["to"]
            if side=="electric"
                pMW=max(P[j], p["minimum_design_MW"])
                qMW=max(Q[j], p["minimum_design_MW"])
                pu, qu=pMW/e["base_MVA"], qMW/e["base_MVA"]
                r=p["path_squared_voltage_drop_budget"] / (2maximum(depth)*(pu+p["x_over_r"]*qu))
                edge["r_pu"]=r
                edge["x_pu"]=p["x_over_r"]*r
                edge["P_max_MW"]=p["capacity_factor"]*pMW
                edge["Q_max_Mvar"]=p["capacity_factor"]*qMW
                edge["ell_max_pu"]=(p["capacity_factor"]*hypot(pu, qu)/e["v_min_pu"])^2
            else
                design=max(H[j], p["minimum_design_MW"])
                mass=design/(h["cp_J_kgK"]/1e6*(edge["S_ref_K"]-edge["R_ref_K"]))
                area=mass/(p["rho_kg_m3"]*p["velocity_m_s"])
                diameter=sqrt(4area/pi)
                edge["U_W_mK"]=2pi*p["insulation_W_mK"] /
                               log((diameter+2p["insulation_thickness_m"])/diameter)
                edge["design_area_m2"]=area
                edge["H_max_MW"]=p["capacity_factor"]*design
                edge["flow_max_kg_s"]=edge["H_max_MW"]/(h["cp_J_kgK"]/1e6*h["delta_min_K"])
                edge["loss_MW"]=r4_loss(edge)
            end
        end
    end
end

"""
    r9_reconfiguration_case(parent, protocol; design=:legacy, policy=:fixed)

从固定树父输入构造第7.3节候选图，不优化、不修改父对象。protocol为TOML路径或字典。
design=:legacy保持原支路参数；:equipment按全部设备额定值与最大灵活负荷重新设计网络。
后者同时改变阻抗、容量、管道散热，属于参数组合对照，不能只归因为增容。
电联络线按原树路径合计阻抗并取路径最小容量；热联络管长度取原路径之和，按自身额定流量
重新确定截面和SI传热系数，不能混用大管径路径的UA与最小管径容量。参数是项目假设。
policy控制fixed/electric/heat/joint；电逐时、热整日，只有协议列出的开关可以动作。
核心负荷、设备、价格与结算保持；R9-RN1—N5，单位MW、kg/s、pu和CNY/次。
"""
function r9_reconfiguration_case(c::R9TradingCase, protocol; design = :legacy, policy = :fixed)
    TOML.parse(c.source_text)==c.data || error("父输入被改写")
    c.data["schema"]=="r9-trading-case-v1" || error("只能从原固定树派生，不能重复追加联络边")
    design in (:legacy, :equipment) && policy in (:fixed, :electric, :heat, :joint) ||
        error("未知派生规则")
    p=protocol isa AbstractString ? TOML.parsefile(protocol) : deepcopy(protocol)
    p["schema"]=="r9-network-protocol-v1" || error("网络协议版本错误")
    p["tie_parameter_rule"]=="original_path_length_impedance_minimum_capacity_new_pipe_geometry" ||
        error("未声明联络参数规则")
    p["equipment_rule"]=="full_device_absolute_envelope_plus_maximum_flexible_demand" ||
        error("未声明设备接入规则")
    all(x->x isa Real && isfinite(x) && x>0, values(p["design"])) || error("设计参数须有限正值")
    d=deepcopy(c.data)
    design==:equipment && r9_equipment_design!(d, p["design"])
    n=Dict{String,Any}(
        "version"=>"r9_network_checked_v1",
        "policy"=>string(policy),
        "design"=>string(design),
        "parent_sha256"=>c.sha256,
        "protocol"=>p,
        "protocol_sha256"=>bytes2hex(sha256(r4_text(p))),
    )
    for key in (
        "dwell_steps",
        "stable_history_steps",
        "electric_max_actions",
        "electric_action_CNY",
        "heat_action_CNY",
        "terminal_rule",
    )
        n[key]=p[key]
    end
    for (side, key) in (("electric", "edges"), ("heat", "pipes"))
        original=deepcopy(d[side][key])
        pairs=[minmax(x["from"], x["to"]) for x in original]
        switches=[minmax(x...) for x in p[side*"_base_switches"]]
        allunique(switches) && all(x->x in pairs, switches) || error("原图开关不属于父树")
        ties=p[side*"_ties"]
        allunique(minmax(x...) for x in ties) || error("重复联络边")
        n[side*"_initial"]=[ones(Int, length(original)); zeros(Int, length(ties))]
        n[side*"_switchable"]=[Int.(pairs .∈ Ref(switches)); ones(Int, length(ties))]
        for (i, j) in ties
            minmax(i, j) in pairs && error("联络边重复原支路")
            path=r9_network_path(original, d[side]["nodes"], i, j)
            rows=original[path]
            tie=deepcopy(first(rows))
            tie["from"], tie["to"]=i, j
            tie["design_parent_path"]=path
            if side=="electric"
                for field in ("r_pu", "x_pu")
                    tie[field]=sum(x[field] for x in rows)
                end
                for field in ("P_max_MW", "Q_max_Mvar", "ell_max_pu")
                    tie[field]=minimum(x[field] for x in rows)
                end
            else
                all(
                    x->(x["S_ref_K"], x["R_ref_K"], x["ambient_K"]) ==
                       (tie["S_ref_K"], tie["R_ref_K"], tie["ambient_K"]),
                    rows,
                ) || error("路径参考温度不同，不能合计损耗")
                tie["length_m"]=sum(x["length_m"] for x in rows)
                for field in ("H_max_MW", "flow_max_kg_s")
                    tie[field]=minimum(x[field] for x in rows)
                end
                hp=p["design"]
                mass=tie["H_max_MW"]/(
                    hp["capacity_factor"]*d["heat"]["cp_J_kgK"]/1e6 *
                    (tie["S_ref_K"]-tie["R_ref_K"])
                )
                area=mass/(hp["rho_kg_m3"]*hp["velocity_m_s"])
                diameter=sqrt(4area/pi)
                tie["design_area_m2"]=area
                tie["U_W_mK"]=2pi*hp["insulation_W_mK"] /
                              log((diameter+2hp["insulation_thickness_m"])/diameter)
                tie["loss_MW"]=r4_loss(tie)
            end
            push!(d[side][key], tie)
        end
    end
    d["schema"]="r9-trading-case-v2"
    d["id"]=c.data["id"]*"-"*string(design)*"-"*string(policy)
    d["network_control"]=n
    R9TradingCase(d)
end
