# 合成教学输入；参数构造先于正式优化，不由求解结果调参。
using PaperRebuild

function r5_dispatch_hand(; dt = 1.0)
    T=1
    device(id, kind, cap, cost) = Dict{String,Any}(
        "id"=>id,
        "kind"=>kind,
        "node"=>2,
        "p_min_MW"=>0.0,
        "p_max_MW"=>cap,
        "q_min_Mvar"=>0.0,
        "q_max_Mvar"=>0.0,
        "cost_USD_MWh"=>cost,
    )
    eb=device("EB", "EB", 0.1, 0.0)
    merge!(eb, Dict("source_id"=>"source", "heat_ratio"=>1.0))
    gt=device("GT", "GT", 0.0, 130.0)
    merge!(gt, Dict("P_initial_MW"=>0.0, "ramp_up_MW_h"=>1.0, "ramp_down_MW_h"=>1.0))
    d=Dict{String,Any}(
        "schema"=>"r5-dispatch-case-v1",
        "origin"=>"synthetic",
        "name"=>"hand_heat_042",
        "T"=>T,
        "dt_h"=>dt,
        "ambient_K"=>[283.15],
        "units"=>Dict(
            "power"=>"MW",
            "reactive"=>"Mvar",
            "energy"=>"MWh",
            "time"=>"h",
            "temperature"=>"K",
            "flow"=>"kg/s",
            "heat_capacity"=>"MWh/K",
            "heat_transfer"=>"MW/K",
            "energy_price"=>"USD/MWh",
            "reserve_price"=>"USD/(MW*h)",
        ),
        "electric"=>Dict(
            "nodes"=>2,
            "root"=>1,
            "S_base_MVA"=>1.0,
            "v_ref_pu"=>1.0,
            "v_min_pu"=>0.95,
            "v_max_pu"=>1.05,
            "pcc_min_MW"=>0.0,
            "pcc_max_MW"=>1.0,
            "qcc_min_Mvar"=>-1.0,
            "qcc_max_Mvar"=>1.0,
            "P_load_MW"=>[[0.0], [0.1]],
            "Q_load_Mvar"=>[[0.0], [0.02]],
            "lines"=>[
                Dict(
                    "id"=>"e12",
                    "from"=>1,
                    "to"=>2,
                    "r_pu"=>0.01,
                    "x_pu"=>0.005,
                    "P_limit_MW"=>1.0,
                    "Q_limit_Mvar"=>1.0,
                ),
            ],
        ),
        "heat"=>Dict(
            "terminal_rule"=>"free",
            "nodes"=>2,
            "c_J_kgK"=>4200.0,
            "S_min_K"=>303.15,
            "S_max_K"=>353.15,
            "R_min_K"=>293.15,
            "R_max_K"=>343.15,
            "sources"=>[
                Dict(
                    "id"=>"source",
                    "node"=>1,
                    "m_kg_s"=>1.0,
                    "T_min_K"=>330.15,
                    "T_max_K"=>330.15,
                ),
            ],
            "pipes"=>[
                Dict(
                    "id"=>"h12",
                    "from"=>1,
                    "to"=>2,
                    "m_kg_s"=>1.0,
                    "rho_kg_m3"=>1000.0,
                    "area_m2"=>0.01,
                    "length_m"=>360.0,
                    "loss_W_mK"=>0.0,
                    "history_S_K"=>fill(330.15, ceil(Int, 1/dt)),
                    "history_R_K"=>fill(320.15, ceil(Int, 1/dt)),
                ),
            ],
        ),
        "devices"=>[eb, gt],
        "buildings"=>[
            Dict(
                "id"=>"building",
                "heat_node"=>2,
                "electric_node"=>2,
                "m_kg_s"=>1.0,
                "C_MWh_K"=>0.01,
                "G_MW_K"=>0.0042,
                "T_initial_K"=>293.15,
                "T_min_K"=>293.15,
                "T_max_K"=>293.15,
                "R_min_K"=>320.15,
                "R_max_K"=>320.15,
                "P_DH_max_MW"=>0.0,
                "COP_DH"=>1.0,
                "terminal_rule"=>"initial",
            ),
        ],
        "award"=>Dict(
            "origin"=>"synthetic",
            "P_DA_MW"=>[0.142],
            "R_up_MW"=>[0.0],
            "R_down_MW"=>[0.0],
            "energy_price"=>[100.0],
            "up_price"=>[5.0],
            "down_price"=>[2.0],
        ),
        "realtime"=>Dict(
            "alpha_up"=>[0.0],
            "alpha_down"=>[0.0],
            "price"=>[100.0],
            "penalty_USD_MWh"=>1000.0,
            "delta"=>0.0,
        ),
    )
    d
