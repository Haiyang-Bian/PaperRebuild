# 合成参数生成器；显式 --write 才生成，不覆盖已存在输入。不是论文参数恢复器。
using TOML
root = normpath(joinpath(@__DIR__, ".."))
function r2_fixture(two_sources)
    T = 4
    n = two_sources ? 3 : 2
    electric_nodes = [
        Dict("P_MW" => fill(i == 1 ? 0.0 : 0.2, T), "Q_Mvar" => fill(i == 1 ? 0.0 : 0.02, T))
        for i in 1:n
    ]
    pipes = [
        Dict(
            "from" => i,
            "to" => i+1,
            "area_m2" => 0.01,
            "length_m" => 180.0,
            "epsilon_W_mK" => 0.2,
            "mu_kPa_s2_kg2" => 0.5,
            "flow_min" => i == 1 ? 0.5 : 1.0,
            "flow_max" => i == 1 ? 1.5 : 3.0,
            "flow_history" => fill(i == 1 ? 1.0 : 2.0, 4),
            "S_history_K" => fill(353.0, 4),
            "R_history_K" => fill(313.0, 4),
            "fixed_flow" => fill(i == 1 ? 1.0 : 2.0, T),
        ) for i in 1:(n-1)
    ]
    nodes = [
        Dict(
            "role" => i == n ? "load" : "source",
            "flow_min" => i == n ? (two_sources ? 1.0 : 0.5) : 0.5,
            "flow_max" => i == n && two_sources ? 3.0 : 1.5,
            "return_K" => 313.0,
            "H_MW" => i == n ? (two_sources ? 2.0 : 1.0) .* [0.15, 0.16, 0.17, 0.16] : zeros(T),
        ) for i in 1:n
    ]
    devices = Dict{String,Any}[]
    for i in 1:(n-1)
        push!(
            devices,
            Dict(
                "kind" => "CHP",
                "electric_node" => i+1,
                "heat_node" => i,
                "P_min" => 0.0,
                "P_max" => 0.3,
                "heat_ratio" => 1.5,
                "cost_per_MWh" => 80.0+10i,
                "availability" => fill(0.3, T),
            ),
        )
        push!(
            devices,
            Dict(
                "kind" => "EB",
                "electric_node" => i+1,
                "heat_node" => i,
                "P_min" => 0.0,
                "P_max" => 0.3,
                "heat_ratio" => 0.95,
                "cost_per_MWh" => 0.0,
                "availability" => fill(0.3, T),
            ),
        )
    end
    push!(
        devices,
        Dict(
            "kind" => "PV",
            "electric_node" => n,
            "heat_node" => 0,
            "P_min" => 0.0,
            "P_max" => 0.05,
            "heat_ratio" => 0.0,
            "cost_per_MWh" => 1.0,
            "availability" => [0.0, 0.03, 0.05, 0.01],
        ),
    )
    return Dict(
        "schema" => "r2-case-v1",
        "id" => two_sources ? "two-source" : "single-source",
        "origin" => "synthetic",
        "description" => "项目手查小系统，不是论文原始参数；固定方向、单位功率因数、自由终端热状态。",
        "T" => T,
        "dt_h" => 1.0,
        "ambient_K" => fill(293.0, T),
        "grid_price" => [100.0, 250.0, 250.0, 100.0],
        "units" => Dict(
            "power" => "MW",
            "energy" => "MWh",
            "temperature" => "K",
            "flow" => "kg/s",
            "time" => "h",
            "pressure" => "kPa",
        ),
        "electric" => Dict(
            "nodes" => electric_nodes,
            "base_MVA" => 1.0,
            "base_kV" => 10.0,
            "grid_max_MW" => 2.0,
            "v_min_pu" => 0.95,
            "v_max_pu" => 1.05,
            "edges" => [
                Dict(
                    "from" => i,
                    "to" => i+1,
                    "r_pu" => 0.005,
                    "x_pu" => 0.002,
                    "ell_max_pu" => 4.0,
                ) for i in 1:(n-1)
            ],
        ),
        "heat" => Dict(
            "nodes" => nodes,
            "pipes" => pipes,
            "rho_kg_m3" => 1000.0,
            "cp_J_kgK" => 4200.0,
            "pressure_max_kPa" => 1000.0,
            "S_bounds_K" => [343.0, 363.0],
            "R_bounds_K" => [303.0, 323.0],
            "S_reference_K" => 353.0,
            "R_reference_K" => 313.0,
        ),
        "devices" => devices,
    )
end
if "--write" in ARGS
    mkpath(joinpath(root, "configs", "r2"))
    for two in (false, true)
        d = r2_fixture(two)
        path = joinpath(root, "configs", "r2", d["id"]*".toml")
        ispath(path) && error("拒绝覆盖已冻结输入：$path")
        open(io -> TOML.print(io, d; sorted = true), path, "w")
    end
end
