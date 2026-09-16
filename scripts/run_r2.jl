# 如存在项目本地缓存则使用它；不改变全局默认版本或用户环境配置。
let depot = normpath(joinpath(@__DIR__, "..", ".julia"))
    isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
end
using PaperRebuild, TOML
include("r2_setup.jl")
root = normpath(joinpath(@__DIR__, ".."))
file = isempty(ARGS) ? "single-source" : ARGS[1]
form = length(ARGS) < 2 ? :wmm_checked_v1 : Symbol(ARGS[2])
fixed = "--fixed" in ARGS
open_solver = "--open" in ARGS
c = load_r2_case(joinpath(root, "configs", "r2", file*".toml"))
spec = R2Spec(; formulation = form)
budget = "--smoke" in ARGS ? 60.0 : 600.0
if form in (:wmm_literal, :schpd_literal)
    factory = nothing
elseif open_solver
    @eval import Clarabel
    factory = Clarabel.Optimizer
else
    try
        @eval import Gurobi
        global environment = Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    catch err
        state = r2_setup_status(err)
        isnothing(state) && rethrow()
        result = r2_setup_failure(c, spec, state; fixed_flows = fixed, budget_sec = budget)
        dir = save_r2_run(c, result; root = joinpath(root, "results", "runs"))
        println("R2_RUN=", relpath(dir, root), " status=", state)
        exit(1)
    end
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
