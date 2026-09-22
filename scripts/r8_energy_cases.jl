isdefined(@__MODULE__, :r8_mechanism_input) || include("r8_cases.jl")

# 先由容量和逐时守恒推导，再用于开发/正式优化；不接收任何历史最优值或调参结果。
"""构造四小时合成储热机制输入；固定初态、容量、负荷与全故障集合，UA是唯一散热变体。"""
function r8_shift_input(root; UA = 0.0)
    original=r8_mechanism_input(root, "tie_three"; UA, resource = "no_battery")
    d=deepcopy(original.case.normal.data)
    d["name"]="synthetic_r8_four_hour_heat_shift_ua$(Int(UA))"
    demand=[0.5, 0.5, 0.8, 0.8]
    d["electric"]["load_MW"]=[zeros(4), demand ./ 2, demand ./ 2]
    for g in d["devices"]
        if g["kind"]=="CHP"
            g["P_max_MW"]=0.3
            g["previous_P_MW"]=[0.3, 0.3]
        elseif g["kind"]=="GT"
            g["P_max_MW"]=0.5
        elseif g["kind"]=="EB"
            g["P_max_MW"]=0.25
        end
    end
    h=d["heat"]
    # 原设S_min在正散热下会使第一个出水低于温区；优化前为两个UA组统一给1K余量。
    h["S_reference_K"]=h["S_min_K"]+1.0
    h["R_reference_K"]=h["S_reference_K"]-0.4/(h["c_J_kgK"]/1e6*5.0)
    for p in h["pipes"], side in ("S", "R")
        p["history_$(side)_K"]=[fill(h["$(side)_reference_K"], 2)]
        for profile in p["initial_$(side)_profiles"]
            profile["temperature_K"].=h["$(side)_reference_K"]
        end
    end
    rules=deepcopy(original.case.specification)
    rules["events"]=[
        Dict(
            "id"=>"four_hour",
            "event_start"=>1,
            "periods"=>4,
            "renewable_factor"=>0.5,
            "loss_limit_MWh"=>0.0,
        ),
    ]
    c=R7PlanningCase(R7NormalCase(d), rules)
    arrays=Dict(
        "pipe"=>fill(5.0, 1, 4),
        "source"=>[5.0 5 5 5; 0 0 0 0],
        "load"=>[0.0 0 0 0; 5 5 5 5],
    )
    kwargs=Dict{Symbol,Any}()
    for (key, a) in arrays
        kwargs[Symbol(key*"_min")]=a
        kwargs[Symbol(key*"_max")]=a
    end
    ns=r7_normal_flow_spec(c.normal; kwargs..., thermal = :lossy_gauss)
    bounds=Dict{String,Any}()
    for pair in PaperRebuild.r7_planning_pairs(c)
        bounds[PaperRebuild.r7_planning_pair_key(pair)]=Dict(
            key*suffix=>copy(a) for (key, a) in arrays for suffix in ("_min", "_max")
        )
    end
    flow=r7_flow_planning_spec(c; normal_flow = ns, recovery_bounds = bounds, substeps = 1)
    (; case = c, flow)
end

"""独立水团回放0.5/0.5/0.3/0.3MW热源手算轨迹；不是优化结果，零UA下初末状态相同。"""
function r8_shift_hand_replay()
    cp=4200.0
    f=5.0
    M=18000.0
    S0=334.15
    R0=S0-0.4/(cp*f/1e6)
    S=PaperRebuild.r7_pipe_state([M], [S0])
    R=PaperRebuild.r7_pipe_state([M], [R0])
    reference=293.15
    energy0=cp*M*(S0+R0-2reference)/3.6e9
    rows=NamedTuple[]
    for (t, H) in enumerate([0.5, 0.5, 0.3, 0.3])
        Sold=PaperRebuild.r7_pipe_inventory(S; cp_J_kgK = cp, reference_K = reference).mean_K
        Rold=PaperRebuild.r7_pipe_inventory(R; cp_J_kgK = cp, reference_K = reference).mean_K
        Sin=Rold+H/(cp*f/1e6)
        Rin=Sold-0.4/(cp*f/1e6)
        a=PaperRebuild.r7_pipe_step(
            S;
            mass_flow_kg_s = f,
            inlet_K = Sin,
            ambient_K = 293.15,
            dt_h = 1.0,
            cp_J_kgK = cp,
            UA_W_K = 0.0,
            reference_K = reference,
        )
        b=PaperRebuild.r7_pipe_step(
            R;
            mass_flow_kg_s = f,
            inlet_K = Rin,
            ambient_K = 293.15,
            dt_h = 1.0,
            cp_J_kgK = cp,
            UA_W_K = 0.0,
            reference_K = reference,
        )
        S, R=a.state, b.state
        E=PaperRebuild.r7_pipe_inventory(S; cp_J_kgK = cp, reference_K = reference).relative_heat_MWh+PaperRebuild.r7_pipe_inventory(
            R;
            cp_J_kgK = cp,
            reference_K = reference,
        ).relative_heat_MWh
        EB=(H-0.3)/0.95
        load=t<=2 ? 0.5 : 0.8
        GT=load+EB-0.3
        push!(
            rows,
            (;
                t,
                source_MW = H,
                load_MW = 0.4,
                CHP_MW = 0.3,
                GT_MW = GT,
                EB_MW = EB,
                S_in_K = Sin,
                R_in_K = Rin,
                stored_above_initial_MWh = E-energy0,
                electric_residual_MW = 0.3+GT-EB-load,
                heat_residual_MW = cp*f/1e6*(Sold-Rin)-0.4,
            ),
        )
    end
    rows
end
