# R9-RS：第7.4节独立输入。保留原节点编号，不调用7.2/7.3情景构造或读取作者收益表。
"""
    r9_reserve_template(source_directory, protocol_path)

由第7.1节额定设备、44/38原连接与表7-12用户侧电加热器构造第7.4节24h补救模板。
返回显式CNY的R5DispatchCase v2；PV1保留2MW，额定表容量按协议选择电输入侧。
固定正向热流、作者节点法J、供回水混合与建筑C/G均显式记录，初始历史由稳态代数构造。
只生成输入，不抽样、不优化、不写文件；初始参考不相容时拒绝，不依据优化费用改参。
模板零备用不是正式风险优化；线性电网/管温末态free及完整轨迹补救边界仍须分别说明。
"""
function r9_reserve_template(source_directory, protocol_path)
    bundle=load_r9_sources(source_directory)
    p=TOML.parsefile(protocol_path)
    p["schema"]=="r9-reserve-input-protocol-v1" &&
    p["source_section"]=="7.4" &&
    p["currency"]=="CNY" &&
    p["T"]==24 &&
    p["dt_h"]==1.0 || error("备用输入协议不支持")
    p["p2h_capacity_basis"]=="electric_input" || error("电热容量侧必须明确，当前采用电输入")
    p["chp_initial_rule"]=="steady_reference_heat_divided_by_heat_ratio; EB1_reference_zero" &&
    p["commitment_rule"]=="CHP_on_with_original_Pmin; continuous_chapter5_dispatch; startup_not_claimed" ||
        error("启停/初始出力解释不支持")
    T=p["T"]
    for key in ("electric_profile", "heat_profile", "pv_profile")
        x=p[key]
        length(x)==T && all(v->isfinite(v)&&0<=v<=1, x) && maximum(x)==1 || error("时序非法")
    end
    src=bundle.data["inputs.toml"]
    top=bundle.data["topology.toml"]
    base=src["base"]
    e, h, b, m=p["electric"], p["heat"], p["building"], p["market"]
    m["role"]=="price_taker" &&
    m["tariff_rule"] ==
    "add_to_day_ahead_and_realtime_energy_price_only; algebra_equals_tariff_times_actual_PCC" ||
        error("价格接受及网络费口径未声明")
    h["history_rule"]=="steady_author_fixed_flow_J; zero_local_P2H; declared_reference_load" ||
        error("热历史解释不支持")
    h["terminal_rule"]=="free" && b["terminal_rule"] in ("initial", "free") || error("终端规则错误")
    e["design_rule"]=="original_tree_absolute_load_and_all_connected_device_envelope" &&
    e["transformer_rule"]=="ideal_nominal_transformers; single_per_unit_base; no_loss_or_capacity_certification" ||
        error("电网替代解释不支持")
    b["ambient_rule"]=="T_initial-(T_initial-T_ambient_reference)*heat_profile/reference_fraction" ||
        error("环境与参考热负荷关系未声明")
    m["reserve_time_unit"]=="CNY_per_MW_per_hour; explicit interpretation of inconsistent text/axis" ||
        error("备用价格时间单位未声明")
    for (key, lo, hi) in (
        ("energy_price_CNY_MWh", 200.0, 400.0),
        ("up_price_CNY_MW_h", 20.0, 40.0),
        ("down_price_CNY_MW_h", 20.0, 40.0),
    )
        length(m[key])==T && all(v->isfinite(v)&&lo<=v<=hi, m[key]) ||
            error("替代价格超出声明的原文范围")
    end
    for k in (
        "length_m",
        "velocity_m_s",
        "rho_kg_m3",
        "cp_J_kgK",
        "reference_delta_K",
        "reference_fraction",
        "insulation_W_mK",
        "insulation_thickness_m",
    )
        isfinite(h[k]) && h[k]>0 || error("热工程参数非正")
    end
    B, N=top["electric"]["nodes"], top["heat"]["nodes"]
    B==44 && N==38 && e["root"]==44 || error("未保持原系统节点")
    enodes=top["electric"]["edges"]
    hnodes=top["heat"]["edges"]
    eo, depth=r9_tree_order(B, enodes, 44)
    ho, _=r9_tree_order(N, hnodes, 1)
    devices=Dict{String,Any}[]
    for g in base["chp"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"CHP",
                "node"=>g["electric_node"],
                "source_id"=>"H"*string(g["heat_node"]),
                "heat_ratio"=>g["H_over_P"],
                "p_min_MW"=>g["P_min_MW"],
                "p_max_MW"=>g["P_max_MW"],
                "q_min_Mvar"=>0.0,
                "q_max_Mvar"=>0.0,
                "cost_per_MWh"=>g["fuel_CNY_MWh_electric"],
                "P_initial_MW"=>g["P_min_MW"],
                "ramp_up_MW_h"=>g["P_max_MW"]*p["chp_ramp_fraction_per_hour"],
                "ramp_down_MW_h"=>g["P_max_MW"]*p["chp_ramp_fraction_per_hour"],
            ),
        )
    end
    for g in base["eb"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"EB",
                "node"=>g["electric_node"],
                "source_id"=>"H"*string(g["heat_node"]),
                "heat_ratio"=>g["eta"],
                "p_min_MW"=>0.0,
                "p_max_MW"=>g["H_max_MW"]/g["eta"],
                "q_min_Mvar"=>0.0,
                "q_max_Mvar"=>0.0,
                "cost_per_MWh"=>0.0,
            ),
        )
    end
    for g in base["pv"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"PV",
                "node"=>g["electric_node"],
                "p_min_MW"=>0.0,
                "p_max_MW"=>g["P_max_MW"],
                "available_MW"=>g["P_max_MW"] .* p["pv_profile"],
                "q_min_Mvar"=>0.0,
                "q_max_Mvar"=>0.0,
                "cost_per_MWh"=>g["cost_CNY_MWh"],
            ),
        )
    end
    pf=e["power_factor"]
    0<pf<=1 || error("功率因数错误")
    ep=[i==44 ? 0.0 : base["electric_peak_MVA"]*pf/(B-1) for i in 1:B]
    eq=[i==44 ? 0.0 : base["electric_peak_MVA"]*sqrt(1-pf^2)/(B-1) for i in 1:B]
    pe, qe=copy(ep), copy(eq)
    for g in devices
        pe[g["node"]]+=g["p_max_MW"]
    end
    for g in src["reserve"]["p2h"]
        pe[g["electric_node"]]+=g["capacity_MW"]
    end
    for j in reverse(eo[2:end])
        i=only(i for (i, k) in enodes if k==j)
        pe[i]+=pe[j]
        qe[i]+=qe[j]
    end
    lines=Dict{String,Any}[]
    for (i, j) in enodes
        # 第5章v是幅值的线性近似；不使用第3/4章平方电压或电流锥。
        r=e["path_voltage_drop_budget_pu"]*e["base_MVA"] /
          (maximum(depth)*(pe[j]+e["x_over_r"]*qe[j]))
        push!(
            lines,
            Dict(
                "id"=>"E$i-$j",
                "from"=>i,
                "to"=>j,
                "r_pu"=>r,
                "x_pu"=>r*e["x_over_r"],
                "P_limit_MW"=>e["capacity_factor"]*pe[j],
                "Q_limit_Mvar"=>e["capacity_factor"]*qe[j],
            ),
        )
    end
    cp=h["cp_J_kgK"]/1e6
    href=base["heat_peak_MW"]*h["reference_fraction"]/(N-2)
    port=[i in (1, 15) ? 0.0 : href/(cp*h["reference_delta_K"]) for i in 1:N]
    local_flow=h["source15_reference_MW"]/(cp*h["reference_delta_K"])
    demand=copy(port)
    demand[15]=-local_flow
    for j in reverse(ho[2:end])
        i=only(i for (i, k) in hnodes if k==j)
        demand[i]+=demand[j]
    end
    sources=[
        Dict(
            "id"=>"H"*string(i),
            "node"=>i,
            "m_kg_s"=>v,
            "T_min_K"=>h["S_bounds_K"][1],
            "T_max_K"=>h["S_bounds_K"][2],
        ) for (i, v) in ((1, demand[1]), (15, local_flow))
    ]
    buildings=Dict{String,Any}[]
    ref_delta=b["initial_K"]-h["ambient_reference_K"]
    ref_delta>0 && b["time_constant_h"]>0 || error("建筑参考热容非法")
    for i in 1:N
        i in (1, 15) && continue
        localdev=filter(x->x["heat_node"]==i, src["reserve"]["p2h"])
        length(localdev)<=1 || error("本版一节点至多一个表7-12设备")
        g=isempty(localdev) ? nothing : only(localdev)
        G=href/ref_delta
        push!(
            buildings,
            Dict(
                "id"=>"B$i",
                "heat_node"=>i,
                "electric_node"=>g===nothing ? i : g["electric_node"],
                "m_kg_s"=>port[i],
                "C_MWh_K"=>G*b["time_constant_h"],
                "G_MW_K"=>G,
                "T_initial_K"=>b["initial_K"],
                "T_min_K"=>b["comfort_K"][1],
                "T_max_K"=>b["comfort_K"][2],
                "R_min_K"=>h["R_bounds_K"][1],
                "R_max_K"=>h["R_bounds_K"][2],
                "P_DH_max_MW"=>g===nothing ? 0.0 : g["capacity_MW"],
                "COP_DH"=>g===nothing ? 1.0 : g["eta"],
                "terminal_rule"=>b["terminal_rule"],
            ),
        )
    end
    pipes=Dict{String,Any}[]
    for (i, j) in hnodes
        flow=demand[j]
        flow>0 || error("参考需要反向/停流；本版拒绝")
        area=flow/(h["rho_kg_m3"]*h["velocity_m_s"])
        diameter=sqrt(4area/pi)
        eps=2pi*h["insulation_W_mK"]/log1p(2h["insulation_thickness_m"]/diameter)
        push!(
            pipes,
            Dict(
                "id"=>"H$i-$j",
                "from"=>i,
                "to"=>j,
                "m_kg_s"=>flow,
                "rho_kg_m3"=>h["rho_kg_m3"],
                "area_m2"=>area,
                "length_m"=>h["length_m"],
                "loss_W_mK"=>eps,
            ),
        )
    end
    reference=r9_reserve_reference(ho, pipes, sources, buildings, h)
    for (i, pipe) in enumerate(pipes)
        kernel=fixed_flow_kernel(
            pipe["m_kg_s"],
            pipe["rho_kg_m3"],
            pipe["area_m2"],
            pipe["length_m"],
            1.0,
            pipe["loss_W_mK"];
            c_w = h["cp_J_kgK"]/1000,
        )
        pipe["history_S_K"]=fill(reference["S_K"][pipe["from"]], maximum(kernel.lags))
        pipe["history_R_K"]=fill(reference["R_K"][pipe["to"]], maximum(kernel.lags))
    end
    for g in devices
        g["kind"]=="CHP" || continue
        index=only(findall(x->x["id"]==g["source_id"], sources))
        g["P_initial_MW"]=reference["source_heat_MW"][index]/g["heat_ratio"]
    end
    price=Float64.(m["energy_price_CNY_MWh"]) .+ m["transmission_CNY_MWh"]
    d=Dict{String,Any}(
        "schema"=>"r5-dispatch-case-v2",
        "name"=>p["id"],
        "origin"=>"synthetic",
        "currency"=>"CNY",
        "T"=>T,
        "dt_h"=>1.0,
        "units"=>Dict(
            "power"=>"MW",
            "reactive"=>"Mvar",
            "energy"=>"MWh",
            "time"=>"h",
            "temperature"=>"K",
            "flow"=>"kg/s",
            "heat_capacity"=>"MWh/K",
            "heat_transfer"=>"MW/K",
            "energy_price"=>"CNY/MWh",
            "reserve_price"=>"CNY/(MW*h)",
        ),
        "ambient_K"=>b["initial_K"] .- ref_delta .* p["heat_profile"] ./ h["reference_fraction"],
        "devices"=>devices,
        "buildings"=>buildings,
        "electric"=>Dict(
            "nodes"=>B,
            "root"=>44,
            "S_base_MVA"=>e["base_MVA"],
            "v_ref_pu"=>e["voltage_ref_pu"],
            "v_min_pu"=>e["voltage_min_pu"],
            "v_max_pu"=>e["voltage_max_pu"],
            "pcc_min_MW"=>0.0,
            "pcc_max_MW"=>e["pcc_max_MW"],
            "qcc_min_Mvar"=>0.0,
            "qcc_max_Mvar"=>e["qcc_max_Mvar"],
            "P_load_MW"=>[ep[i] .* p["electric_profile"] for i in 1:B],
            "Q_load_Mvar"=>[eq[i] .* p["electric_profile"] for i in 1:B],
            "lines"=>lines,
        ),
        "heat"=>Dict(
            "nodes"=>N,
            "c_J_kgK"=>h["cp_J_kgK"],
            "terminal_rule"=>h["terminal_rule"],
            "S_min_K"=>h["S_bounds_K"][1],
            "S_max_K"=>h["S_bounds_K"][2],
            "R_min_K"=>h["R_bounds_K"][1],
            "R_max_K"=>h["R_bounds_K"][2],
            "sources"=>sources,
            "pipes"=>pipes,
        ),
        "award"=>Dict(
            "origin"=>"synthetic",
            "P_DA_MW"=>zeros(T),
            "R_up_MW"=>zeros(T),
            "R_down_MW"=>zeros(T),
            "energy_price"=>price,
            "up_price"=>m["up_price_CNY_MW_h"],
            "down_price"=>m["down_price_CNY_MW_h"],
        ),
        "realtime"=>Dict(
            "alpha_up"=>zeros(T),
            "alpha_down"=>zeros(T),
            "price"=>price,
            "delta"=>m["delta"],
            "penalty_per_MWh"=>m["penalty_CNY_MWh"],
        ),
        "r9_reserve"=>Dict(
            "schema"=>"r9-reserve-template-v1",
            "protocol"=>p,
            "protocol_sha256"=>r9_hash(p),
            "source_hashes"=>bundle.hashes,
            "reference"=>reference,
            "source_contract"=>Dict(
                "base"=>deepcopy(base),
                "p2h"=>deepcopy(src["reserve"]["p2h"]),
                "electric_edges"=>deepcopy(enodes),
                "heat_edges"=>deepcopy(hnodes),
            ),
            "optimized_to_construct_input"=>false,
            "original_input_ready"=>false,
        ),
    )
    # 零成交仅为模板；不要把它解释为已运行的无备用调度。
    c=R5DispatchCase(d)
    check=audit_r9_reserve_input(c)
    check["reference_pass"] || error("预优化稳态参考不相容："*join(check["failures"], "; "))
    c
