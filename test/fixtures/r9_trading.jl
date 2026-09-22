# MIT项目合成解析例；不含论文参数。零线路损耗仅用于手算能量和现金流。
function r9_trading_fixture(; T = 1, dt = 1.0, reverse = false, store = false)
    actor(id, en, hn, P, H) = Dict{String,Any}(
        "id"=>id,
        "electric_node"=>en,
        "heat_node"=>hn,
        "P_load"=>fill(P, T),
        "P_preferred"=>fill(P, T),
        "H_load"=>fill(H, T),
        "H_preferred"=>fill(H, T),
        "flex"=>0.0,
        "sat_P"=>0.0,
        "sat_H"=>0.0,
        "Q_ratio"=>0.0,
        "retail_limit_MW"=>10.0,
    )
    device(id, kind, owner, en, hn, cap; ratio = 0.0, energy = 0.0) = Dict{String,Any}(
        "id"=>id,
        "kind"=>kind,
        "owner"=>owner,
        "electric_node"=>en,
        "heat_node"=>hn,
        "power_max_MW"=>cap,
        "power_min_MW"=>0.0,
        "availability_MW"=>fill(cap, T),
        "heat_ratio"=>ratio,
        "energy_max_MWh"=>energy,
        "initial_MWh"=>energy/2,
        "eta_ch"=>1.0,
        "eta_dis"=>1.0,
        "loss_per_h"=>0.0,
        "cost_CNY_MWh"=>0.0,
        "origin"=>"synthetic_analytical_fixture",
    )
    actors=[
        actor("DSO", 0, 0, 0.0, 0.0),
        actor("A1", 2, 2, 1.0, 0.0),
        actor("A2", 3, 3, 1.0, reverse ? 0.0 : 1.0),
    ]
    devices=[
        device("PV", "PV", 2, 2, 0, 2.0),
        device("P2H", "P2H", reverse ? 3 : 1, reverse ? 3 : 1, reverse ? 3 : 1, 2.0; ratio = 1.0),
    ]
    store && push!(devices, device("BS", "BS", 2, 2, 0, 1.0; energy = 1.0))
    edges=[
        Dict(
            "from"=>i,
            "to"=>i+1,
            "r_pu"=>0.0,
            "x_pu"=>0.0,
            "P_max_MW"=>10.0,
            "Q_max_Mvar"=>10.0,
            "ell_max_pu"=>100.0,
        ) for i in 1:2
    ]
    pipes=[
        Dict(
            "from"=>i,
            "to"=>i+1,
            "H_max_MW"=>4.0,
            "flow_max_kg_s"=>100.0,
            "length_m"=>1.0,
            "U_W_mK"=>0.0,
            "S_ref_K"=>363.15,
            "R_ref_K"=>323.15,
            "ambient_K"=>283.15,
            "loss_MW"=>0.0,
        ) for i in 1:2
    ]
    prices=Dict(
        k=>fill(p, T) for (k, p) in (
            "P_buy"=>200.0,
            "P_sell"=>60.0,
            "H_buy"=>160.0,
            "H_sell"=>40.0,
            "P_peer"=>130.0,
            "H_peer"=>100.0,
            "fee"=>5.0,
        )
    )
    R9TradingCase(
        Dict(
            "schema"=>"r9-trading-case-v1",
            "id"=>"analytical-r9-trading",
            "origin"=>"synthetic",
            "T"=>T,
            "dt_h"=>dt,
            "units"=>Dict(
                "power"=>"MW",
                "energy"=>"MWh",
                "flow"=>"kg/s",
                "temperature"=>"K",
                "time"=>"h",
                "money"=>"CNY",
            ),
            "actors"=>actors,
            "devices"=>devices,
            "grid_price"=>fill(100.0, T),
            "settlement"=>prices,
            "electric"=>Dict(
                "nodes"=>3,
                "root"=>1,
                "edges"=>edges,
                "base_MVA"=>10.0,
                "base_kV"=>10.0,
                "grid_max_MW"=>10.0,
                "grid_Q_max_Mvar"=>10.0,
                "v_min_pu"=>0.9,
                "v_max_pu"=>1.1,
                "P_background_MW"=>[zeros(T) for _ in 1:3],
                "Q_background_Mvar"=>[zeros(T) for _ in 1:3],
            ),
            "heat"=>Dict(
                "nodes"=>3,
                "root"=>1,
                "pipes"=>pipes,
                "cp_J_kgK"=>4200.0,
                "delta_min_K"=>20.0,
                "delta_max_K"=>70.0,
                "model"=>"steady_energy_mass_envelope",
                "H_background_MW"=>[fill(reverse && i==1 ? 1.0 : 0.0, T) for i in 1:3],
            ),
        ),
    )
end
