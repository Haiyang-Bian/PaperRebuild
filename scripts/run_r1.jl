using PaperRebuild
using Clarabel

casepath = isempty(ARGS) ? joinpath(@__DIR__, "..", "configs", "r1", "micro.toml") : ARGS[1]
c = load_case(casepath)
r = solve_r1_case(c; optimizer = Clarabel.Optimizer)
dir = save_r1_run(c, r)
println("Run: ", dir)
println("Solver status: ", r["status"])
report = validate_r1_solution(c, r)
println(
    "Relaxed model: ",
    report.relaxed_pass,
    "; original branch equality: ",
    report.original_branch_pass,
)
r["status"] == "solver_optimal" && report.relaxed_pass ||
    error("R1 求解或模型验证未通过；已保留运行记录")
