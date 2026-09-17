# Julia入口共用；不改变用户全局Julia配置或许可文件。
let depot = normpath(joinpath(@__DIR__, "..", ".julia"))
    isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
end
using PaperRebuild, JuMP, TOML, Dates, UUIDs, SHA

function r3_gurobi_factory(solver_module)
    environment = solver_module.Env(Dict{String,Any}("OutputFlag"=>0))
    return ()->solver_module.Optimizer(environment)
end

function r3_study_case(entry)
    root = normpath(joinpath(@__DIR__, ".."))
    c = load_r2_case(joinpath(root, "configs", "r2", entry["case"]*".toml"))
    if haskey(entry, "heat_demand_MW") || get(entry, "zero_grid_price", false)
        data = deepcopy(c.data)
        if haskey(entry, "heat_demand_MW")
            for node in data["heat"]["nodes"]
                node["role"]=="load" && (node["H_MW"] .= entry["heat_demand_MW"])
            end
            data["description"] *= " R3容量反例：负荷显式改为10MW，非论文参数。"
        end
        if get(entry, "zero_grid_price", false)
            data["grid_price"] .= 0.0
            data["description"] *= " R3电网锥松弛边界例：免费购电不惩罚网损，非论文参数。"
        end
        io = IOBuffer()
        TOML.print(io, data; sorted = true)
        c = R2Case(data, bytes2hex(sha256(take!(io))))
    end
    init = entry["initialization"]
    initial =
        init=="case_fixed" ? PaperRebuild.r2_flow_matrix(c) :
        init=="low_flow" ? fill(entry["flow_kg_s"], length(c.data["heat"]["pipes"]), c.data["T"]) :
        nothing
    init in ("case_fixed", "low_flow", "schpd") || error("未知初始化")
    return c, initial
end
