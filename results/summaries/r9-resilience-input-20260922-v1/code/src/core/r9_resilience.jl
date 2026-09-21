# 第7.5节输入生成；不读取作者费用或失供结果，不调用优化器。
function r9_resilience_steady(base, top, h)
    edges=top["heat"]["edges"]
    order, _=r9_tree_order(38, edges, 1)
    cp, rho=h["cp_J_kgK"], h["rho_kg_m3"]
    ambient, inlet=h["ambient_reference_K"], h["source_reference_K"]
    heat=[i in (1, 15) ? 0.0 : base["heat_peak_MW"]*h["reference_fraction"]/36 for i in 1:38]
    loads=heat/(cp/1e6*h["reference_delta_K"])
    sources=zeros(38)
    sources[15]=h["source15_reference_MW"]/(cp/1e6*h["reference_delta_K"])
    sub=loads-sources
    for j in reverse(order[2:end])
        i=only(i for (i, k) in edges if k==j)
        sub[i]+=sub[j]
    end
    sources[1]=sub[1]
    flows=[sub[j] for (i, j) in edges]
    all(>(0), flows) || error("第7.5节参考热流非正，拒绝自动改负荷或源分配")
    volumes=flows/rho/h["velocity_m_s"]*h["length_m"]
    diameter=sqrt.(4 .* flows/rho/h["velocity_m_s"]/pi)
    UA=2pi*h["insulation_W_mK"]*h["length_m"] ./ log1p.(2h["insulation_thickness_m"] ./ diameter)
    decay=exp.(-UA ./ (cp .* flows))
    S, R, sout, rout=zeros(38), zeros(38), zeros(37), zeros(37)
    for i in order
        ins=findall(x->x[2]==i, edges)
        mass=sources[i]+sum(flows[a] for a in ins; init = 0.0)
        S[i]=(sources[i]*inlet+sum(flows[a]*sout[a] for a in ins; init = 0.0))/mass
        for (a, (j, k)) in enumerate(edges)
            j==i && (sout[a]=ambient+(S[i]-ambient)*decay[a])
        end
    end
    Td=[loads[i]>0 ? S[i]-heat[i]/(cp/1e6*loads[i]) : 0.0 for i in 1:38]
    for i in reverse(order)
        outs=findall(x->x[1]==i, edges)
        mass=loads[i]+sum(flows[a] for a in outs; init = 0.0)
        R[i]=(loads[i]*Td[i]+sum(flows[a]*rout[a] for a in outs; init = 0.0))/mass
        for (a, (j, k)) in enumerate(edges)
            k==i && (rout[a]=ambient+(R[i]-ambient)*decay[a])
        end
    end
    sourceheat=cp/1e6 .* sources .* (inlet .- R)
    loss=sum(cp/1e6*flows[a]*(S[i]-sout[a]+R[j]-rout[a]) for (a, (i, j)) in enumerate(edges))
    abs(sum(sourceheat)-sum(heat)-loss)<=1e-10 || error("稳态参考热量不守恒")
    (; flows, sources, loads, volumes, UA, S, R, sourceheat, loss)
end

