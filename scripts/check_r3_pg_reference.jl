push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r3_setup.jl")
using Test, Clarabel, Gurobi
factory=r3_gurobi_factory(Gurobi)
records=Dict{String,Any}[]
@testset "R3 PG same-model commercial reference" begin
    for name in ("single-source", "two-source"), mode in (:dispatch, :diagnostic)
        c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", name*".toml"))
        m=PaperRebuild.r2_flow_matrix(c)*(mode==:diagnostic ? 0.72 : 1.0)
        a=PaperRebuild.r3_solve(
            c,
            ()->build_r3_subproblem(c, m; mode),
            Clarabel.Optimizer;
            sensitivity = true,
        )
        b=PaperRebuild.r3_solve(c, ()->build_r3_subproblem(c, m; mode), factory; sensitivity = true)
        @test a["sensitivity"]["trusted"]
        if !b["sensitivity"]["trusted"]
            println(
                "Gurobi KKT ",
                name,
                " ",
                mode,
                " ",
                [
                    (k, get(b["sensitivity"], k, missing)) for k in
                    ("reason", "primal", "dual", "complementarity", "stationarity", "relative_gap")
                ],
            )
        end
        diff=abs(a["solver_objective"]-b["solver_objective"])/max(1, abs(a["solver_objective"]))
        @test diff<=1e-4
        ga=sum(sum, a["sensitivity"]["gradient"])
        record=Dict{String,Any}(
            "case"=>name,
            "mode"=>string(mode),
            "relative_objective_difference"=>diff,
            "clarabel_directional_gradient"=>ga,
            "gurobi_dual_trusted"=>b["sensitivity"]["trusted"],
            "clarabel_gap"=>a["solver_relative_gap"],
            "gurobi_gap"=>b["solver_relative_gap"],
        )
        if b["sensitivity"]["trusted"]
            gb=sum(sum, b["sensitivity"]["gradient"])
            @test abs(ga-gb)/max(1, abs(ga))<=1e-3
            record["gurobi_directional_gradient"]=gb
        else
            @test !haskey(b["sensitivity"], "gradient")
            record["gurobi_kkt"]=b["sensitivity"]["kkt"]
            record["interpretation"]="primal objective agrees; raw dual rejected; no Gurobi gradient claim"
        end
        push!(records, record)
    end
end
path=joinpath(
    @__DIR__,
    "..",
    "results",
    "runs",
    "r3-pg-reference-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*".toml",
)
open(
    io->TOML.print(
        io,
        Dict("records"=>records, "source_hashes"=>PaperRebuild.r2_science_hashes());
        sorted = true,
    ),
    path,
    "w",
)
println(path)
