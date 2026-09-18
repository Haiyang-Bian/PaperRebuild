using PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA, Dates

function r5_market_optimizer(which::Symbol)
    if which==:highs
        return optimizer_with_attributes(
            HiGHS.Optimizer,
            "threads"=>1,
            "primal_feasibility_tolerance"=>1e-9,
            "dual_feasibility_tolerance"=>1e-9,
        )
    elseif which==:clarabel
        return optimizer_with_attributes(
            Clarabel.Optimizer,
            "tol_feas"=>1e-10,
            "tol_gap_abs"=>1e-10,
            "tol_gap_rel"=>1e-10,
        )
    elseif which==:gurobi
        path=normpath(joinpath(@__DIR__, "..", "tools", "solvers"))
        path in LOAD_PATH || push!(LOAD_PATH, path)
        @eval using Gurobi
        return Base.invokelatest(r5_market_gurobi_factory)
    end
    error("未知市场求解器")
end

function r5_market_gurobi_factory()
    environment=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    optimizer_with_attributes(
        ()->Gurobi.Optimizer(environment),
        "Threads"=>1,
        "Seed"=>23,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
    )
end