end

# 固定温度与固定负荷的稳态代数；不通过优化器搜一组容易可行的历史。
function r9_reserve_reference(order, pipes, sources, buildings, h)
    N=length(order)
    S, R=zeros(N), zeros(N)
    sout, rout=zeros(length(pipes)), zeros(length(pipes))
    loadreturn=zeros(length(buildings))
    J=[
        fixed_flow_kernel(
            p["m_kg_s"],
            p["rho_kg_m3"],
            p["area_m2"],
            p["length_m"],
            1.0,
            p["loss_W_mK"];
            c_w = h["cp_J_kgK"]/1000,
        ).J for p in pipes
    ]
    ambient=h["ambient_reference_K"]
    for i in order
        incoming=findall(p->p["to"]==i, pipes)
        ss=filter(s->s["node"]==i, sources)
        mass=sum(pipes[j]["m_kg_s"] for j in incoming; init = 0.0)+sum(
            s["m_kg_s"] for s in ss;
            init = 0.0,
        )
        S[i]=(
            sum(pipes[j]["m_kg_s"]*sout[j] for j in incoming; init = 0.0) +
            sum(s["m_kg_s"]*h["source_reference_K"] for s in ss; init = 0.0)
        )/mass
        for (j, p) in enumerate(pipes)
            p["from"]==i && (sout[j]=ambient+J[j]*(S[i]-ambient))
        end
    end
    for (j, b) in enumerate(buildings)
        heat=b["G_MW_K"]*(b["T_initial_K"]-ambient)
        loadreturn[j]=S[b["heat_node"]]-heat/(h["cp_J_kgK"]/1e6*b["m_kg_s"])
    end
    for i in reverse(order)
        downstream=findall(p->p["from"]==i, pipes)
        bs=findall(b->b["heat_node"]==i, buildings)
        mass=sum(pipes[j]["m_kg_s"] for j in downstream; init = 0.0)+sum(
            buildings[j]["m_kg_s"] for j in bs;
            init = 0.0,
        )
        R[i]=(
            sum(pipes[j]["m_kg_s"]*rout[j] for j in downstream; init = 0.0) +
            sum(buildings[j]["m_kg_s"]*loadreturn[j] for j in bs; init = 0.0)
        )/mass
        for (j, p) in enumerate(pipes)
            p["to"]==i && (rout[j]=ambient+J[j]*(R[i]-ambient))
        end
    end
    Dict(
        "S_K"=>S,
        "R_K"=>R,
        "S_out_K"=>sout,
        "R_out_K"=>rout,
        "load_return_K"=>loadreturn,
        "source_heat_MW"=>[
            h["cp_J_kgK"]/1e6*s["m_kg_s"]*(h["source_reference_K"]-R[s["node"]]) for s in sources
        ],
        "ambient_K"=>ambient,
        "local_P2H_MW"=>zeros(length(buildings)),
        "node_order"=>order,
    )
end
