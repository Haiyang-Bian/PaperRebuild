using PaperRebuild, JuMP, Gurobi, Test, TOML
include("r8_cases.jl")
length(ARGS)==1 || error("usage: test_r8_gurobi.jl NEW_OUTPUT")
dest=abspath(only(ARGS))
ispath(dest)&&error("不覆盖开发记录")
mkpath(dest)
opt=optimizer_with_attributes(
    Gurobi.Optimizer,
    "Threads"=>1,
    "NonConvex"=>2,
    "FeasibilityTol"=>1e-9,
    "OptimalityTol"=>1e-9,
    "IntFeasTol"=>1e-9,
    "MIPGap"=>1e-8,
    "DualReductions"=>0,
)
@testset "R8 independent nonconvex and resource development" begin
    for (id, family, resource, control, mode) in (
        ("tie_fixed", "tie_three", "all", "fixed", :threshold),
        ("tie_forest", "tie_three", "no_reconfiguration", "fixed", :threshold),
        ("lossy_free", "legacy", "all", "joint_continuous", :economic),
    )
        x=r8_mechanism_input(normpath(joinpath(@__DIR__, "..")), family; resource, control)
        s=r8_spec(
            x.case,
            x.flow;
            mode,
            limits_MWh = [0.4, 0.4],
            topology = x.topology,
            heat_preparation = x.heat_preparation,
        )
        write(
            joinpath(dest, id*"-input.toml"),
            PaperRebuild.r7_text(
                Dict(
                    "normal"=>x.case.normal.data,
                    "planning"=>x.case.specification,
                    "flow"=>x.flow,
                    "spec"=>s,
                    "budget_sec"=>60.0,
                ),
            ),
        )
        r=solve_r8_case(x.case, x.flow, s; optimizer = opt, budget_sec = 60)
        save_r8_run(x.case, x.flow, s, r, joinpath(dest, id))
        println(
            id,
            " primary=",
            r["primary"]["status"],
            " ",
            get(r["primary"], "error", ""),
            " eval=",
            get(get(r, "evaluation", Dict()), "status", "missing"),
            " ",
            get(get(r, "evaluation", Dict()), "error", ""),
        )
        @test read_r8_run(joinpath(dest, id)).result["run_id"]==r["run_id"]
        @test !r["full_thesis_domain_verified"]
        @test r["primary"]["status"] in (
            "candidate",
            "time_limit_with_solution",
            "time_limit_no_solution",
            "budget_exhausted",
            "infeasible_certified",
        )
        if r["validation"]["recovery_verified"]
            @test all(w["model_pass"] for w in r["validation"]["evaluation"]["witness_checks"])
        end
    end
end