end

function r5_dispatch_teaching()
    d=r5_dispatch_hand()
    d["name"]="four_period_IES"
    d["T"]=4
    d["ambient_K"]=[283.15, 282.15, 283.15, 284.15]
    e=d["electric"]
    e["P_load_MW"]=[[0.0, 0.0, 0.0, 0.0], [0.12, 0.14, 0.13, 0.12]]
    e["Q_load_Mvar"]=[[0.0, 0.0, 0.0, 0.0], [0.02, 0.02, 0.02, 0.02]]
    s=d["heat"]["sources"][1]
    s["T_min_K"], s["T_max_K"]=313.15, 353.15
    p=d["heat"]["pipes"][1]
    p["length_m"]=90.0
    p["loss_W_mK"]=0.05
    p["history_S_K"], p["history_R_K"]=[333.15], [323.15]
    b=d["buildings"][1]
    merge!(
        b,
        Dict(
            "C_MWh_K"=>0.02,
            "G_MW_K"=>0.003,
            "T_min_K"=>292.15,
            "T_max_K"=>294.15,
            "R_min_K"=>303.15,
            "R_max_K"=>343.15,
            "P_DH_max_MW"=>0.05,
            "COP_DH"=>0.95,
        ),
    )
    d["devices"][1]["heat_ratio"]=0.95
    d["devices"][2]["p_max_MW"]=0.15
    push!(
        d["devices"],
        Dict(
            "id"=>"CHP",
            "kind"=>"CHP",
            "node"=>2,
            "p_min_MW"=>0.0,
            "p_max_MW"=>0.08,
            "q_min_Mvar"=>-0.03,
            "q_max_Mvar"=>0.03,
            "cost_USD_MWh"=>90.0,
            "source_id"=>"source",
            "heat_ratio"=>1.0,
            "P_initial_MW"=>0.03,
            "ramp_up_MW_h"=>0.08,
            "ramp_down_MW_h"=>0.08,
        ),
    )
    push!(
        d["devices"],
        Dict(
            "id"=>"PV",
            "kind"=>"PV",
            "node"=>2,
            "p_min_MW"=>0.0,
            "p_max_MW"=>0.08,
            "q_min_Mvar"=>0.0,
            "q_max_Mvar"=>0.0,
            "cost_USD_MWh"=>5.0,
            "available_MW"=>[0.0, 0.04, 0.08, 0.02],
        ),
    )
    d["award"]=Dict(
        "origin"=>"synthetic",
        "P_DA_MW"=>fill(0.14, 4),
        "R_up_MW"=>fill(0.03, 4),
        "R_down_MW"=>fill(0.03, 4),
        "energy_price"=>[80.0, 100.0, 140.0, 100.0],
        "up_price"=>fill(5.0, 4),
        "down_price"=>fill(2.0, 4),
    )
    d["realtime"]=Dict(
        "alpha_up"=>[0.0, 1.0, 0.0, 0.5],
        "alpha_down"=>[0.0, 0.0, 1.0, 0.0],
        "price"=>[80.0, 120.0, 150.0, 100.0],
        "penalty_USD_MWh"=>1000.0,
        "delta"=>0.1,
    )
    d
end