"""
    r9_resilience_template(source_directory, protocol_path; critical_set="nodes_figure_7_12")

按第7.5节原图44电/38热节点和原额定表生成显式替代输入，返回正常案例、事件规则及构造证据。
采用统一15分钟网格、合成逐节点负荷、有限开关/故障集和精确稳态空间初温；金额CNY，功率MW，
流率kg/s、温度K、时间h。所有新增参数由独立协议给出，生成过程中不求解、不写文件。
两套原图关键节点分别生成，物理总负荷及设备完全相同。设备不继承第7.2/7.3的扩容或电池。
本入口仅冻结规定正常流量的条件基准；不宣称完成变流量保供、作者同输入或完整故障认证。
"""
function r9_resilience_template(source_directory, protocol_path; critical_set = "nodes_figure_7_12")
    bundle=load_r9_sources(source_directory)
    p=TOML.parsefile(protocol_path)
    p["schema"]=="r9-resilience-input-protocol-v1" &&
    p["source_section"]=="7.5" &&
    p["currency"]=="CNY" &&
    p["dt_h"]==0.25 &&
    p["periods"]==96 || error("保供输入协议错误")
    critical_set in p["critical_sets"] || error("未声明的关键节点集合")
    review=TOML.parsefile(joinpath(source_directory, "resilience-review.toml"))
    src, top=bundle.data["inputs.toml"], bundle.data["topology.toml"]
    base, assets=src["base"], src["resilience"]
    e, h=p["electric"], p["heat"]
    T, dt=p["periods"], p["dt_h"]
    for key in ("electric_profile", "heat_profile", "pv_profile")
        length(p[key])==24 && all(x->isfinite(x)&&0<=x<=1, p[key]) && maximum(p[key])==1 ||
            error("合成小时比例非法")
    end
    ep, hp, pv=(
        repeat(Float64.(p[k]); inner = 4) for
        k in ("electric_profile", "heat_profile", "pv_profile")
    )
    0<e["power_factor"]<=1 || error("功率因数错误")
    p["initial_chp"]=="CHP1_off; CHP2_on_at_steady_source1_heat_divided_by_1.2" ||
        error("初始启停规则错误")
    h["initial_rule"]=="exact_positive_steady_exponential_supply_and_return; instantaneous_mass_weighted_mixing" ||
        error("初始空间状态规则错误")
    h["normal_flow_rule"]=="fixed_reference_flows; conditional_preplan_only" ||
        error("正常流量规则错误")
    sets=only(x for x in review["finding"] if x["id"]=="R9-RS02")
    criticals=Dict(
        k=>[
            i in sets[k] ? assets["critical_active_capacity_MW"]/length(sets[k]) : 0.0 for i in 1:44
        ] for k in p["critical_sets"]
    )
    minimum_load=max.((criticals[k] for k in p["critical_sets"])...)
    total=base["electric_peak_MVA"]*e["power_factor"]
    remaining=total-sum(minimum_load)
    remaining>0 || error("关键负荷与共同总需求冲突")
    load=minimum_load+[i==44 ? 0.0 : remaining/43 for i in 1:44]
    all(load .>= criticals[critical_set]) || error("关键负荷超过总负荷")
    steady=r9_resilience_steady(base, top, h)
    devices=Dict{String,Any}[]
    tanphi=sqrt(1-e["power_factor"]^2)/e["power_factor"]
    for g in assets["chp"]
        on=g["id"]=="CHP2"
        prior=on ? steady.sourceheat[1]/g["H_over_P"] : 0.0
        g["P_min_MW"]*on<=prior<=g["P_max_MW"]*on || error("稳态CHP初值越界")
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"CHP",
                "electric_node"=>g["electric_node"],
                "heat_node"=>g["heat_node"],
                "P_min_MW"=>g["P_min_MW"],
                "P_max_MW"=>g["P_max_MW"],
                "Q_min_Mvar"=>0.0,
                "Q_max_Mvar"=>g["P_max_MW"]*e["generator_tan_phi_capacity"],
                "heat_ratio"=>g["H_over_P"],
                "previous_commitment"=>Int(on),
                "previous_P_MW"=>[prior],
                "previous_duration_h"=>p["previous_duration_h"],
                "min_on_h"=>p["min_on_h"],
                "min_off_h"=>p["min_off_h"],
                "terminal_rule"=>"carry_obligation",
                "ramp_MW_h"=>g["P_max_MW"]*p["chp_ramp_fraction_per_hour"],
                "startup_MW"=>g["P_max_MW"],
                "shutdown_MW"=>g["P_max_MW"],
                "startup_cost"=>g["startup_CNY"],
                "cost_P_MWh"=>g["fuel_CNY_MWh_electric"],
                "cost_basis"=>"electric_equivalent",
            ),
        )
    end
    for g in base["eb"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"EB",
                "electric_node"=>g["electric_node"],
                "heat_node"=>g["heat_node"],
                "P_max_MW"=>g["H_max_MW"]/g["eta"],
                "heat_ratio"=>g["eta"],
                "cost_P_MWh"=>0.0,
            ),
        )
    end
    steady.sourceheat[15]<=only(g["H_max_MW"] for g in base["eb"] if g["heat_node"]==15) ||
        error("参考源15超容量")
    for g in assets["gt"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"GT",
                "electric_node"=>g["electric_node"],
                "P_max_MW"=>g["P_max_MW"],
                "Q_max_Mvar"=>g["P_max_MW"]*e["generator_tan_phi_capacity"],
                "cost_P_MWh"=>g["cost_CNY_MWh"],
            ),
        )
    end
    for g in base["pv"]
        push!(
            devices,
            Dict(
                "id"=>g["id"],
                "kind"=>"PV",
                "electric_node"=>g["electric_node"],
                "P_max_MW"=>g["P_max_MW"],
                "available_MW"=>[[g["P_max_MW"]*v] for v in pv],
                "cost_P_MWh"=>g["cost_CNY_MWh"],
            ),
        )
    end
    edges=top["electric"]["edges"]
    order, depth=r9_tree_order(44, edges, 44)
    pe, qe=copy(load), load*tanphi
    for g in devices
        pe[g["electric_node"]]+=g["P_max_MW"]
        qe[g["electric_node"]]+=get(g, "Q_max_Mvar", 0.0)
    end
    for j in reverse(order[2:end])
        i=only(i for (i, k) in edges if k==j)
        pe[i]+=pe[j]
        qe[i]+=qe[j]
    end
    vulnerable=Set(minmax(x...) for x in e["vulnerable_edges"])
    lines=Dict{String,Any}[]
    for (i, j) in edges
        r=e["path_voltage_drop_budget_pu"]*e["base_MVA"]/(
            maximum(depth)*(pe[j]+e["x_over_r"]*qe[j])
        )
        push!(
            lines,
            Dict(
                "from"=>i,
                "to"=>j,
                "base_closed"=>1,
                "vulnerable"=>minmax(i, j) in vulnerable,
                "r_pu"=>r,
                "x_pu"=>r*e["x_over_r"],
                "P_max_MW"=>e["capacity_factor"]*pe[j],
                "Q_max_Mvar"=>e["capacity_factor"]*qe[j],
            ),
        )
    end
    # 新联络线参数只由原树路径决定；不读取优化器输出或原文收益反推。
    for (a, b) in e["ties"]
        previous=Dict(a=>(0, 0))
        queue=[a]
        for i in queue, (k, (u, v)) in enumerate(edges)
            j=u==i ? v : v==i ? u : 0
            if j!=0 && !haskey(previous, j)
                previous[j]=(i, k)
                push!(queue, j)
            end
        end
        path=Int[]
        node=b
        while node!=a
            node, k=previous[node]
            push!(path, k)
        end
        push!(
            lines,
            Dict(
                "from"=>a,
                "to"=>b,
                "base_closed"=>0,
                "vulnerable"=>minmax(a, b) in vulnerable,
                "r_pu"=>sum(lines[k]["r_pu"] for k in path),
                "x_pu"=>sum(lines[k]["x_pu"] for k in path),
                "P_max_MW"=>minimum(lines[k]["P_max_MW"] for k in path),
                "Q_max_Mvar"=>minimum(lines[k]["Q_max_Mvar"] for k in path),
            ),
        )
    end
    tariff=base["tariff"]
    prices=[
        begin
            hour=(t-1)*dt
            band=any(a<=hour<b for (a, b) in tariff["peak_intervals_h"]) ? "peak" :
                 any(a<=hour<b for (a, b) in tariff["flat_intervals_h"]) ? "flat" : "valley"
            tariff[band*"_CNY_MWh"]
        end for t in 1:T
    ]
    ed=Dict(
        "nodes"=>44,
        "pcc_node"=>44,
        "S_base_MVA"=>e["base_MVA"],
        "v_min_pu"=>e["v_min_pu"],
        "v_max_pu"=>e["v_max_pu"],
        "v_ref_pu"=>e["v_ref_pu"],
        "flow_domain"=>"signed",
        "pcc_min_MW"=>0.0,
        "pcc_max_MW"=>e["pcc_max_MW"],
        "qcc_min_Mvar"=>0.0,
        "qcc_max_Mvar"=>e["qcc_max_Mvar"],
        "price_MWh"=>prices,
        "load_MW"=>[load[i]*ep for i in 1:44],
        "tan_phi"=>fill(tanphi, 44),
        "root_eligible"=>[Int(i in e["root_eligible_nodes"]) for i in 1:44],
        "switch_budget"=>e["switch_budget"],
        "fault_budget"=>e["fault_budget"],
        "shed_fraction_max"=>fill(e["shedding_fraction_max"], 44),
        "lines"=>lines,
    )
    pipes=Dict{String,Any}[]
    cp, rho=h["cp_J_kgK"], h["rho_kg_m3"]
    for (a, (i, j)) in enumerate(top["heat"]["edges"])
        f, V, ua=steady.flows[a], steady.volumes[a], steady.UA[a]
        pipe=Dict{String,Any}(
            "from"=>i,
            "to"=>j,
            "volume_S_m3"=>V,
            "volume_R_m3"=>V,
            "UA_S_W_K"=>ua,
            "UA_R_W_K"=>ua,
            "flow_max_kg_s"=>h["flow_capacity_factor"]*f,
            "flow_change_max_kg_s"=>h["flow_change_fraction"]*f,
            "normal_flow_kg_s"=>fill(f, T),
            "mu_S_Pa_s2_kg2"=>h["reference_pipe_drop_Pa"]/f^2,
            "mu_R_Pa_s2_kg2"=>h["reference_pipe_drop_Pa"]/f^2,
            "valve_max_Pa"=>h["valve_max_Pa"],
        )
        for (side, Tin) in (("S", steady.S[i]), ("R", steady.R[j]))
            state=R7PipeState([
                R7PipeSegment(
                    rho*V,
                    h["ambient_reference_K"],
                    Tin-h["ambient_reference_K"],
                    ua/(rho*V*cp*f),
                    true,
                ),
            ])
            pipe["initial_$(side)_profiles"]=[
                r7_initial_profile(state; provenance = p["id"]*": exact steady exponential"),
            ]
        end
        push!(pipes, pipe)
    end
    hd=Dict(
        "nodes"=>38,
        "available"=>true,
        "c_J_kgK"=>cp,
        "rho_kg_m3"=>rho,
        "S_min_K"=>h["S_bounds_K"][1],
        "S_max_K"=>h["S_bounds_K"][2],
        "R_min_K"=>h["R_bounds_K"][1],
        "R_max_K"=>h["R_bounds_K"][2],
        "S_reference_K"=>h["source_reference_K"],
        "R_reference_K"=>h["source_reference_K"]-h["reference_delta_K"],
        "ambient_K"=>fill(h["ambient_reference_K"], T),
        "load_MW"=>[i in (1, 15) ? zeros(T) : base["heat_peak_MW"]/36*hp for i in 1:38],
        "source_flow_kg_s"=>[fill(f, T) for f in steady.sources],
        "load_flow_kg_s"=>[fill(f, T) for f in steady.loads],
        "source_flow_max"=>steady.sources*h["flow_capacity_factor"],
        "load_flow_max"=>steady.loads*h["flow_capacity_factor"],
        "source_delta_min"=>zeros(38),
        "source_delta_max"=>[
            f>0 ? h["S_bounds_K"][2]-h["R_bounds_K"][1] : 0.0 for f in steady.sources
        ],
        "load_delta_min"=>zeros(38),
        "load_delta_max"=>[f>0 ? h["S_bounds_K"][2]-h["R_bounds_K"][1] : 0.0 for f in steady.loads],
        "shed_fraction_max"=>fill(h["shedding_fraction_max"], 38),
        "pressure_max_Pa"=>h["pressure_max_Pa"],
        "delta_pressure_min_Pa"=>h["delta_pressure_min_Pa"],
        "delta_pressure_max_Pa"=>h["delta_pressure_max_Pa"],
        "pipes"=>pipes,
    )
    data=Dict(
        "schema"=>"r7-normal-case-v2",
        "currency"=>"CNY",
        "name"=>p["id"]*"_"*critical_set,
        "origin"=>"synthetic",
        "periods"=>T,
        "dt_h"=>dt,
        "probabilities"=>[1.0],
        "flow_control"=>"prescribed_positive",
        "thermal_model"=>"plug_flow_reference_v1",
        "heat_terminal_rule"=>p["heat_terminal_rule"],
        "battery_rule"=>p["battery_rule"],
        "scenario_information"=>"full_trajectory_after_shared_commitment",
        "units"=>Dict(
            "power"=>"MW",
            "reactive"=>"Mvar",
            "energy"=>"MWh",
            "time"=>"h",
            "temperature"=>"K",
            "flow"=>"kg/s",
            "pressure"=>"Pa",
            "price"=>"CNY/MWh",
        ),
        "electric"=>ed,
        "heat"=>hd,
        "devices"=>devices,
    )
    c=with_r7_electric_domain(
        R7NormalCase(data),
        e["recovery_domain"];
        provenance = e["root_provenance"],
    )
    c=with_r7_switch_control(
        c,
        vcat(e["base_switches"], e["ties"]);
        provenance = e["switch_provenance"],
    )
    c=with_r7_critical_load(
        c,
        reduce(vcat, [permutedims(v*ep) for v in criticals[critical_set]]);
        provenance = p["critical_allocation"]*"; "*critical_set,
    )
    a, b=p["pilot"]["event_start_h"], p["pilot"]["event_end_h"]
    isinteger(a/dt) && isinteger((b-a)/dt) || error("事件不能精确落在共同网格")
    event=Dict(
        "id"=>"event1_10_14",
        "event_start"=>Int(a/dt)+1,
        "periods"=>Int((b-a)/dt),
        "renewable_factor"=>p["pilot"]["renewable_factor"],
        "loss_limit_MWh"=>p["pilot"]["loss_limit_MWh"],
    )
    spec=Dict(
        "schema"=>"r7-planning-spec-v1",
        "normal_domain"=>"prescribed_positive_fixed_electric_topology",
        "recovery_model"=>"r7_recovery_port_checked_v1",
        "events"=>[event],
    )
    planning=R7PlanningCase(c, spec)
    eventcase=r7_event_template(planning, 1)
    faults=Dict{String,Any}()
    for (id, failed) in zip(p["pilot"]["fault_ids"], p["pilot"]["fault_edges"])
        selected=Set(minmax(x...) for x in failed)
        fault=[Int(minmax(l["from"], l["to"]) in selected) for l in lines]
        sum(fault)==length(selected) || error("预运行故障端点不存在")
        r7_check_fault(eventcase, fault)
        faults[id]=fault
    end
    evidence=Dict(
        "origin"=>p["origin"],
        "protocol_sha256"=>bytes2hex(sha256(read(protocol_path))),
        "source_hashes"=>bundle.hashes,
        "review_sha256"=>bytes2hex(
            sha256(read(joinpath(source_directory, "resilience-review.toml"))),
        ),
        "total_peak_MW"=>sum(load),
        "critical_peak_MW"=>sum(criticals[critical_set]),
        "steady_source_heat_MW"=>steady.sourceheat,
        "steady_heat_loss_MW"=>steady.loss,
        "fault_universe_count"=>length(r7_faults(eventcase)),
        "pilot_faults"=>faults,
        "conditional_fixed_flow_only"=>true,
        "author_input_complete"=>false,
    )
    (; normal = c, planning, protocol = p, evidence)
end
