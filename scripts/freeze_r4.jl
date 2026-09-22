# 首次求解前冻结；已存在且内容不同就拒绝，不能看到收益后调参覆盖。
using TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
function actor(
    id,
    node;
    CHP = 0.0,
    EB = 0.0,
    HP = 0.0,
    PV = 0.0,
    BS = 0.0,
    P = zeros(4),
    H = zeros(4),
    flex = 0.1,
    cost = 140.0,
)
    return Dict(
        "id"=>id,
        "node"=>node,
        "CHP_max"=>CHP,
        "EB_max"=>EB,
        "HP_max"=>HP,
        "PV_max"=>PV,
        "BS_power_max"=>BS,
        "BS_energy_max"=>2BS,
        "BS_initial"=>BS,
        "CHP_cost"=>cost,
        "PV_cost"=>12.5,
        "BS_cost"=>5.0,
        "sat_P"=>5000.0,
        "sat_H"=>5000.0,
        "heat_ratio"=>1.2,
        "Q_ratio"=>0.2,
        "retail_limit"=>20.0,
        "port_flow_max"=>100.0,
        "COP_HP"=>3.0,
        "COP_EB"=>0.95,
        "eta_ch"=>0.95,
        "eta_dis"=>0.95,
        "P_load"=>P,
        "H_load"=>H,
        "flex"=>flex,
        "PV_profile"=>[0.0, 0.6, 1.0, 0.2],
    )
end
base=Dict(
    "schema"=>"r4-case-v1",
    "origin"=>"synthetic",
    "name"=>"base",
    "T"=>4,
    "dt_h"=>1.0,
    "description"=>"R4教学合成数据；非作者原始参数；优化前冻结。",
    "units"=>Dict(
        "power"=>"MW",
        "energy"=>"MWh",
        "time"=>"h",
        "mass_flow"=>"kg/s",
        "temperature"=>"K",
        "money"=>"USD_synthetic",
    ),
    "p2p_enabled"=>true,
    "grid_price"=>[80.0, 140.0, 100.0, 80.0],
    "actors"=>[
        actor("DSO", 1; CHP = 0.3, EB = 0.2, flex = 0.0, cost = 180.0),
        actor(
            "A",
            2;
            HP = 0.1,
            PV = 0.45,
            BS = 0.1,
            P = [0.2, 0.25, 0.2, 0.2],
            H = [0.1, 0.12, 0.1, 0.1],
        ),
        actor("B", 3; CHP = 0.15, EB = 0.1, P = [0.25, 0.3, 0.25, 0.25], H = [0.2, 0.25, 0.2, 0.2]),
    ],
    "settlement"=>Dict(
        "P_buy"=>200.0,
        "P_sell"=>60.0,
        "H_buy"=>160.0,
        "H_sell"=>40.0,
        "P_peer"=>130.0,
        "H_peer"=>100.0,
        "fee"=>5.0,
    ),
    "electric"=>Dict(
        "S_base_MVA"=>1.0,
        "V_base_kV"=>10.0,
        "grid_max"=>2.0,
        "Q_grid_max"=>2.0,
        "v_min"=>0.95,
        "v_max"=>1.05,
        "edges"=>[
            Dict(
                "from"=>i,
                "to"=>i+1,
                "r"=>0.01,
                "x"=>0.01,
                "P_max"=>0.6,
                "Q_max"=>0.6,
                "ell_max"=>4.0,
            ) for i in 1:2
        ],
    ),
    "heat"=>Dict(
        "cp"=>4180.0,
        "source_delta_min"=>20.0,
        "source_delta_max"=>60.0,
        "load_delta_min"=>10.0,
        "load_delta_max"=>40.0,
        "pipes"=>[
            Dict(
                "from"=>i,
                "to"=>i+1,
                "flow_max"=>10.0,
                "H_max"=>0.6,
                "U_W_mK"=>0.2,
                "length_m"=>90.0,
                "S_ref_K"=>353.15,
                "R_ref_K"=>313.15,
                "ambient_K"=>283.15,
            ) for i in 1:2
        ],
    ),
)
function freeze(path, d)
    io=IOBuffer()
    TOML.print(io, d; sorted = true)
    text=String(take!(io))
    isfile(path) && read(path, String)!=text && error("拒绝覆盖已冻结文件: "*path)
    mkpath(dirname(path))
    isfile(path) || write(path, text)
    return bytes2hex(sha256(text))
end
entries=Dict{String,Any}[]
for name in (
    "base",
    "electric_bottleneck",
    "heat_bottleneck",
    "no_p2p",
    "fixed_load",
    "capacity_infeasible",
)
    d=deepcopy(base)
    d["name"]=name
    name=="electric_bottleneck" && (d["electric"]["edges"][2]["P_max"]*=0.25)
    name=="heat_bottleneck" && (d["heat"]["pipes"][2]["H_max"]*=0.25)
    name=="no_p2p" && (d["p2p_enabled"]=false)
    name=="fixed_load" && foreach(a->a["flex"]=0.0, d["actors"])
    name=="capacity_infeasible" && (d["actors"][3]["H_load"]=fill(10.0, 4))
    hash=freeze(joinpath(root, "configs", "r4", name*".toml"), d)
    push!(entries, Dict("name"=>name, "sha256"=>hash))
end
freeze(
    joinpath(root, "configs", "r4", "study.toml"),
    Dict(
        "schema"=>"r4-study-v1",
        "case"=>entries,
        "variants"=>["independent_exact", "central_socp", "central_exact"],
        "budget_sec"=>600,
        "bottleneck_factor"=>0.25,
        "seed"=>23,
        "threads"=>1,
        "gurobi_feasibility_tol"=>1e-9,
        "gurobi_optimality_tol"=>1e-9,
        "gurobi_MIPGap"=>1e-6,
        "clarabel_tol"=>1e-9,
        "freeze_rule"=>"输入先于任何本批优化；无收益驱动的调参。",
    ),
)
println("R4: six cases frozen and hashed.")
