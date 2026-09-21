using Test, PaperRebuild
VERSION==v"1.12.6" || error("Expected Julia 1.12.6")
isempty(ARGS) ||
    (length(ARGS)==2 && first(ARGS)=="--gurobi") ||
    error("usage: test_r9_trading_runs.jl [--gurobi NEW_DIRECTORY]")
if isempty(ARGS)
    include(joinpath(@__DIR__, "..", "test", "r9_trading_runs.jl"))
else
    # 本机可选小例，不能当作44/38节点正式结果或跨求解器速度结论。
    include(joinpath(@__DIR__, "r3_setup.jl"))
    using Gurobi
    include(joinpath(@__DIR__, "..", "test", "fixtures", "r9_trading.jl"))
    folder=abspath(last(ARGS))
    ispath(folder) && error("Do not overwrite development evidence")
    mkpath(folder)
    environment=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    attributes=Dict{String,Any}(
        "Threads"=>1,
        "Seed"=>0,
        "NonConvex"=>2,
        "MIPGap"=>1e-4,
        "FeasibilityTol"=>1e-8,
        "OptimalityTol"=>1e-8,
        "IntFeasTol"=>1e-8,
    )
    optimizer=optimizer_with_attributes(()->Gurobi.Optimizer(environment), collect(attributes)...)
    c=r9_trading_fixture(; store = true)
    write(joinpath(folder, "input.toml"), c.source_text)
    write(joinpath(folder, "solver-options.toml"), PaperRebuild.r4_text(attributes))
    cp(@__FILE__, joinpath(folder, "test-source.jl"))
    cp(joinpath(@__DIR__, "r3_setup.jl"), joinpath(folder, "setup-source.jl"))
    cp(
        joinpath(@__DIR__, "..", "test", "fixtures", "r9_trading.jl"),
        joinpath(folder, "fixture-source.jl"),
    )
    @testset "R9 Gurobi small workflow, not scale reproduction" begin
        for operation in (:central, :independent), electric in (:socp, :exact)
            start=PaperRebuild.r3_clock()
            r=solve_r9_trading_case(
                c;
                optimizer,
                operation,
                electric,
                budget_sec = 60.0,
                deadline = start+60,
            )
            id=string(operation)*"-"*string(electric)
            path=save_r9_trading_run(c, r; directory = folder, run_id = id)
            println(
                id,
                ": ",
                r["status"],
                "; model=",
                r["validation"]["model_pass"],
                "; original=",
                r["validation"]["electric_original_pass"],
                "; objective=",
                get(r, "system_cost_CNY", "unavailable"),
            )
            @test r["validation"]["model_pass"] && r["validation"]["heat_energy_mass_pass"]
            @test r["validation"]["ledger_pass"]
            @test r["system_cost_CNY"]≈100.0 atol=1e-4
            @test r["wall_budget_pass"]
            electric==:exact && @test r["validation"]["electric_original_pass"]
            @test read_r9_trading_run(path; frozen = false).validation==r["validation"]
        end
    end
end
