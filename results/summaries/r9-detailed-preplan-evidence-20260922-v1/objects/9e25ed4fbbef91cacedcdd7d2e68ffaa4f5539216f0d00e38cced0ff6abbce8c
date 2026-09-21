# 从导入前开始计时，Gurobi顶层加载，防止Julia 1.12动态模块世界年龄错误。
const DETAILED_PROCESS_STARTED = time()
using Gurobi, JuMP
include("r9_detailed_preplan_study.jl")
length(ARGS) == 3 || error("usage: run_r9_detailed_preplan.jl INPUT NEW_OUTPUT MODE")
optimizer = optimizer_with_attributes(
    Gurobi.Optimizer,
    "OutputFlag" => 0,
    "Threads" => 1,
    "FeasibilityTol" => 1e-9,
    "IntFeasTol" => 1e-9,
    "OptimalityTol" => 1e-9,
    "MIPGap" => 1e-4,
    "DualReductions" => 0,
)
R9DetailedPreplanStudy.run(
    abspath(ARGS[1]),
    abspath(ARGS[2]),
    ARGS[3],
    optimizer;
    started = DETAILED_PROCESS_STARTED,
)
