# 如存在项目本地缓存则使用它；不改变全局默认版本或用户环境配置。
let depot = normpath(joinpath(@__DIR__, "..", ".julia"))
    isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
end
using PaperRebuild, TOML
root = normpath(joinpath(@__DIR__, ".."))
file = isempty(ARGS) ? "single-source" : ARGS[1]
form = length(ARGS) < 2 ? :wmm_checked_v1 : Symbol(ARGS[2])
fixed = "--fixed" in ARGS
open_solver = "--open" in ARGS
c = load_r2_case(joinpath(root, "configs", "r2", file*".toml"))
spec = R2Spec(; formulation = form)
if open_solver
    @eval import Clarabel
    factory = Clarabel.Optimizer
else
    @eval import Gurobi
    environment = Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    factory =
        () -> begin
            optimizer = Gurobi.Optimizer(environment)
            for (key, value) in (
                "OutputFlag"=>0,
                "Threads"=>1,
                "Seed"=>0,
                "NonConvex"=>2,
                "FeasibilityTol"=>1e-9,
                "OptimalityTol"=>1e-9,
                "BarConvTol"=>1e-10,
                "MIPGap"=>1e-6,
            )
                Gurobi.MOI.set(optimizer, Gurobi.MOI.RawOptimizerAttribute(key), value)
            end
            optimizer
        end
end
budget = "--smoke" in ARGS ? 60.0 : 600.0
result = solve_r2_case(
    c;
    optimizer = factory,
    spec,
    fixed_flows = fixed,
    enumerate_mixing = open_solver,
    budget_sec = budget,
)
dir = save_r2_run(c, result; root = joinpath(root, "results", "runs"))
println("R2_RUN=", relpath(dir, root))
println("status=", result["status"], " objective=", get(result, "objective", "missing"))
report = validate_r2_solution(c, result)
println("validation=", report.status, " model_pass=", report.model_pass)
for row in filter(r -> r.scope == "model" && !r.pass, report.rows)[1:min(end, 10)]
    println(row)
end
