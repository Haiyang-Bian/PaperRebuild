using PaperRebuild, TOML

function r8_mechanism_input(root, family; UA = 10.0, resource = "all", control = "fixed")
    family in ("legacy", "tie_three") || error("未知R8案例")
    resource in ("all", "no_battery", "no_net_heat_charge", "no_reconfiguration") ||
        error("未知资源")
    control in ("fixed", "joint_continuous") || error("未知流量域")
    d=TOML.parsefile(joinpath(root, "configs/r7/normal-reserve-hand.toml"))
    d["name"]="synthetic_r8_$(family)_$(resource)_ua$(Int(UA))"
    d["battery_rule"]="per_period_exclusive_v1"
    for p in d["heat"]["pipes"]
        p["UA_S_W_K"], p["UA_R_W_K"]=UA, UA
    end
    if family=="tie_three"
        # 预声明机制输入：增加受保护联络边及负荷侧GT，不根据优化收益调参。
        e=d["electric"]
        e["nodes"]=3
        e["load_MW"]=[zeros(4), fill(0.4, 4), fill(0.4, 4)]
        e["tan_phi"]=zeros(3)
        e["root_eligible"]=ones(Int, 3)
        e["shed_fraction_max"]=ones(3)
        e["switch_budget"]=3
        e["flow_domain"]="signed"
        line=deepcopy(only(e["lines"]))
        l2, l3=deepcopy(line), deepcopy(line)
        l2["from"], l2["to"]=2, 3
        l3["from"], l3["to"], l3["base_closed"], l3["vulnerable"]=1, 3, 0, false
        e["lines"]=[line, l2, l3]
        d["devices"][2]["electric_node"]=3
        push!(
            d["devices"],
            Dict(
                "id"=>"GT2",
                "kind"=>"GT",
                "electric_node"=>2,
                "P_max_MW"=>0.4,
                "Q_max_Mvar"=>0.5,
                "cost_P_USD_MWh"=>140.0,
            ),
        )
        push!(
            d["devices"],
            Dict(
                "id"=>"EB1",
                "kind"=>"EB",
                "electric_node"=>1,
                "heat_node"=>1,
                "P_max_MW"=>0.2,
                "heat_ratio"=>0.95,
                "cost_P_USD_MWh"=>2.0,
            ),
        )
    end
    if resource=="no_battery"
        filter!(g->g["kind"]!="BES", d["devices"])
        # 删除设备同时删除它独有的成网资格；不能保留一个不存在的电池来充当孤岛根。
        for j in 1:d["electric"]["nodes"]
            any(g->g["electric_node"]==j&&g["kind"] in ("CHP", "GT", "BES"), d["devices"]) ||
                (d["electric"]["root_eligible"][j]=0)
        end
    end
    rules=TOML.parsefile(joinpath(root, "configs/r7/planning-reserve-hand.toml"))
    foreach(e->e["loss_limit_MWh"]=1.2, rules["events"])
    c=R7PlanningCase(R7NormalCase(d), rules)
    arrays=Dict(
        "pipe"=>fill(5.0, 1, 4),
        "source"=>[5.0 5 5 5; 0 0 0 0],
        "load"=>[0.0 0 0 0; 5 5 5 5],
    )
    kwargs=Dict{Symbol,Any}()
    for (k, x) in arrays
        kwargs[Symbol(k*"_min")]=control=="fixed" ? x : map(v->v>0 ? 0.05 : 0.0, x)
        kwargs[Symbol(k*"_max")]=control=="fixed" ? x : map(v->v>0 ? 10.0 : 0.0, x)
    end
    ns=r7_normal_flow_spec(c.normal; kwargs..., thermal = :lossy_gauss)
    rb=Dict{String,Any}()
    for pair in PaperRebuild.r7_planning_pairs(c)
        T=rules["events"][pair.event]["periods"]
        flux=family=="legacy" && any(==(1), pair.fault) ? 0.0 : 5.0
        raw=Dict(
            "pipe"=>fill(flux, 1, T),
            "source"=>vcat(fill(flux, 1, T), zeros(1, T)),
            "load"=>vcat(zeros(1, T), fill(flux, 1, T)),
        )
        b=Dict{String,Any}()
        for (k, x) in raw
            cap=k=="pipe" ? [10.0] : k=="source" ? [10.0, 0.0] : [0.0, 10.0]
            b[k*"_min"]=control=="fixed" ? x : zeros(size(x))
            b[k*"_max"]=control=="fixed" ? x : repeat(reshape(cap, :, 1), 1, T)
        end
        rb[PaperRebuild.r7_planning_pair_key(pair)]=b
    end
    flow=r7_flow_planning_spec(c; normal_flow = ns, recovery_bounds = rb, substeps = 1)
    (;
        case = c,
        flow,
        topology = resource=="no_reconfiguration" ? :retain_surviving : :reconfigure,
        heat_preparation = resource=="no_net_heat_charge" ? :no_net_charge : :free,
    )
end
