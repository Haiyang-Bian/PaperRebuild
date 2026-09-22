using PaperRebuild, Gurobi, Test, TOML
using JuMP

length(ARGS) == 1 || error("传入已完成的 Clarabel 运行目录")
saved = read_r1_run(ARGS[1])
r = solve_r1_case(
    saved.case;
    optimizer = optimizer_with_attributes(
        Gurobi.Optimizer,
        "MIPGap" => 1e-9,
        "FeasibilityTol" => 1e-9,
        "OptimalityTol" => 1e-9,
        "BarConvTol" => 1e-10,
        "BarQCPConvTol" => 1e-10,
    ),
    enumerate_modes = false,
)
r["solver_settings"] = Dict(
    "MIPGap" => 1e-9,
    "FeasibilityTol" => 1e-9,
    "OptimalityTol" => 1e-9,
    "BarConvTol" => 1e-10,
    "BarQCPConvTol" => 1e-10,
)
dir = save_r1_run(saved.case, r)
println("Gurobi comparison run: ", dir)
report = validate_r1_solution(saved.case, r)
@testset "R1 Gurobi vs four-mode Clarabel" begin
    @test r["status"] == "solver_optimal"
    @test report.relaxed_pass
    @test report.original_branch_pass
    @test abs(r["objective"] - saved.result["objective"]) <=
          1e-4 * max(1, abs(saved.result["objective"]))
end
println("Gurobi comparison run: ", dir)
